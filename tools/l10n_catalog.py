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

Registry-bound seam (R union of #147, at the end of this file):

    parse_registry_declarations(source: bytes) -> dict
        semantic key -> declaration, from the declaration block of the bytes
        of core/Localization.lua, parsed without executing Lua
    validate_registry_catalog_data(english, packs, key context, release,
                                   localization: bytes) -> dict
    registry_catalog_report(the same five byte strings) -> dict
        report schemaVersion 2; the four-input API keeps schemaVersion 1
    CatalogRegistryError
        .code (stable, one of REGISTRY_CODES), .path and .key

Opt-in diagnostic seam (S6 of #147, after the registry-bound seam):

    registry_catalog_diagnostics(the same five byte strings) -> dict
        a read-only diagnostic receipt that never raises for catalog data:
        the unchanged strict verdict, every independent invalid, obsolete
        and orphan pack entry when the rest of the catalog is trustworthy,
        else an explicit incomplete-collection boundary. It is not a gate.
    CatalogDiagnosticError
        .code (stable, one of DIAGNOSTIC_CODES), .path and .key

Opt-in provenance seam (S7 of #147, at the end of this file):

    pack_provenance_diagnostics(the same five byte strings) -> dict
        a read-only provenance receipt that never raises for catalog or
        metadata data: the unchanged catalog verdict, the technical validity
        of the per-pack provenance records in RELEASE_LANGUAGES.json, each
        declared English base as UNKNOWN, MATCHED or STALE against the exact
        supplied English bytes, and attested facts NOT_ESTABLISHED with
        support HELD. A STALE base or malformed record makes it invalid.
    CatalogProvenanceError
        .code (stable, one of PROVENANCE_CODES), .path and .key

Static consumer binding seam (S8 of #147, after the provenance seam):

    consumer_binding_report(the same five byte strings, toc_records,
                            source_records) -> dict
        a read-only binding receipt over the Lua source the two product
        TOCs load: each declared key is DIRECT_LITERAL_CONSUMER,
        MAPPED_TO_CONSUMER or UNBOUND by a bounded syntactic check that never
        executes Lua and counts a site only when its result reaches an
        output, with unresolved, orphan, kind and mutation problems kept
        explicit; valid only without any problem. Each record is {"path",
        "sha256", "byteLength", "data"}, and the claims are checked against
        the data.
    CatalogConsumerError
        .code (stable, one of CONSUMER_CODES), .path, .line and .subject

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

    python tools/l10n_catalog.py [--root DIR] [--require-complete] [--registry]
                                 [--diagnose | --provenance | --consumers]

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
executed, fetched or read from Git. With --registry, core/Localization.lua is also read as bytes under the
same root rules and the registry-bound report v2 replaces the report; the
record then carries registryBinding "requested". With --diagnose,
core/Localization.lua is read the same way and one diagnostics record with
the registry_catalog_diagnostics receipt is written on stdout instead; its
exit status is 2 while the catalog is invalid or the collection is
incomplete, else 0, or 1 with --require-complete. With --provenance,
core/Localization.lua is read the same way and one provenance record with
the pack_provenance_diagnostics receipt is written on stdout; its exit
status is 2 while the receipt is invalid, else 0, or 1 with
--require-complete, because support is always held. With --consumers,
core/Localization.lua, companion/NexusSupport/NexusSupport.toc and every Lua
file the two TOCs load (each entry a safe relative .lua path) are read the
same way and one consumers record with the consumer_binding_report receipt
is written on stdout; its exit status is 2 while the receipt is invalid,
else 0, or 1 with --require-complete. Any two of --diagnose, --provenance and
--consumers together are argument-conflict. Python 3.9+, standard library
only.
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
# The four-input API's fixed format schema as {key: (fields, result limit)}.
# The registry-bound API (end of this file) passes the parsed declarations
# instead and never reads these constants.
_V1_FORMATS = types.MappingProxyType({key: (fields, _FORMAT_LIMITS[key])
                                      for key, fields in _FORMAT_FIELDS.items()})
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


def _check_value(text, key, path, formats=_V1_FORMATS):
    schema = formats.get(key)
    if schema is None:
        _require(_valid_text(text), 'invalid-text', path, key)
    else:
        _require(_valid_template(text, schema[0]), 'invalid-template', path, key)


def _slots_match(placeholders, fields):
    names = []
    for slot in placeholders:
        if type(slot) is not dict or set(slot) != {'name', 'type'}:
            return False
        if type(slot['name']) is not str or slot['type'] != _SLOT_TYPE:
            return False
        names.append(slot['name'])
    return len(names) == len(fields) and set(names) == set(fields)


def _check_english(english, formats=_V1_FORMATS):
    _require(len(english) > 0, 'english-empty', 'english')
    _require(len(english) <= _MAX_BASE_ENTRIES, 'english-too-many', 'english')
    for key, text in english.items():
        _require(_valid_key(key), 'invalid-key', 'english', key)
        _check_value(text, key, 'english', formats)


def _check_context(document, english, formats=_V1_FORMATS):
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
        schema = formats.get(key)
        fields = None if schema is None else schema[0]
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
            _require(_is_int(row.get('resultLimitBytes'), schema[1]),
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


def _check_pack_set(packs, products):
    """Within the runtime pack limit, no English pack and exactly the
    selected optional products."""
    where = 'packs'
    _require(len(packs) <= _MAX_LANGUAGES, 'pack-count', where)
    _require(_ENGLISH_ID not in packs, 'pack-english', where, _ENGLISH_ID)
    for pack_id in packs:
        _require(pack_id in products and pack_id != _ENGLISH_ID, 'pack-unknown', where, pack_id)
    for product_id in products:
        _require(product_id == _ENGLISH_ID or product_id in packs, 'pack-missing', where,
                 product_id)


def _check_pack_shape(pack_id, pack):
    """The autonym and entry count of one pack. Returns the entries path."""
    path = 'packs[%r]' % (pack_id,)
    _require(_valid_text(pack['name'], _MAX_NAME_BYTES), 'invalid-autonym', path + '.name',
             pack_id)
    _require(len(pack['entries']) <= _MAX_BASE_ENTRIES, 'pack-too-many-entries',
             path + '.entries', pack_id)
    return path + '.entries'


def _check_entry(key, text, english, path, formats):
    """One pack entry: a valid key of the English base with valid text."""
    _require(_valid_key(key), 'invalid-key', path, key)
    _require(key in english, 'orphan-entry', path, key)
    _check_value(text, key, path, formats)


def _check_pack_autonym(pack_id, pack, products):
    product_path, product = products[pack_id]
    _require(product['autonym'] == pack['name'], 'release-autonym', product_path + '.autonym',
             pack_id)


def _check_packs(packs, english, products, formats=_V1_FORMATS):
    """The packs: within the runtime pack limit, no English pack, exactly the
    selected optional products, each autonym and entry inside the contract
    and each autonym equal to the release metadata. A missing entry is valid
    partial data and is not replaced by English."""
    _check_pack_set(packs, products)
    for pack_id, pack in packs.items():
        path = _check_pack_shape(pack_id, pack)
        for key, text in pack['entries'].items():
            _check_entry(key, text, english, path, formats)
        _check_pack_autonym(pack_id, pack, products)


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
# because validate_catalog_data rejects such input before any report exists;
# only the opt-in diagnostic receipt (S6, end of this file) fills them.
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


def _classify(ordered, english, entries, decisions, product_id, problems=None):
    """One category list per ENTRY_CATEGORIES name for one optional pack.
    problems, from the diagnostics only, is (invalid keys, obsolete keys):
    an invalid entry is invalid before any declaration applies."""
    invalid = problems[0] if problems else ()
    keys = {category: [] for category in ENTRY_CATEGORIES}
    for key in ordered:
        if key not in entries:
            category = 'missing'
        elif key in invalid:
            category = 'invalid'
        elif (product_id, key) in decisions:
            category = _DECISIONS[decisions[(product_id, key)]]
        elif entries[key] == english[key]:
            category = 'deliberate_english_placeholder'
        else:
            category = 'draft_unreviewed'
        keys[category].append(key)
    if problems:
        keys['obsolete'] = list(problems[1])
    else:
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
    sources = (english_source, packs_source, key_context_json, release_json)
    validated = validate_catalog_data(*sources)
    return _coverage_report(validated, sources, _REPORT_INPUTS, REPORT_SCHEMA_VERSION,
                            NOTICE['validationScope'])


def _input_rows(input_names, sources):
    """One row per (name, source) of input_names with the SHA-256 and length
    of its exact bytes in sources."""
    return [{'name': name, 'source': source, 'sha256': hashlib.sha256(bytes(data)).hexdigest(),
             'byteLength': len(data)} for (name, source), data in zip(input_names, sources)]


def _coverage_report(validated, sources, input_names, schema_version, scope, problems=None):
    """The report derivation shared by catalog_report and the registry-bound
    registry_catalog_report: the evidence and metadata checks, then the
    report of validated data, with one input row per (name, source) of
    input_names and its exact bytes in sources. problems, passed only by the
    diagnostics, maps an optional product ID to its (invalid keys, obsolete
    keys)."""
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
    inputs = _input_rows(input_names, sources)
    reasons, lists, rows = [], {}, []
    for item in optional:
        product_id = item['productId']
        entries = packs[product_id]['entries']
        keys = _classify(ordered, english, entries, decisions, product_id,
                         problems[product_id] if problems else None)
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
        'schemaVersion': schema_version,
        'tool': _TOOL_PATH,
        'status': STATUS,
        'fullValidation': NOTICE['fullValidation'],
        'validationScope': scope,
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
    'argument-conflict',
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
    """Return (root or None, require_complete, registry, diagnose,
    provenance, consumers). Only --root DIR, --root=DIR, --require-complete,
    --registry, --diagnose, --provenance and --consumers are accepted, each
    at most once, and at most one of --diagnose, --provenance and
    --consumers."""
    root, seen, index = None, set(), 0
    while index < len(arguments):
        argument, position = arguments[index], index
        index += 1
        if argument in ('--require-complete', '--registry', '--diagnose', '--provenance',
                        '--consumers'):
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
        if value == '':
            raise CatalogCliError('argument-missing-value', name)
        if value is not None:
            root = value
    if '--diagnose' in seen and '--provenance' in seen:
        raise CatalogCliError('argument-conflict', '--provenance')
    if '--consumers' in seen and ('--diagnose' in seen or '--provenance' in seen):
        raise CatalogCliError('argument-conflict', '--consumers')
    return (root, '--require-complete' in seen, '--registry' in seen, '--diagnose' in seen,
            '--provenance' in seen, '--consumers' in seen)


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


def _cli_toc_row(data, entries):
    return {'name': 'toc', 'source': _TOC_SOURCE, 'sha256': hashlib.sha256(data).hexdigest(),
            'byteLength': len(data), 'requiredOrder': entries, 'scope': _TOC_SCOPE}


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


def _error_fields(error):
    """The stable class and code of error and its known location fields."""
    fields = {'errorClass': type(error).__name__, 'code': error.code}
    for field in ('subject', 'path', 'key', 'line', 'column'):
        value = getattr(error, field, None)
        if value is not None:
            fields[field] = value if type(value) in (str, int) else repr(value)
    return fields


def _cli_error(error):
    """One error record with the stable class and code of error."""
    record = {'schema': CLI_SCHEMA, 'schemaVersion': CLI_SCHEMA_VERSION, 'record': 'error',
              'tool': _TOOL_PATH, 'status': STATUS, 'exitCode': _EXIT_ERROR}
    record.update(_error_fields(error))
    return record


def _cli_emit(stream, record):
    """Write one record as one line of sorted ASCII JSON, as exact bytes."""
    stream.buffer.write(json.dumps(record, sort_keys=True).encode('ascii') + b'\n')
    stream.buffer.flush()


def main(argv=None) -> int:
    """The read-only report command line described in the module documentation:

        python tools/l10n_catalog.py [--root DIR] [--require-complete] [--registry]
                                     [--diagnose | --provenance | --consumers]

    Exactly one ASCII JSON record is written: a report on stdout or an error
    on stderr. The return value is 0 for a valid report, also for partial
    data; 1 with --require-complete while external readiness is not
    established; 2 for an argument, root, input, TOC, syntax, schema,
    registry or evidence error. Without --registry the record is unchanged
    (report schemaVersion 1). With it, core/Localization.lua is read as a
    sixth fixed input and the report is registry_catalog_report
    (schemaVersion 2), marked registryBinding "requested". With --diagnose a
    diagnostics record is written on stdout instead (_cli_diagnostics), with
    --provenance a provenance record (_cli_provenance) and with --consumers
    a consumers record (_cli_consumers)."""
    arguments = sys.argv[1:] if argv is None else list(argv)
    try:
        root, require_complete, registry, diagnose, provenance, consumers = \
            _cli_arguments(arguments)
        resolved = _cli_root(_DEFAULT_ROOT if root is None else root)
        data = [_cli_read(resolved, source) for source in _CLI_INPUTS]
        if registry or diagnose or provenance or consumers:
            localization = _cli_read(resolved, _AUTHORITY)
        toc_entries = _cli_toc(data[-1])
        if consumers:
            return _cli_consumers(resolved, data, localization,
                                  _cli_toc_row(data[-1], toc_entries), require_complete)
        if diagnose:
            return _cli_diagnostics(registry_catalog_diagnostics(*data[:-1], localization),
                                    _cli_toc_row(data[-1], toc_entries), require_complete)
        if provenance:
            return _cli_provenance(pack_provenance_diagnostics(*data[:-1], localization),
                                   _cli_toc_row(data[-1], toc_entries), require_complete)
        if registry:
            report = registry_catalog_report(*data[:-1], localization)
        else:
            report = catalog_report(*data[:-1])
    except _CLI_FAILURES + (CatalogRegistryError, CatalogConsumerError) as error:
        _cli_emit(sys.stderr, _cli_error(error))
        return _EXIT_ERROR
    blocking, readiness = _cli_readiness(report)
    exit_code = _EXIT_NOT_ESTABLISHED if require_complete and blocking else _EXIT_REPORT
    record = {
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
        'toc': _cli_toc_row(data[-1], toc_entries),
        'technicalCatalog': _cli_technical(report),
        'externalReadiness': readiness,
        'report': report,
    }
    if registry:
        record['registryBinding'] = 'requested'
    _cli_emit(sys.stdout, record)
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


# ---------------------------------------------------------------------------
# R union (Refs #147, slices S2 and S5): the registry-bound catalog.
# core/Localization.lua owns one literal declaration table, DECLARATIONS,
# between the exact lines _REGISTRY_OPEN and _REGISTRY_CLOSE (the S1 marker
# contract: the token appears in exactly those two whole lines, BEGIN
# first). The runtime admits English only for a declared key in its declared
# kind and derives its format schemas from the declarations.
#
# parse_registry_declarations reads those bytes without evaluating,
# importing or executing Lua. Between the markers, after Lua 5.1 whitespace
# and comments, the only accepted form is
#
#     local DECLARATIONS = { ["key"] = <declaration>, ... }
#
# in the restricted literal-table grammar of _parse_literal_table above, so
# an expression, call, variable, operator, computed key, semicolon or second
# statement is a CatalogSyntaxError with an existing CODES code and a
# repeated key is duplicate-key. Each declaration must be exactly
# {kind = "text"} or exactly {kind = "format", fields = {"name", ...},
# slot = "count", resultLimit = 254}: one or more distinct lower-case field
# names, the count slot type and the runtime's MAX_TEXT_BYTES - 2 limit. Any
# other declaration, key or count is a CatalogRegistryError (REGISTRY_CODES).
# The runtime leaves such a declaration out at load; offline it fails.
#
# validate_registry_catalog_data and registry_catalog_report are the
# five-input registry-bound API and report schemaVersion 2. They take the
# exact bytes of the four catalog inputs plus core/Localization.lua, and the
# parsed declarations, never _FORMAT_FIELDS or _FORMAT_LIMITS, govern the
# English, pack and key-context checks. They add: every English key is
# declared (undeclared-entry), every declared key has English
# (english-incomplete), and each key-context row's kind, placeholder names in
# order with their type, and result limit equal its declaration
# (context-declaration-mismatch). validate_catalog_data and catalog_report
# above keep four inputs, report schemaVersion 1 and their scoped label; they
# are not registry validation. Nothing here reads a file: main() passes the
# sixth fixed input only when --registry is given.

REGISTRY_CODES = (
    'registry-marker', 'registry-structure', 'registry-too-many', 'registry-key',
    'registry-kind', 'registry-field', 'registry-placeholders', 'registry-slot',
    'registry-limit', 'undeclared-entry', 'english-incomplete',
    'context-declaration-mismatch',
)
REGISTRY_REPORT_SCHEMA_VERSION = 2
REGISTRY_SCOPE = (
    'Registry-bound scoped draft: the English base, the packs and the key-context rows are '
    'checked against the declarations of core/Localization.lua, parsed without executing Lua, '
    'for the currently declared static keys and the single charge-count template; not whole '
    '#147. Plural variants, dynamic-key coverage per family, runtime load/fallback parity, '
    'per-pack translator provenance/rights and approved terminology validation are not '
    'implemented by this component.')
_REGISTRY_TOKEN = 'NEXUS-L10N-REGISTRY'
_REGISTRY_OPEN = '-- NEXUS-L10N-REGISTRY BEGIN'
_REGISTRY_CLOSE = '-- NEXUS-L10N-REGISTRY END'
_REGISTRY_TABLE = 'DECLARATIONS'
_TEXT_DECLARATION = frozenset(('kind',))
_FORMAT_DECLARATION = frozenset(('kind', 'fields', 'slot', 'resultLimit'))
_FIELD_NAME = re.compile('[a-z][a-z0-9_]*')
_REGISTRY_INPUTS = _REPORT_INPUTS + (('localization', _AUTHORITY),)
_NONEXECUTION = 'declarations are parsed from the supplied bytes; no Lua is executed'


class CatalogRegistryError(ValueError):
    """Raised for a missing or malformed declaration block, a malformed
    declaration, or registry-bound catalog data that disagrees with the
    declarations. It carries a stable code (one of REGISTRY_CODES) and, when
    known, the path in the input and the key concerned."""

    def __init__(self, code: str, path: str = None, key=None):
        detail = '' if path is None else ' at ' + path
        if key is not None:
            detail += ' (%r)' % (key,)
        super().__init__(code + detail)
        self.code, self.path, self.key = code, path, key


def _registry(condition, code, path, key=None):
    if not condition:
        raise CatalogRegistryError(code, path, key)


def _declaration_block(text):
    """The text between the two marker lines, preceded by one newline per
    earlier line so token line numbers stay those of the whole source."""
    lines = [line[:-1] if line.endswith('\r') else line for line in text.split('\n')]
    opens = [index for index, line in enumerate(lines) if line == _REGISTRY_OPEN]
    closes = [index for index, line in enumerate(lines) if line == _REGISTRY_CLOSE]
    _registry(len(opens) == 1 and len(closes) == 1 and opens[0] < closes[0]
              and text.count(_REGISTRY_TOKEN) == 2, 'registry-marker', _AUTHORITY)
    return '\n' * (opens[0] + 1) + '\n'.join(lines[opens[0] + 1:closes[0]])


def _declaration(key, value):
    """One checked declaration as {'kind': 'text'} or {'kind': 'format',
    'fields': (names...), 'slot': 'count', 'resultLimit': 254}."""
    path = '%s[%r]' % (_REGISTRY_TABLE, key)
    _registry(_valid_key(key), 'registry-key', path, key)
    _registry(type(value) is dict and value, 'registry-structure', path, key)
    kind = value.get('kind')
    _registry(kind in ('text', 'format'), 'registry-kind', path + '.kind', key)
    if kind == 'text':
        _registry(set(value) == _TEXT_DECLARATION, 'registry-field', path, key)
        return {'kind': 'text'}
    _registry(set(value) == _FORMAT_DECLARATION, 'registry-field', path, key)
    fields = value['fields']
    _registry(type(fields) is list and fields and len(set(map(repr, fields))) == len(fields)
              and all(type(name) is str and len(name) <= _MAX_KEY_BYTES
                      and _FIELD_NAME.fullmatch(name) is not None for name in fields),
              'registry-placeholders', path + '.fields', key)
    _registry(value['slot'] == _SLOT_TYPE, 'registry-slot', path + '.slot', key)
    _registry(_is_int(value['resultLimit'], _MAX_TEXT_BYTES - 2), 'registry-limit',
              path + '.resultLimit', key)
    return {'kind': 'format', 'fields': tuple(fields), 'slot': _SLOT_TYPE,
            'resultLimit': value['resultLimit']}


def parse_registry_declarations(source: bytes) -> dict:
    """Parse the declaration block of the exact bytes of core/Localization.lua
    into {key: declaration} in source order (grammar above). The source is
    never evaluated, imported or executed. A syntax failure raises
    CatalogSyntaxError (CODES); a marker or declaration failure raises
    CatalogRegistryError (REGISTRY_CODES)."""
    if not isinstance(source, (bytes, bytearray)):
        raise TypeError('source must be bytes, not %s' % type(source).__name__)
    try:
        text = bytes(source).decode('utf-8')
    except UnicodeDecodeError:
        raise CatalogSyntaxError('not-utf8') from None
    parser = _LiteralParser(_tokens(_declaration_block(text), integers=True))
    for kind, value in (('name', 'local'), ('name', _REGISTRY_TABLE), ('punct', '='),
                        ('punct', '{')):
        parser.take(kind, value)
    table = parser.table(1)
    token = parser.tokens[parser.index]
    if token.kind != 'eof':
        parser.fail('trailing-content', token)
    _registry(type(table) is dict and table, 'registry-structure', _REGISTRY_TABLE)
    _registry(len(table) <= _MAX_BASE_ENTRIES, 'registry-too-many', _REGISTRY_TABLE)
    return {key: _declaration(key, value) for key, value in table.items()}


def _declared_formats(declarations):
    return types.MappingProxyType({key: (value['fields'], value['resultLimit'])
                                   for key, value in declarations.items()
                                   if value['kind'] == 'format'})


def _context_shape(declaration):
    """The key-context kind, placeholders and result limit a declaration
    requires (None: no resultLimitBytes member)."""
    if declaration['kind'] == 'text':
        return 'text', [], None
    return ('format', [{'name': name, 'type': declaration['slot']}
                       for name in declaration['fields']], declaration['resultLimit'])


def _check_registry(declarations, english, context):
    """Complete English against the declarations, then each key-context row
    of a declared key against its declaration. Rows of other shapes are left
    to _check_context."""
    for key in english:
        _registry(key in declarations, 'undeclared-entry', 'english', key)
    for key in declarations:
        _registry(key in english, 'english-incomplete', _REGISTRY_TABLE, key)
    rows = context.get('keys')
    for index, row in enumerate(rows if type(rows) is list else ()):
        key = row.get('key') if type(row) is dict else None
        if type(key) is not str or key not in declarations:
            continue
        kind, placeholders, limit = _context_shape(declarations[key])
        found = row.get('resultLimitBytes')
        limit_ok = ('resultLimitBytes' not in row) if limit is None else _is_int(found, limit)
        _registry(row.get('kind') == kind and row.get('placeholders') == placeholders
                  and limit_ok, 'context-declaration-mismatch', 'keyContext.keys[%d]' % index, key)


def validate_registry_catalog_data(english_source: bytes, packs_source: bytes,
                                  key_context_json: bytes, release_json: bytes,
                                  localization_source: bytes) -> dict:
    """The registry-bound schema API: validate the exact bytes of the four
    catalog inputs of validate_catalog_data plus core/Localization.lua, with
    the parsed declarations governing (see above), and return a dict with
    english, packs, keyContext, release and declarations. Each argument must
    be bytes or bytearray, else TypeError. Failures raise CatalogSyntaxError,
    CatalogValidationError or CatalogRegistryError; nothing is executed."""
    for name, value in (('english_source', english_source), ('packs_source', packs_source),
                        ('key_context_json', key_context_json), ('release_json', release_json),
                        ('localization_source', localization_source)):
        if not isinstance(value, (bytes, bytearray)):
            raise TypeError('%s must be bytes, not %s' % (name, type(value).__name__))
    english = parse_english(english_source)
    packs = parse_packs(packs_source)
    key_context = _strict_json(key_context_json, 'keyContext')
    release = _strict_json(release_json, 'release')
    declarations = parse_registry_declarations(localization_source)
    formats = _declared_formats(declarations)
    _check_english(english, formats)
    _check_registry(declarations, english, key_context)
    _check_context(key_context, english, formats)
    products = _check_release(release)
    _check_packs(packs, english, products, formats)
    return {'english': english, 'packs': packs, 'keyContext': key_context, 'release': release,
            'declarations': declarations}


def registry_catalog_report(english_source: bytes, packs_source: bytes,
                            key_context_json: bytes, release_json: bytes,
                            localization_source: bytes) -> dict:
    """Report schemaVersion 2: validate_registry_catalog_data on the five
    inputs, then the catalog_report derivation with five input rows, the
    registry-bound validationScope and a registry section listing the
    declarations. An invalid input gets no report."""
    sources = (english_source, packs_source, key_context_json, release_json,
               localization_source)
    validated = validate_registry_catalog_data(*sources)
    report = _coverage_report(validated, sources, _REGISTRY_INPUTS,
                              REGISTRY_REPORT_SCHEMA_VERSION, REGISTRY_SCOPE)
    report['registry'] = _registry_section(validated)
    return report


def _registry_section(validated):
    """The registry section of report schemaVersion 2."""
    rows = []
    for key, declaration in validated['declarations'].items():
        kind, placeholders, limit = _context_shape(declaration)
        row = {'key': key, 'kind': kind}
        if limit is not None:
            row.update({'placeholders': placeholders, 'resultLimitBytes': limit})
        rows.append(row)
    return {
        'source': _AUTHORITY,
        'markers': {'open': _REGISTRY_OPEN, 'close': _REGISTRY_CLOSE},
        'declarationCount': len(rows),
        'englishKeys': len(validated['english']),
        'keyContextRows': len(validated['keyContext']['keys']),
        'declarations': rows,
        'rule': ('the declared keys, the English keys and the key-context rows are one set; '
                 'kind, placeholder names in order with their type, and result limit come '
                 'from the declarations'),
        'nonexecution': _NONEXECUTION,
    }


# ---------------------------------------------------------------------------
# S6 (Refs #147): opt-in, read-only static diagnostics over the registry-bound
# catalog. The strict gate above stops at the first failure, so invalid and
# obsolete entries never reach a report. registry_catalog_diagnostics takes
# the same five byte strings and returns a receipt instead of raising:
#
# - strictVerdict is registry_catalog_report's own verdict on the same bytes,
#   with its unchanged error class and code. The receipt never changes it.
# - Everything except the pack entries must first be trustworthy, in the
#   strict order: syntax, JSON, declarations, English, registry, key context,
#   release, the retired-key list (keyContext.retiredKeys, below), the pack
#   set, each pack's autonym and entry count. The first failure there is the
#   collection boundary: collection INCOMPLETE, no entry problem and no
#   coverage, because entries cannot be enumerated safely. Nothing is
#   repaired, guessed or re-parsed with a looser grammar.
# - Otherwise every pack entry gets the strict entry check. An invalid-text
#   or invalid-template entry of an active key is invalid; any other
#   unknown key (orphan-entry or invalid-key there) is obsolete when the
#   retired-key list names it, else an orphan. An orphan is never obsolete
#   and never counted. The coverage then is report schemaVersion 2 with
#   invalid active keys in invalid, still once in the active denominator,
#   and retired keys in obsolete, outside it. A failure in its evidence
#   checks is a boundary too.
#
# valid is true only when the strict verdict is valid and the collection is
# complete. The receipt is not a gate: completeness is never established,
# and the strict API, required CI and release gates still decide. The
# retired-key list is read only here; the strict APIs never read it, so
# their outcomes are unchanged. The command line writes the receipt with
# --diagnose (exit 2 while invalid or incomplete).

DIAGNOSTIC_SCHEMA = 'nexus.l10n.diagnostic_receipt'
DIAGNOSTIC_SCHEMA_VERSION = 1
DIAGNOSTIC_CODES = (
    'retired-structure', 'retired-key', 'retired-duplicate', 'retired-order', 'retired-active',
)
PROBLEM_CATEGORIES = ('invalid', 'obsolete', 'orphan')
_INVALID_ENTRY_CODES = frozenset(('invalid-text', 'invalid-template'))
_STRICT_FAILURES = (CatalogSyntaxError, CatalogValidationError, CatalogRegistryError,
                    CatalogEvidenceError)
_DIAGNOSTIC_MODE = ('opt-in read-only diagnostics over the exact supplied bytes; the strict '
                    'verdict is reported unchanged')
_COLLECTION_RULE = ('COMPLETE: every pack entry was checked. INCOMPLETE: the boundary failure '
                    'made entry enumeration untrustworthy, so no entry problem or coverage is '
                    'reported and other problems may exist')
_COMPLETENESS_RULE = ('this receipt never establishes completeness or release readiness; '
                      'fallback English, autonyms and copied English are never reviewed '
                      'translations')
_GATE_RULE = ('this receipt is not a gate: the strict API, required CI and release gates '
              'decide, and an invalid catalog fails them however it is reported')


class CatalogDiagnosticError(ValueError):
    """Raised inside registry_catalog_diagnostics for a malformed retired-key
    list and reported as its collection boundary. It carries a stable code
    (one of DIAGNOSTIC_CODES) and, when known, the path and the key."""

    def __init__(self, code: str, path: str = None, key=None):
        detail = '' if path is None else ' at ' + path
        if key is not None:
            detail += ' (%r)' % (key,)
        super().__init__(code + detail)
        self.code, self.path, self.key = code, path, key


def _diagnostic(condition, code, path, key=None):
    if not condition:
        raise CatalogDiagnosticError(code, path, key)


def _check_retired(context, declarations):
    """keyContext.retiredKeys.keys: valid semantic keys, each once, in
    ascending order, none an active declaration. Returns the list."""
    where = 'keyContext.retiredKeys'
    record = context.get('retiredKeys')
    _diagnostic(type(record) is dict and _is_str_list(record.get('keys')), 'retired-structure',
                where)
    keys, seen = record['keys'], set()
    for key in keys:
        _diagnostic(_valid_key(key), 'retired-key', where + '.keys', key)
        _diagnostic(key not in seen, 'retired-duplicate', where + '.keys', key)
        _diagnostic(key not in declarations, 'retired-active', where + '.keys', key)
        seen.add(key)
    _diagnostic(keys == sorted(keys), 'retired-order', where + '.keys')
    return list(keys)


def _trusted_catalog(sources):
    """Every strict check except the pack entries, in the strict order, plus
    the retired-key list. Returns (validated, retired keys, formats)."""
    english_source, packs_source, key_context_json, release_json, localization_source = sources
    english = parse_english(english_source)
    packs = parse_packs(packs_source)
    key_context = _strict_json(key_context_json, 'keyContext')
    release = _strict_json(release_json, 'release')
    declarations = parse_registry_declarations(localization_source)
    formats = _declared_formats(declarations)
    _check_english(english, formats)
    _check_registry(declarations, english, key_context)
    _check_context(key_context, english, formats)
    products = _check_release(release)
    retired = _check_retired(key_context, declarations)
    _check_pack_set(packs, products)
    for pack_id, pack in packs.items():
        _check_pack_shape(pack_id, pack)
        _check_pack_autonym(pack_id, pack, products)
    validated = {'english': english, 'packs': packs, 'keyContext': key_context,
                 'release': release, 'declarations': declarations}
    return validated, retired, formats


def _entry_code(key, text, english, path, formats):
    """The strict code of one pack entry, or None when it is valid."""
    try:
        _check_entry(key, text, english, path, formats)
    except CatalogValidationError as error:
        return error.code
    return None


def _entry_problems(validated, retired, formats):
    """Every entry problem of the optional packs in release order, keys
    sorted, and {product ID: (invalid keys, obsolete keys)}."""
    english, packs = validated['english'], validated['packs']
    rows, problems = [], {}
    for item in validated['release']['products']:
        if item['kind'] != _OPTIONAL:
            continue
        product_id = item['productId']
        entries = packs[product_id]['entries']
        path = 'packs[%r].entries' % (product_id,)
        invalid, obsolete = set(), []
        for key in sorted(entries):
            code = _entry_code(key, entries[key], english, path, formats)
            if code is None:
                continue
            if code in _INVALID_ENTRY_CODES:
                category = 'invalid'
                invalid.add(key)
            elif key in retired:
                category = 'obsolete'
                obsolete.append(key)
            else:
                category = 'orphan'
            rows.append({'productId': product_id, 'key': key, 'category': category,
                         'code': code})
        problems[product_id] = (frozenset(invalid), obsolete)
    return rows, problems


def registry_catalog_diagnostics(english_source: bytes, packs_source: bytes,
                                 key_context_json: bytes, release_json: bytes,
                                 localization_source: bytes) -> dict:
    """The opt-in diagnostic receipt (see above) for the exact bytes of the
    five registry-bound inputs. Each argument must be bytes or bytearray,
    else TypeError; no catalog failure is raised. Nothing is read, written,
    executed or modified."""
    sources = (english_source, packs_source, key_context_json, release_json,
               localization_source)
    for name, value in zip(('english_source', 'packs_source', 'key_context_json',
                            'release_json', 'localization_source'), sources):
        if not isinstance(value, (bytes, bytearray)):
            raise TypeError('%s must be bytes, not %s' % (name, type(value).__name__))
    sources = tuple(bytes(value) for value in sources)
    try:
        registry_catalog_report(*sources)
        strict = {'result': 'valid'}
    except _STRICT_FAILURES as error:
        strict = {'result': 'invalid', 'api': 'registry_catalog_report'}
        strict.update(_error_fields(error))
    retired, rows, coverage, boundary, stage = None, [], None, None, 'structure'
    try:
        validated, retired_keys, formats = _trusted_catalog(sources)
        retired = retired_keys
        rows, problems = _entry_problems(validated, frozenset(retired_keys), formats)
        stage = 'evidence'
        coverage = _coverage_report(validated, sources, _REGISTRY_INPUTS,
                                    REGISTRY_REPORT_SCHEMA_VERSION, REGISTRY_SCOPE, problems)
        coverage['registry'] = _registry_section(validated)
    except _STRICT_FAILURES + (CatalogDiagnosticError,) as error:
        boundary = {'stage': stage}
        boundary.update(_error_fields(error))
        rows, coverage = [], None
    if boundary is None and strict['result'] == 'invalid' and not rows:
        # Never report an invalid catalog as fully collected without a problem.
        boundary = {key: value for key, value in strict.items() if key != 'result'}
        boundary['stage'] = 'strict'
        coverage = None
    return {
        'schema': DIAGNOSTIC_SCHEMA,
        'schemaVersion': DIAGNOSTIC_SCHEMA_VERSION,
        'tool': _TOOL_PATH,
        'status': STATUS,
        'validationScope': REGISTRY_SCOPE,
        'mode': _DIAGNOSTIC_MODE,
        'inputs': _input_rows(_REGISTRY_INPUTS, sources),
        'valid': strict['result'] == 'valid' and boundary is None,
        'strictVerdict': strict,
        'collection': {'state': 'INCOMPLETE' if boundary else 'COMPLETE', 'boundary': boundary,
                       'rule': _COLLECTION_RULE},
        'retiredKeys': retired,
        'entryProblems': rows,
        'problemCounts': {category: sum(1 for row in rows if row['category'] == category)
                          for category in PROBLEM_CATEGORIES},
        'coverage': coverage,
        'completeness': {'established': False, 'rule': _COMPLETENESS_RULE},
        'gate': 'NOT_A_GATE',
        'gateRule': _GATE_RULE,
        'nonexecution': _NONEXECUTION,
    }


def _cli_diagnostics(receipt, toc, require_complete):
    """Write one diagnostics record on stdout and return its exit status: 2
    while the receipt is not valid, else 1 with --require-complete (never
    established) or 0."""
    if not receipt['valid']:
        exit_code = _EXIT_ERROR
    else:
        exit_code = _EXIT_NOT_ESTABLISHED if require_complete else _EXIT_REPORT
    _cli_emit(sys.stdout, {
        'schema': CLI_SCHEMA,
        'schemaVersion': CLI_SCHEMA_VERSION,
        'record': 'diagnostics',
        'tool': _TOOL_PATH,
        'status': STATUS,
        'requireComplete': 'requested' if require_complete else 'not_requested',
        'registryBinding': 'requested',
        'exitCode': exit_code,
        'inputBinding': _INPUT_BINDING,
        'toc': toc,
        'diagnostics': receipt,
    })
    return exit_code


# ---------------------------------------------------------------------------
# S7 (Refs #147): per-pack provenance metadata and an opt-in, read-only
# provenance receipt. release.packProvenance (contract
# nexus.l10n.pack_provenance, version 1) holds one record per optional_ui_pack
# product with exactly productId and the facts of _PROVENANCE_FACTS. A fact is
# either
#
#     {"status": "UNKNOWN", "reason": <statement>}
#
# or DECLARED: englishBase as {"status", "algorithm": "SHA-256", "basis":
# _ENGLISH_BASIS, "sha256": 64 lower-case hex, "evidenceReference"}, every
# other fact as {"status", "value": <statement>, "evidenceReference"}. A
# statement is 1 to 512 characters without surrounding whitespace or control
# characters and is no placeholder (_NOT_A_STATEMENT); a reference is an
# https:// URL that is never fetched. Anything else is a CatalogProvenanceError
# (PROVENANCE_CODES): a boolean, a placeholder, a mixed shape or another basis,
# such as a Git object ID or a hash of decoded entries.
#
# pack_provenance_diagnostics takes the five registry-bound byte strings and
# reports, separately:
# - catalogVerdict: registry_catalog_report's own verdict, unchanged;
# - metadata.technicalValidity: the record schema plus every declared base,
#   compared only with the exact supplied English bytes. Equal is MATCHED,
#   different is STALE, a technical failure (provenance-stale); UNKNOWN is
#   never stale. Nothing is normalized, and a declaration is never refreshed;
# - englishObservation: the digest of the supplied English bytes, an
#   observation only, never a drafting base and never written anywhere;
# - historicalDeclarations: sourceLineage and packReviewStatementAtBase,
#   verbatim, as documented claims that fill no per-pack fact;
# - attestedFacts NOT_ESTABLISHED and supportEligibility HELD, always: no
#   attestation contract exists, and no record, statement, reference or match
#   grants review, rights, human, native or language-support acceptance.
# valid is true only when the catalog verdict and the metadata are valid. The
# strict APIs, the coverage reports and the S6 diagnostics never read
# packProvenance, so their outcomes are unchanged. The command line writes
# the receipt with --provenance (exit 2 while invalid).

PROVENANCE_SCHEMA = 'nexus.l10n.provenance_receipt'
PROVENANCE_SCHEMA_VERSION = 1
PROVENANCE_CODES = (
    'provenance-contract', 'provenance-structure', 'provenance-field',
    'provenance-unknown-product', 'provenance-duplicate-product', 'provenance-missing-product',
    'provenance-status', 'provenance-reason', 'provenance-value', 'provenance-reference',
    'provenance-basis', 'provenance-hash-format', 'provenance-stale',
)
_PROVENANCE_CONTRACT = 'nexus.l10n.pack_provenance'
_PROVENANCE_FACTS = ('englishBase', 'authorship', 'attribution', 'rightsStatement',
                     'importedCorpus')
_RECORD_FIELDS = frozenset(('productId',) + _PROVENANCE_FACTS)
_UNKNOWN, _DECLARED_FACT = 'UNKNOWN', 'DECLARED'
_UNKNOWN_FIELDS = frozenset(('status', 'reason'))
_DECLARED_FIELDS = frozenset(('status', 'value', 'evidenceReference'))
_DECLARED_BASE_FIELDS = frozenset(('status', 'algorithm', 'basis', 'sha256',
                                   'evidenceReference'))
_BASE_ALGORITHM = 'SHA-256'
_ENGLISH_BASIS = 'exact-supplied-english-bytes'
_MAX_STATEMENT_CHARS = 512
_NOT_A_STATEMENT = _NOT_A_REVIEWER | frozenset((
    'declared', 'verified', 'accepted', 'attested', 'yes', 'no', 'true', 'false', 'todo',
    '-', '?'))
_NOT_ESTABLISHED, _HELD = 'NOT_ESTABLISHED', 'HELD'
_RELATIONS = ('UNKNOWN', 'MATCHED', 'STALE')
PROVENANCE_SCOPE = (
    'Per-pack provenance metadata only: the record schema and each declared English base '
    'against the exact supplied English bytes. Not catalog validity, translation quality, '
    'review, rights, authorship, human, native or language-support acceptance; not whole '
    '#147.')
_PROVENANCE_MODE = ('opt-in read-only provenance receipt over the exact supplied bytes; the '
                    'catalog verdict is reported unchanged')
_OBSERVATION_ROLE = ('observation of the supplied bytes only: not a drafting base, not a Git '
                     'object ID and not recorded in any metadata')
_TECHNICAL_RULE = ('VALID: every record has the schema and no declared base is stale. It is '
                   'technical validity only and attests no fact')
_HISTORICAL_NATURE = 'documented_claim'
_SUPPORT_RULE = ('review, rights, fluent human, native and language-support acceptance are '
                 'separate evidence gates; no provenance record grants them')
_ATTESTATION_RULE = ('no attestation contract exists: a DECLARED fact or a MATCHED base is a '
                     'documented claim, not an independently evidenced fact')
_PROVENANCE_COMPLETENESS = ('this receipt never establishes completeness, support or release '
                            'readiness')


class CatalogProvenanceError(ValueError):
    """Raised inside pack_provenance_diagnostics for malformed provenance
    metadata or a stale declared base, and reported as a metadata problem. It
    carries a stable code (one of PROVENANCE_CODES) and, when known, the path
    and the product ID."""

    def __init__(self, code: str, path: str = None, key=None):
        detail = '' if path is None else ' at ' + path
        if key is not None:
            detail += ' (%r)' % (key,)
        super().__init__(code + detail)
        self.code, self.path, self.key = code, path, key


def _provenance(condition, code, path, key=None):
    if not condition:
        raise CatalogProvenanceError(code, path, key)


def _valid_statement(text):
    """A recorded statement: 1 to 512 characters without leading or trailing
    whitespace, C0 or C1 controls or DEL, and not a placeholder. It is
    recorded, never verified."""
    if type(text) is not str or not 1 <= len(text) <= _MAX_STATEMENT_CHARS:
        return False
    if text != text.strip() or any(ord(char) < 32 or 127 <= ord(char) <= 159 for char in text):
        return False
    return text.casefold() not in _NOT_A_STATEMENT


def _check_fact(fact, name, path, product_id):
    """One UNKNOWN or DECLARED fact of a provenance record, returned as a copy."""
    _provenance(type(fact) is dict, 'provenance-structure', path, product_id)
    status = fact.get('status')
    _provenance(type(status) is str and status in (_UNKNOWN, _DECLARED_FACT),
                'provenance-status', path + '.status', product_id)
    if status == _UNKNOWN:
        _provenance(set(fact) == _UNKNOWN_FIELDS, 'provenance-field', path, product_id)
        _provenance(_valid_statement(fact['reason']), 'provenance-reason', path + '.reason',
                    product_id)
        return dict(fact)
    base = name == 'englishBase'
    _provenance(set(fact) == (_DECLARED_BASE_FIELDS if base else _DECLARED_FIELDS),
                'provenance-field', path, product_id)
    if base:
        _provenance(fact['algorithm'] == _BASE_ALGORITHM and fact['basis'] == _ENGLISH_BASIS,
                    'provenance-basis', path + '.basis', product_id)
        _provenance(type(fact['sha256']) is str and _SHA256_HEX.fullmatch(fact['sha256'])
                    is not None, 'provenance-hash-format', path + '.sha256', product_id)
    else:
        _provenance(_valid_statement(fact['value']), 'provenance-value', path + '.value',
                    product_id)
    reference = fact['evidenceReference']
    _provenance(type(reference) is str and _valid_reference(reference), 'provenance-reference',
                path + '.evidenceReference', product_id)
    return dict(fact)


def _check_provenance(release, optional_ids):
    """release.packProvenance: the contract and exactly one record per
    optional product. Returns {product ID: (path, {fact: copy})}."""
    where = 'release.packProvenance'
    member = release.get('packProvenance')
    _provenance(type(member) is dict, 'provenance-structure', where)
    _provenance(member.get('contract') == _PROVENANCE_CONTRACT, 'provenance-contract',
                where + '.contract')
    _provenance(_is_int(member.get('contractVersion'), 1), 'provenance-contract',
                where + '.contractVersion')
    records = member.get('records')
    _provenance(type(records) is list, 'provenance-structure', where + '.records')
    found = {}
    for index, record in enumerate(records):
        path = '%s.records[%d]' % (where, index)
        _provenance(type(record) is dict, 'provenance-structure', path)
        product_id = record.get('productId')
        key = product_id if type(product_id) is str else None
        _provenance(set(record) == _RECORD_FIELDS and key is not None, 'provenance-field',
                    path, key)
        _provenance(product_id in optional_ids, 'provenance-unknown-product',
                    path + '.productId', product_id)
        _provenance(product_id not in found, 'provenance-duplicate-product',
                    path + '.productId', product_id)
        found[product_id] = (path, {name: _check_fact(record[name], name, path + '.' + name,
                                                      product_id)
                                    for name in _PROVENANCE_FACTS})
    for product_id in optional_ids:
        _provenance(product_id in found, 'provenance-missing-product', where + '.records',
                    product_id)
    return found


def _strict_verdict(sources):
    """registry_catalog_report's own verdict on the exact sources."""
    try:
        registry_catalog_report(*sources)
    except _STRICT_FAILURES as error:
        verdict = {'result': 'invalid', 'api': 'registry_catalog_report'}
        verdict.update(_error_fields(error))
        return verdict
    return {'result': 'valid'}


def _historical_declarations(release):
    """The historical document-level declarations, verbatim."""
    return {'sourceLineage': json.loads(json.dumps(release.get('sourceLineage'))),
            'packReviewStatementAtBase': release.get('packReviewStatementAtBase'),
            'nature': _HISTORICAL_NATURE, 'perPackFacts': 'NOT_DERIVED'}


def _provenance_rows(records, optional_ids, observed):
    """One row per optional product in release order, with its base relation
    and hold reasons, and the stale-base problems."""
    rows, problems = [], []
    for product_id in optional_ids:
        path, facts = records[product_id]
        base = dict(facts['englishBase'])
        subject = product_id + '.englishBase'
        if base['status'] == _UNKNOWN:
            base['relation'] = 'UNKNOWN'
            holds = [_reason('base-unknown', subject, base['reason'])]
        elif base['sha256'] == observed:
            base['relation'] = 'MATCHED'
            holds = [_reason('base-declared-not-attested', subject,
                             'the declared digest equals the supplied English bytes')]
        else:
            base['relation'] = 'STALE'
            holds = [_reason('base-stale', subject, 'declared %s; supplied %s'
                             % (base['sha256'], observed))]
            problem = {'stage': 'binding'}
            problem.update(_error_fields(CatalogProvenanceError(
                'provenance-stale', path + '.englishBase.sha256', product_id)))
            problems.append(problem)
        for name in _PROVENANCE_FACTS[1:]:
            fact = facts[name]
            if fact['status'] == _UNKNOWN:
                holds.append(_reason('fact-unknown', product_id + '.' + name, fact['reason']))
            else:
                holds.append(_reason('fact-declared-not-verified', product_id + '.' + name,
                                     fact['value']))
        holds.append(_reason('support-gates-outside-provenance', product_id, _SUPPORT_RULE))
        rows.append({'productId': product_id, 'englishBase': base,
                     'facts': {name: facts[name] for name in _PROVENANCE_FACTS[1:]},
                     'attestedFacts': _NOT_ESTABLISHED, 'supportEligibility': _HELD,
                     'holdReasons': holds})
    return rows, problems


def pack_provenance_diagnostics(english_source: bytes, packs_source: bytes,
                                key_context_json: bytes, release_json: bytes,
                                localization_source: bytes) -> dict:
    """The opt-in provenance receipt (see above) for the exact bytes of the
    five registry-bound inputs. Each argument must be bytes or bytearray,
    else TypeError; no catalog or metadata failure is raised. Nothing is
    read, written, fetched, executed or modified."""
    sources = (english_source, packs_source, key_context_json, release_json,
               localization_source)
    for name, value in zip(('english_source', 'packs_source', 'key_context_json',
                            'release_json', 'localization_source'), sources):
        if not isinstance(value, (bytes, bytearray)):
            raise TypeError('%s must be bytes, not %s' % (name, type(value).__name__))
    sources = tuple(bytes(value) for value in sources)
    strict = _strict_verdict(sources)
    observed = hashlib.sha256(sources[0]).hexdigest()
    historical, rows, problems, stage = None, None, [], 'release'
    try:
        release = _strict_json(sources[3], 'release')
        products = _check_release(release)
        historical = _historical_declarations(release)
        stage = 'schema'
        optional_ids = [product_id for product_id, (_, product) in products.items()
                        if product['kind'] == _OPTIONAL]
        records = _check_provenance(release, optional_ids)
    except (CatalogValidationError, CatalogProvenanceError) as error:
        problem = {'stage': stage}
        problem.update(_error_fields(error))
        problems.append(problem)
    else:
        rows, problems = _provenance_rows(records, optional_ids, observed)
    relations = None if rows is None else {
        relation: sum(1 for row in rows if row['englishBase']['relation'] == relation)
        for relation in _RELATIONS}
    return {
        'schema': PROVENANCE_SCHEMA,
        'schemaVersion': PROVENANCE_SCHEMA_VERSION,
        'tool': _TOOL_PATH,
        'status': STATUS,
        'scope': PROVENANCE_SCOPE,
        'mode': _PROVENANCE_MODE,
        'inputs': _input_rows(_REGISTRY_INPUTS, sources),
        'valid': strict['result'] == 'valid' and not problems,
        'catalogVerdict': strict,
        'metadata': {'contract': _PROVENANCE_CONTRACT, 'contractVersion': 1,
                     'technicalValidity': 'INVALID' if problems else 'VALID',
                     'problems': problems, 'rule': _TECHNICAL_RULE},
        'englishObservation': {'source': _ENGLISH_SOURCE, 'algorithm': _BASE_ALGORITHM,
                               'basis': _ENGLISH_BASIS, 'sha256': observed,
                               'byteLength': len(sources[0]), 'role': _OBSERVATION_ROLE},
        'historicalDeclarations': historical,
        'baseRelations': relations,
        'packs': rows,
        'attestedFacts': _NOT_ESTABLISHED,
        'attestationRule': _ATTESTATION_RULE,
        'supportEligibility': _HELD,
        'supportRule': _SUPPORT_RULE,
        'completeness': {'established': False, 'rule': _PROVENANCE_COMPLETENESS},
        'nonexecution': _NONEXECUTION,
    }


def _cli_provenance(receipt, toc, require_complete):
    """Write one provenance record on stdout and return its exit status: 2
    while the receipt is not valid, else 1 with --require-complete (support is
    always held) or 0."""
    if not receipt['valid']:
        exit_code = _EXIT_ERROR
    else:
        exit_code = _EXIT_NOT_ESTABLISHED if require_complete else _EXIT_REPORT
    _cli_emit(sys.stdout, {
        'schema': CLI_SCHEMA,
        'schemaVersion': CLI_SCHEMA_VERSION,
        'record': 'provenance',
        'tool': _TOOL_PATH,
        'status': STATUS,
        'requireComplete': 'requested' if require_complete else 'not_requested',
        'registryBinding': 'requested',
        'exitCode': exit_code,
        'inputBinding': _INPUT_BINDING,
        'toc': toc,
        'provenance': receipt,
    })
    return exit_code


# ---------------------------------------------------------------------------
# S8 (Refs #147): static consumer binding of the declared keys. The strict
# APIs prove that every declared key has valid English; consumer_binding_report
# proves, by a bounded syntactic check of the loaded Lua source, that each one
# also has a genuine static consumer. It takes the five registry-bound byte
# strings, a record per TOC and a record per Lua file those TOCs load. Each
# record is {"path", "sha256", "byteLength", "data"}: the claimed digest and
# length are checked against the exact data, never normalized. The TOC
# records must be exactly the two product TOCs, Nexus.toc and
# companion/NexusSupport/NexusSupport.toc; the TOC entries and the source
# records must be the same set of safe relative paths, the
# registry Lua sources must be loaded by Nexus.toc in their runtime order and
# be the same bytes as the registry inputs, and a failure there raises
# CatalogConsumerError (CONSUMER_CODES) instead of shrinking the inventory.
#
# Every loaded file is tokenized with the trusted lexer and parsed with a Lua
# 5.1 grammar into a syntax tree; nothing is evaluated, imported or executed,
# and no control flow, reachability or runtime value is decided. Local names
# are resolved lexically. A receiver is the global Nexus followed by
# .Localization, directly or through a local alias that is never assigned
# again; only Text, Resolve and Format are consumer methods, each bound to the
# declared kind (text, text, format). A key is bound by:
#
# - direct-call: a consumer method called on a receiver with a literal key;
# - wrapper-call: a literal key passed to a local function whose parameter
#   goes unchanged into a consumer method call on a receiver;
# - map-value: a value of a read-only local table of literal string pairs,
#   dispatched as wrapper(MAP[v], ...) by the sole return of
#   "if MAP[v] then ... end" in the body of an exported module function
#   (function T.Name, with Nexus.<Module> = T, defined once). Only an earlier
#   "if OTHER[v] then" guard over another such table may precede it; the
#   codes it holds shadow the map's entries.
#
# A site counts only when its localization result reaches an output (review
# fix 1): a may-flow path in _UnitFlow, from the call through parens, the
# text-carrying operands of and/or/.., bindings every definition of which
# carries the same proof, function returns into their resolved calls, field
# channels and parameters, ends at argument 1 of SetText, AddLine or
# AddMessage or an argument of print. A wrapper must return its own
# consumer-method result. A discarded, overwritten or merely compared result,
# or one reaching only an unused helper or a stock widget outside the loaded
# source, is listed in unprovenSites and never counted. A module table is
# one identity with its local aliases (review fix 2): a field written through
# an alias is another definition, and a module table that escapes its file,
# is reassigned or is written through a computed key resolves no function.
#
# Comments, strings that merely contain call text, data and declaration
# tables, Has and Kind queries and Text methods of other objects never bind.
# A literal key that is not declared is binding-orphan, a method of the other
# kind binding-kind. A reassigned alias or wrapper, a method call, an indirect
# reference to a consumer method, an unsupported dispatch and an assignment to
# the seam outside core/Localization.lua are binding-unresolved or
# binding-mutation, never assumed bindings. A dynamic key or an unresolvable
# receiver is listed in dynamicUnknown (issue #142 scope) and never counted.
# The receipt is valid only without any problem. Family membership is
# reported separately from binding; no family, language or support
# acceptance follows from either. The command line writes the receipt with
# --consumers (exit 2 while invalid).

CONSUMER_SCHEMA = 'nexus.l10n.consumer_binding_receipt'
CONSUMER_SCHEMA_VERSION = 1
CONSUMER_CODES = (
    'consumer-input-structure', 'consumer-path', 'consumer-duplicate-path',
    'consumer-hash-mismatch', 'consumer-length-mismatch', 'consumer-toc-required',
    'consumer-toc-unknown', 'consumer-toc-not-utf8', 'consumer-toc-entry', 'consumer-toc-duplicate',
    'consumer-source-missing', 'consumer-source-unlisted', 'consumer-registry-unloaded',
    'consumer-registry-order', 'consumer-registry-conflict',
)
BINDING_PROBLEM_CODES = (
    'binding-unparsed', 'binding-unbound', 'binding-orphan', 'binding-kind',
    'binding-unresolved', 'binding-mutation',
)
BINDING_CLASSES = ('DIRECT_LITERAL_CONSUMER', 'MAPPED_TO_CONSUMER', 'UNBOUND')
CONSUMER_SCOPE = (
    'Static consumer binding of the currently declared keys: syntactic call, alias, wrapper '
    'and literal-map dispatch chains in the TOC-loaded Lua source, parsed without executing '
    'Lua. Not runtime reachability, branch occurrence, rendering, native UI acceptance, family '
    'coverage or adoption, dynamic-key grammar (#142) or whole #147.')
_MAIN_TOC = 'Nexus.toc'
_CONSUMER_TOCS = (_MAIN_TOC, 'companion/NexusSupport/NexusSupport.toc')
_RECORD_FIELDS_S8 = frozenset(('path', 'sha256', 'byteLength', 'data'))
_PATH_SEGMENT = re.compile('[A-Za-z0-9_][A-Za-z0-9_.-]*')
_LOCALIZATION = 'Nexus.Localization'
_KEY_METHODS = types.MappingProxyType({'Text': 'text', 'Resolve': 'text', 'Format': 'format'})
_QUERY_METHODS = frozenset(('Has', 'Kind'))
_SEAM_METHODS = frozenset(_KEY_METHODS) | _QUERY_METHODS
_DIRECT, _MAPPED, _UNBOUND = BINDING_CLASSES
_CONSUMER_MODE = ('opt-in read-only static binding receipt over the exact supplied bytes; the '
                  'strict catalog verdict must be valid first')
_HASH_BASIS = ('each sha256 and byteLength is of the exact supplied bytes, LF or CRLF as given; '
               'nothing is normalized and no Git object is read')
_BINDING_RULE = ('DIRECT_LITERAL_CONSUMER: a direct-call or wrapper-call site whose result '
                 'reaches an output. MAPPED_TO_CONSUMER: only map-value sites that do. UNBOUND: '
                 'no such site; a literal lead, comment, declaration, unrelated Text method or '
                 'a discarded or overwritten result never binds')
_OUTPUT_RULE = ('a site counts only when its localization result may flow, by the syntactic '
                'rules of _UnitFlow, into argument 1 of SetText, AddLine or AddMessage or an '
                'argument of print; a site that does not is listed in unprovenSites and not '
                'counted. This is a static path, not proof that it runs or is displayed')
_FAMILY_RULE = ('binding and family classification are independent: DECLARED names the window '
                'families whose adoptedKeys hold the key, UNCLASSIFIED none; neither adopts a '
                'key or establishes family coverage')
_CONSUMER_COMPLETENESS = ('this receipt never establishes completeness: dynamic keys, branch '
                          'reachability, rendering and native display are outside it')
_CONSUMER_LIMITS = (
    'static syntax only: a bound site is not proved to run, to be reached or to be displayed',
    'a localization table passed to another function, stored in a global or a table field, or '
    'reached through a computed name is not followed',
    'map dispatch is accepted only in the exact guarded shape described for this seam',
    'result flow is may-flow and flow-insensitive: a field name is one channel across every '
    'table, values in globals, computed-key writes and method calls are not followed, and an '
    'output outside the loaded source (such as the stock dropdown menu) is not an output',
    'Lua 5.1 lexical and grammar rules; LuaJIT and Lua 5.2 additions are refused',
)
_CONSUMER_INPUT_BINDING = ('exact bytes read once from the resolved root for the registry inputs, '
                           'both TOCs and every Lua file they load; no Git revision is read')


class CatalogConsumerError(ValueError):
    """Raised by consumer_binding_report for malformed, inconsistent or
    incomplete TOC and source records. It carries a stable code (one of
    CONSUMER_CODES), the path concerned and, for a TOC line, the TOC as
    subject and its 1-based line number."""

    def __init__(self, code: str, path: str = None, line: int = None, subject: str = None):
        detail = '' if path is None else ' at ' + path
        if subject is not None:
            detail += ' (%s' % subject + ('' if line is None else ', line %d' % line) + ')'
        super().__init__(code + detail)
        self.code, self.path, self.line, self.subject = code, path, line, subject


def _consumer(condition, code, path=None, line=None, subject=None):
    if not condition:
        raise CatalogConsumerError(code, path, line, subject)


def _safe_path(path, suffix):
    """A relative POSIX path of plain segments that ends with suffix."""
    return (type(path) is str and path.endswith(suffix)
            and all(_PATH_SEGMENT.fullmatch(segment) for segment in path.split('/')))


def _consumer_records(records, suffix, name):
    """[(path, exact bytes)] after the record shape and the claimed digest
    and length are checked against the bytes."""
    _consumer(type(records) in (list, tuple), 'consumer-input-structure', name)
    rows = []
    for index, row in enumerate(records):
        where = '%s[%d]' % (name, index)
        _consumer(type(row) is dict and set(row) == _RECORD_FIELDS_S8, 'consumer-input-structure',
                  where)
        _consumer(isinstance(row['data'], (bytes, bytearray)), 'consumer-input-structure',
                  where + '.data')
        _consumer(type(row['sha256']) is str and _SHA256_HEX.fullmatch(row['sha256']) is not None,
                  'consumer-input-structure', where + '.sha256')
        _consumer(type(row['byteLength']) is int, 'consumer-input-structure',
                  where + '.byteLength')
        path = row['path']
        _consumer(_safe_path(path, suffix), 'consumer-path', path if type(path) is str else where)
        data = bytes(row['data'])
        _consumer(hashlib.sha256(data).hexdigest() == row['sha256'], 'consumer-hash-mismatch', path)
        _consumer(len(data) == row['byteLength'], 'consumer-length-mismatch', path)
        rows.append((path, data))
    return rows


def _toc_entries(toc, data):
    """[(path, line)] of the Lua files one TOC loads: blank, comment and
    metadata lines are skipped, slash and backslash runs become one /, and
    each entry is relative to the directory of the TOC."""
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        raise CatalogConsumerError('consumer-toc-not-utf8', toc) from None
    if text.startswith('\ufeff'):
        text = text[1:]
    base = toc.rpartition('/')[0]
    entries = []
    for number, line in enumerate(_TOC_LINE_BREAK.split(text), 1):
        entry = line.strip()
        if entry and not entry.startswith('#'):
            path = (base + '/' if base else '') + _TOC_SEPARATORS.sub('/', entry)
            _consumer(_safe_path(path, '.lua'), 'consumer-toc-entry', None, number, toc)
            entries.append((path, number))
    return entries


def _consumer_inputs(registry, toc_records, source_records):
    """Check the TOC and source records against each other and against the
    registry inputs. Returns (tocs, sources, listed), where listed maps each
    loaded path to (TOC, line, load order)."""
    tocs = _consumer_records(toc_records, '.toc', 'toc_records')
    sources = _consumer_records(source_records, '.lua', 'source_records')
    seen = set()
    for path, _ in tocs + sources:
        _consumer(path.casefold() not in seen, 'consumer-duplicate-path', path)
        seen.add(path.casefold())
    # The closed product contract: exactly the two product TOCs, each present.
    present = [path for path, _ in tocs]
    for toc in _CONSUMER_TOCS:
        _consumer(toc in present, 'consumer-toc-required', toc)
    for toc in present:
        _consumer(toc in _CONSUMER_TOCS, 'consumer-toc-unknown', toc)
    listed, folded = {}, set()
    for toc, data in tocs:
        for path, number in _toc_entries(toc, data):
            _consumer(path.casefold() not in folded, 'consumer-toc-duplicate', path, number, toc)
            folded.add(path.casefold())
            listed[path] = (toc, number, len(listed))
    supplied = dict(sources)
    for path, (toc, number, _) in listed.items():
        _consumer(path in supplied, 'consumer-source-missing', path, number, toc)
    for path in supplied:
        _consumer(path in listed, 'consumer-source-unlisted', path)
    order = []
    for data, path in zip(registry, (_ENGLISH_SOURCE, _PACKS_SOURCE, _AUTHORITY)):
        entry = listed.get(path)
        _consumer(entry is not None and entry[0] == _MAIN_TOC, 'consumer-registry-unloaded', path)
        _consumer(supplied[path] == data, 'consumer-registry-conflict', path)
        order.append(entry[2])
    _consumer(order == sorted(order), 'consumer-registry-order', _AUTHORITY, None, _MAIN_TOC)
    return tocs, supplied, listed


# The Lua 5.1 tokens and syntax tree. Strings and comments use the trusted
# lexer, exactly as the data parsers above; the tree keeps only what the
# binding needs and is never evaluated.

_LuaToken = namedtuple('_LuaToken', 'kind value line column')
# Optional spaces, then a name (group 1), a numeral as the Lua 5.1 lexer reads
# it (group 2) or an operator (group 3). A - that starts a comment and a [
# that opens a long bracket are left to the lexer, as are strings and line
# breaks.
_LUA_TOKEN = re.compile(
    '[ \t\v\f]*(?:([A-Za-z_][A-Za-z0-9_]*)'
    '|((?:[0-9]|[.][0-9])[0-9.]*(?:[eE][+-]?)?[A-Za-z0-9_]*)'
    r'|(\.\.\.|\.\.|==|~=|<=|>=|-(?!-)|\[(?!=*\[)|[+*/%^#<>=(){}\];:,.]))?')
_LUA_LINE_REST = re.compile('[^\r\n]*')
_LUA_NUMBER = re.compile('0[xX][0-9a-fA-F]+|(?:[0-9]+[.]?[0-9]*|[.][0-9]+)(?:[eE][+-]?[0-9]+)?')
_BLOCK_END = frozenset(('end', 'else', 'elseif', 'until'))
_BINARY = frozenset(('+', '-', '*', '/', '%', '^', '..', '==', '~=', '<', '<=', '>', '>=',
                     'and', 'or'))
_UNARY = frozenset(('-', 'not', '#'))


def _lua_tokens(text):
    """Every Lua 5.1 token of text, ending with one 'eof' token. A short
    string whose value is not UTF-8 keeps the value None: it is never a key.
    A lexical error raises CatalogSyntaxError."""
    scanner = _LEXER.Scanner(text)
    tokens, length, match = [], len(text), _LUA_TOKEN.match
    append = tokens.append
    try:
        while True:
            found = match(text, scanner.index)
            group = found.lastindex
            if group is not None:
                value, start = found.group(group), found.start(group)
                line, column = scanner.line, start - scanner.line_start + 1
                if group == 1:
                    append(_LuaToken('keyword' if value in _RESERVED else 'name', value, line,
                                     column))
                elif group == 2:
                    if _LUA_NUMBER.fullmatch(value) is None:
                        raise CatalogSyntaxError('unexpected-token', line, column)
                    append(_LuaToken('number', value, line, column))
                else:
                    append(_LuaToken('op', value, line, column))
                scanner.index = found.end()
                continue
            index = scanner.index = found.end()
            if index >= length:
                append(_LuaToken('eof', None, scanner.line, scanner.column()))
                return tokens
            char = text[index]
            if char in _NEWLINE:
                scanner.newline()
                continue
            line, column = scanner.line, index - scanner.line_start + 1
            if char == '-' and text.startswith('--', index):
                scanner.index += 2
                if scanner.peek() == '[' and scanner.level() >= 0:
                    _long_body(scanner, 'unfinished-comment', line, column)
                else:
                    scanner.index = _LUA_LINE_REST.match(text, scanner.index).end()
            elif char == '[' and scanner.level() >= 0:
                value = _long_body(scanner, 'unfinished-string', line, column)
                tokens.append(_LuaToken('string', value, line, column))
            elif char in ('"', "'"):
                raw = scanner.short_string(char, line, column)
                try:
                    value = raw.decode('utf-8')
                except UnicodeDecodeError:
                    value = None
                append(_LuaToken('string', value, line, column))
            else:
                raise CatalogSyntaxError('unexpected-token', line, column)
    except _LEXER.SourceError as error:
        raise CatalogSyntaxError(error.code, error.line, error.column) from None


class _Node:
    """One syntax-tree node: its kind, the position of its first token and
    the fields of that kind (slots keep large trees light)."""

    __slots__ = ('kind', 'line', 'column', 'args', 'binding', 'body', 'call', 'clauses', 'cond',
                 'expr', 'exprs', 'fields', 'func', 'key', 'method', 'name', 'names', 'obj',
                 'operands', 'ops', 'orelse', 'params', 'start', 'step', 'stop', 'target',
                 'targets', 'value', 'var', 'vararg')

    def __init__(self, kind, at, **fields):
        self.kind, self.line, self.column = kind, at.line, at.column
        for name, value in fields.items():
            setattr(self, name, value)


class _LuaParser:
    """The Lua 5.1 grammar over a token list. Each method reads tokens in
    order and raises CatalogSyntaxError at the first token it refuses."""

    def __init__(self, tokens):
        self.tokens, self.index = tokens, 0

    def fail(self, token):
        raise CatalogSyntaxError('unexpected-end' if token.kind == 'eof' else 'unexpected-token',
                                 token.line, token.column)

    def at(self, kind, value=None):
        token = self.tokens[self.index]
        return token.kind == kind and (value is None or token.value == value)

    def accept(self, kind, value):
        if self.at(kind, value):
            self.index += 1
            return True
        return False

    def take(self, kind, value=None):
        token = self.tokens[self.index]
        if token.kind != kind or (value is not None and token.value != value):
            self.fail(token)
        self.index += 1
        return token

    def ends_block(self):
        token = self.tokens[self.index]
        return token.kind == 'eof' or (token.kind == 'keyword' and token.value in _BLOCK_END)

    def chunk(self):
        body = self.block()
        self.take('eof')
        return body

    def block(self):
        body = []
        while not self.ends_block():
            token = self.tokens[self.index]
            if token.kind == 'keyword' and token.value in ('return', 'break'):
                # Lua 5.1: return and break are the last statement of a block.
                self.index += 1
                if token.value == 'break':
                    body.append(_Node('break', token))
                else:
                    empty = self.ends_block() or self.at('op', ';')
                    body.append(_Node('return', token, exprs=[] if empty else self.exprlist()))
                self.accept('op', ';')
                return body
            body.append(self.statement())
            self.accept('op', ';')
        return body

    def name(self):
        token = self.take('name')
        return _Node('name', token, value=token.value, binding=None)

    def statement(self):
        token = self.tokens[self.index]
        word = token.value if token.kind == 'keyword' else None
        if word == 'if':
            return self.if_statement(token)
        if word == 'while':
            self.index += 1
            cond = self.expr()
            self.take('keyword', 'do')
            body = self.block()
            self.take('keyword', 'end')
            return _Node('while', token, cond=cond, body=body)
        if word == 'do':
            self.index += 1
            body = self.block()
            self.take('keyword', 'end')
            return _Node('do', token, body=body)
        if word == 'for':
            return self.for_statement(token)
        if word == 'repeat':
            self.index += 1
            body = self.block()
            self.take('keyword', 'until')
            return _Node('repeat', token, body=body, cond=self.expr())
        if word == 'function':
            self.index += 1
            target = self.name()
            while self.accept('op', '.'):
                key = self.take('name')
                target = _Node('index', key, obj=target, key=_Node('string', key, value=key.value))
            method = self.take('name').value if self.accept('op', ':') else None
            func = self.function_body(token, method is not None)
            return _Node('funcstat', token, target=target, method=method, func=func)
        if word == 'local':
            self.index += 1
            if self.accept('keyword', 'function'):
                name = self.name()
                return _Node('localfunction', token, name=name,
                             func=self.function_body(token, False))
            names = [self.name()]
            while self.accept('op', ','):
                names.append(self.name())
            exprs = self.exprlist() if self.accept('op', '=') else []
            return _Node('local', token, names=names, exprs=exprs)
        expr = self.suffixed()
        if self.at('op', '=') or self.at('op', ','):
            targets = [expr]
            while self.accept('op', ','):
                targets.append(self.suffixed())
            self.take('op', '=')
            for target in targets:
                if target.kind not in ('name', 'index'):
                    raise CatalogSyntaxError('unexpected-token', target.line, target.column)
            return _Node('assign', token, targets=targets, exprs=self.exprlist())
        if expr.kind not in ('call', 'method'):
            raise CatalogSyntaxError('unexpected-token', token.line, token.column)
        return _Node('callstat', token, call=expr)

    def if_statement(self, token):
        clauses = []
        while True:
            self.index += 1
            cond = self.expr()
            self.take('keyword', 'then')
            clauses.append((cond, self.block()))
            if not self.at('keyword', 'elseif'):
                break
        orelse = self.block() if self.accept('keyword', 'else') else None
        self.take('keyword', 'end')
        return _Node('if', token, clauses=clauses, orelse=orelse)

    def for_statement(self, token):
        self.index += 1
        first = self.name()
        if self.accept('op', '='):
            start = self.expr()
            self.take('op', ',')
            stop = self.expr()
            step = self.expr() if self.accept('op', ',') else None
            self.take('keyword', 'do')
            body = self.block()
            self.take('keyword', 'end')
            return _Node('fornum', token, var=first, start=start, stop=stop, step=step, body=body)
        names = [first]
        while self.accept('op', ','):
            names.append(self.name())
        self.take('keyword', 'in')
        exprs = self.exprlist()
        self.take('keyword', 'do')
        body = self.block()
        self.take('keyword', 'end')
        return _Node('forin', token, names=names, exprs=exprs, body=body)

    def function_body(self, token, method):
        self.take('op', '(')
        params, vararg = [], False
        if not self.at('op', ')'):
            while True:
                if self.accept('op', '...'):
                    vararg = True
                    break
                params.append(self.name())
                if not self.accept('op', ','):
                    break
        self.take('op', ')')
        body = self.block()
        self.take('keyword', 'end')
        return _Node('function', token, params=params, vararg=vararg, method=method, body=body)

    def exprlist(self):
        exprs = [self.expr()]
        while self.accept('op', ','):
            exprs.append(self.expr())
        return exprs

    def expr(self):
        """Operands and binary operators in source order; precedence is not
        needed for a binding and is not modelled."""
        operands, ops = [self.unary()], []
        while True:
            token = self.tokens[self.index]
            if token.kind in ('op', 'keyword') and token.value in _BINARY:
                self.index += 1
                ops.append(token.value)
                operands.append(self.unary())
            else:
                break
        if not ops:
            return operands[0]
        return _Node('operation', operands[0], operands=operands, ops=ops)

    def unary(self):
        token = self.tokens[self.index]
        if token.kind in ('op', 'keyword') and token.value in _UNARY:
            self.index += 1
            return _Node('operation', token, operands=[self.unary()], ops=[token.value])
        return self.simple()

    def simple(self):
        token = self.tokens[self.index]
        if token.kind == 'number' or (token.kind == 'keyword'
                                      and token.value in ('nil', 'true', 'false')):
            self.index += 1
            return _Node('constant', token, value=token.value)
        if token.kind == 'string':
            self.index += 1
            return _Node('string', token, value=token.value)
        if token.kind == 'keyword' and token.value == 'function':
            self.index += 1
            return self.function_body(token, False)
        if token.kind == 'op' and token.value == '...':
            self.index += 1
            return _Node('constant', token, value='...')
        if token.kind == 'op' and token.value == '{':
            return self.table()
        return self.suffixed()

    def suffixed(self):
        token = self.tokens[self.index]
        if token.kind == 'name':
            expr = self.name()
        elif token.kind == 'op' and token.value == '(':
            self.index += 1
            inner = self.expr()
            self.take('op', ')')
            expr = _Node('paren', token, expr=inner)
        else:
            self.fail(token)
        while True:
            token = self.tokens[self.index]
            if token.kind == 'op' and token.value == '.':
                self.index += 1
                key = self.take('name')
                expr = _Node('index', token, obj=expr, key=_Node('string', key, value=key.value))
            elif token.kind == 'op' and token.value == '[':
                self.index += 1
                key = self.expr()
                self.take('op', ']')
                expr = _Node('index', token, obj=expr, key=key)
            elif token.kind == 'op' and token.value == ':':
                self.index += 1
                name = self.take('name').value
                expr = _Node('method', token, obj=expr, name=name, args=self.args())
            elif token.kind == 'string' or (token.kind == 'op' and token.value in ('(', '{')):
                expr = _Node('call', token, func=expr, args=self.args())
            else:
                return expr

    def args(self):
        token = self.tokens[self.index]
        if token.kind == 'string':
            self.index += 1
            return [_Node('string', token, value=token.value)]
        if token.kind == 'op' and token.value == '{':
            return [self.table()]
        self.take('op', '(')
        if self.accept('op', ')'):
            return []
        args = self.exprlist()
        self.take('op', ')')
        return args

    def table(self):
        start = self.take('op', '{')
        fields = []
        while not self.at('op', '}'):
            token = self.tokens[self.index]
            if token.kind == 'op' and token.value == '[':
                self.index += 1
                key = self.expr()
                self.take('op', ']')
                self.take('op', '=')
                fields.append(_Node('field', token, key=key, value=self.expr()))
            elif token.kind == 'name' and self.tokens[self.index + 1].kind == 'op' \
                    and self.tokens[self.index + 1].value == '=':
                self.index += 2
                fields.append(_Node('field', token, key=_Node('string', token, value=token.value),
                                    value=self.expr()))
            else:
                fields.append(_Node('field', token, key=None, value=self.expr()))
            if not (self.accept('op', ',') or self.accept('op', ';')):
                break
        self.take('op', '}')
        return _Node('table', start, fields=fields)


def _children(node):
    """The direct child nodes of node, in source order. Declared names are
    not children: they are not expressions."""
    kind = node.kind
    if kind in ('local', 'return'):
        return list(node.exprs)
    if kind == 'localfunction':
        return [node.func]
    if kind == 'funcstat':
        return [node.target, node.func]
    if kind == 'assign':
        return node.targets + node.exprs
    if kind == 'callstat':
        return [node.call]
    if kind in ('do', 'function'):
        return list(node.body)
    if kind == 'while':
        return [node.cond] + node.body
    if kind == 'repeat':
        return node.body + [node.cond]
    if kind == 'if':
        out = []
        for cond, body in node.clauses:
            out.append(cond)
            out.extend(body)
        return out + (node.orelse or [])
    if kind == 'fornum':
        return [node.start, node.stop] + ([node.step] if node.step else []) + node.body
    if kind == 'forin':
        return node.exprs + node.body
    if kind == 'call':
        return [node.func] + node.args
    if kind == 'method':
        return [node.obj] + node.args
    if kind == 'index':
        return [node.obj, node.key]
    if kind == 'paren':
        return [node.expr]
    if kind == 'operation':
        return list(node.operands)
    if kind == 'table':
        return [part for field in node.fields for part in (field.key, field.value) if part]
    return []


def _descendants(nodes, functions=False):
    """Every node under nodes, depth first, entering function bodies only
    when functions is true."""
    stack = list(reversed(nodes))
    while stack:
        node = stack.pop()
        yield node
        if functions or node.kind != 'function':
            stack.extend(reversed(_children(node)))


class _Binding:
    """One local name: how it was declared, the expression it was declared
    with, the name nodes that assign it again and every use as (kind,
    name node)."""

    __slots__ = ('node', 'kind', 'value', 'owner', 'index', 'assigned', 'uses')

    def __init__(self, node, kind, value=None, owner=None, index=None):
        self.node, self.kind, self.value = node, kind, value
        self.owner, self.index = owner, index
        self.assigned, self.uses = [], []


class _Resolver:
    """Lexical resolution of one parsed file: each name node gets its local
    binding or None (a global)."""

    def __init__(self):
        self.localfunctions = []

    def lookup(self, scopes, name):
        for scope in reversed(scopes):
            if name in scope:
                return scope[name]
        return None

    def declare(self, scopes, node, kind, **fields):
        binding = _Binding(node, kind, **fields)
        scopes[-1][node.value] = binding
        node.binding = binding
        return binding

    def reference(self, scopes, node, use):
        binding = self.lookup(scopes, node.value)
        node.binding = binding
        if binding is not None:
            binding.uses.append((use, node))
            if use == 'target':
                binding.assigned.append(node)

    def block(self, body, scopes):
        scopes = scopes + [{}]
        for stmt in body:
            self.statement(stmt, scopes)

    def function(self, func, scopes):
        scopes = scopes + [{}]
        if func.method:
            self.declare(scopes, _Node('name', func, value='self', binding=None), 'param',
                         owner=func, index=None)
        for index, param in enumerate(func.params):
            self.declare(scopes, param, 'param', owner=func, index=index)
        self.block(func.body, scopes)

    def target(self, node, scopes):
        if node.kind == 'name':
            self.reference(scopes, node, 'target')
            return
        if node.obj.kind == 'name':
            self.reference(scopes, node.obj, 'field-target')
        else:
            self.expr(node.obj, scopes)
        self.expr(node.key, scopes)

    def statement(self, stmt, scopes):
        kind = stmt.kind
        if kind == 'local':
            for expr in stmt.exprs:
                self.expr(expr, scopes)
            for index, name in enumerate(stmt.names):
                value = stmt.exprs[index] if index < len(stmt.exprs) else None
                self.declare(scopes, name, 'local', value=value)
        elif kind == 'localfunction':
            self.localfunctions.append(self.declare(scopes, stmt.name, 'localfunction',
                                                    value=stmt.func))
            self.function(stmt.func, scopes)
        elif kind == 'funcstat':
            self.target(stmt.target, scopes)
            self.function(stmt.func, scopes)
        elif kind == 'assign':
            for expr in stmt.exprs:
                self.expr(expr, scopes)
            for target in stmt.targets:
                self.target(target, scopes)
        elif kind == 'callstat':
            self.expr(stmt.call, scopes)
        elif kind == 'do':
            self.block(stmt.body, scopes)
        elif kind == 'while':
            self.expr(stmt.cond, scopes)
            self.block(stmt.body, scopes)
        elif kind == 'repeat':
            # The until condition sees the locals of the loop body.
            inner = scopes + [{}]
            for item in stmt.body:
                self.statement(item, inner)
            self.expr(stmt.cond, inner)
        elif kind == 'if':
            for cond, body in stmt.clauses:
                self.expr(cond, scopes)
                self.block(body, scopes)
            if stmt.orelse is not None:
                self.block(stmt.orelse, scopes)
        elif kind == 'fornum':
            for expr in (stmt.start, stmt.stop, stmt.step):
                if expr is not None:
                    self.expr(expr, scopes)
            inner = scopes + [{}]
            self.declare(inner, stmt.var, 'for')
            self.block(stmt.body, inner)
        elif kind == 'forin':
            for expr in stmt.exprs:
                self.expr(expr, scopes)
            inner = scopes + [{}]
            for name in stmt.names:
                self.declare(inner, name, 'for')
            self.block(stmt.body, inner)
        elif kind == 'return':
            for expr in stmt.exprs:
                self.expr(expr, scopes)

    def expr(self, node, scopes):
        kind = node.kind
        if kind == 'name':
            self.reference(scopes, node, 'value')
        elif kind == 'index':
            if node.obj.kind == 'name':
                self.reference(scopes, node.obj, 'index')
            else:
                self.expr(node.obj, scopes)
            self.expr(node.key, scopes)
        elif kind == 'call':
            if node.func.kind == 'name':
                self.reference(scopes, node.func, 'call')
            else:
                self.expr(node.func, scopes)
            for arg in node.args:
                self.expr(arg, scopes)
        elif kind == 'function':
            self.function(node, scopes)
        else:
            for child in _children(node):
                self.expr(child, scopes)


def _path(node, loose=False, depth=0):
    """The dotted Nexus path an expression names ('Nexus',
    'Nexus.Localization', ...) through the global Nexus, literal fields and
    local aliases, else None. An alias that is assigned again names no path;
    loose=True ignores that, to tell a broken alias of a path apart from an
    unrelated name."""
    if depth > 64:
        return None
    kind = node.kind
    if kind == 'paren':
        return _path(node.expr, loose, depth + 1)
    if kind == 'name':
        binding = node.binding
        if binding is None:
            return 'Nexus' if node.value == 'Nexus' else None
        if binding.kind != 'local' or binding.value is None or (binding.assigned and not loose):
            return None
        return _path(binding.value, loose, depth + 1)
    if kind == 'index':
        base = _path(node.obj, loose, depth + 1)
        if base is not None and node.key.kind == 'string' and node.key.value is not None:
            return base + '.' + node.key.value
    return None


def _seam_method(path):
    """The seam method name a path names (Nexus.Localization.<name>), else None."""
    prefix = _LOCALIZATION + '.'
    if path is not None and path.startswith(prefix) and '.' not in path[len(prefix):]:
        return path[len(prefix):]
    return None


def _literal_map(binding, string_values):
    """[(code, value node)] of a read-only local table of literal string keys
    (and literal string values when string_values), else None. The table
    must never be assigned again and only ever be indexed."""
    if binding is None or binding.kind != 'local' or binding.value is None:
        return None
    table = binding.value
    if table.kind != 'table' or binding.assigned or any(use != 'index'
                                                        for use, _ in binding.uses):
        return None
    entries, seen = [], set()
    for field in table.fields:
        if field.key is None or field.key.kind != 'string' or field.key.value is None:
            return None
        if string_values and (field.value.kind != 'string' or field.value.value is None):
            return None
        if field.key.value in seen:
            return None
        seen.add(field.key.value)
        entries.append((field.key.value, field.value))
    return entries


def _frames(ctx):
    """The context chain of the walker as a list, outermost first."""
    frames = []
    while ctx is not None:
        ctx, entry = ctx
        frames.append(entry)
    frames.reverse()
    return frames


class _UnitScan:
    """The binding facts of one parsed file that need neither its path nor
    the declarations: problems, dynamic constructs, literal sites, wrappers,
    map dispatches and Nexus path assignments. Memoized with the parse;
    receipts copy its rows and never change them."""

    def __init__(self, body, localfunctions):
        self.problems, self.dynamic, self.literals = [], [], []
        self.wrappers, self.internal = {}, set()
        self.candidates, self.seam_assignments, self.path_assignments = [], [], {}
        self.find_wrappers(localfunctions)
        self.block(body, (None, ('function', None, None)))

    # -- recording ---------------------------------------------------------

    def problem(self, node, code, **fields):
        row = {'code': code, 'line': node.line, 'column': node.column}
        row.update(fields)
        self.problems.append(row)

    def unknown(self, node, construct, **fields):
        row = {'line': node.line, 'column': node.column, 'construct': construct}
        row.update(fields)
        self.dynamic.append(row)

    # -- wrappers ----------------------------------------------------------

    def find_wrappers(self, localfunctions):
        """A local function is a wrapper when a consumer-method call on a
        receiver in its own body takes one of its parameters, never
        assigned, as the key. Through a reassigned alias it is no wrapper;
        the walk reports that call as unresolved. Whether the wrapper
        returns that result is proved when a receipt links the units."""
        for binding in localfunctions:
            func = binding.value
            found = []
            for node in _descendants(func.body):
                if node.kind != 'call' or not node.args or node.args[0].kind != 'name':
                    continue
                param = node.args[0].binding
                if param is None or param.kind != 'param' or param.owner is not func:
                    continue
                method = _seam_method(_path(node.func))
                if method in _KEY_METHODS and not param.assigned:
                    found.append((node, param.index, method))
            kinds = {(index, _KEY_METHODS[method]) for _, index, method in found}
            if len(kinds) > 1:
                self.problem(binding.node, 'binding-unresolved', construct='wrapper',
                             detail='the wrapper passes different parameters or kinds')
                continue
            if found:
                index, kind = kinds.pop()
                self.wrappers[binding] = {
                    'name': binding.node.value, 'line': binding.node.line, 'parameter': index,
                    'kind': kind, 'method': found[0][2], 'internal': [node for node, _, _ in found]}
                self.internal.update(id(node) for node, _, _ in found)

    # -- the walk ----------------------------------------------------------

    def block(self, body, ctx):
        for index, stmt in enumerate(body):
            self.statement(stmt, (ctx, ('statement', body, index)))

    def statement(self, stmt, ctx):
        kind = stmt.kind
        if kind == 'localfunction':
            self.function(stmt.func, ctx, None)
        elif kind == 'funcstat':
            self.target(stmt.target, stmt.func, ctx)
            self.function(stmt.func, ctx, stmt)
        elif kind == 'assign':
            for expr in stmt.exprs:
                self.expr(expr, ctx)
            for index, target in enumerate(stmt.targets):
                self.target(target, stmt.exprs[index] if index < len(stmt.exprs) else None, ctx)
        elif kind in ('do', 'while', 'repeat', 'if', 'fornum', 'forin'):
            for child in _children(stmt):
                if child.kind not in _STATEMENTS:
                    self.expr(child, ctx)
            for body in _bodies(stmt):
                self.block(body, ctx)
        elif kind in ('local', 'return'):
            for expr in stmt.exprs:
                self.expr(expr, ctx)
        elif kind == 'callstat':
            self.expr(stmt.call, ctx)

    def function(self, func, ctx, funcstat):
        self.block(func.body, (ctx, ('function', func, funcstat)))

    def target(self, target, value, ctx):
        """An assignment or function definition target: seam mutation and
        Nexus path assignments are recorded."""
        if target.kind == 'index':
            if target.obj.kind != 'name':
                self.expr(target.obj, ctx)
            self.expr(target.key, ctx)
        path = _path(target)
        if path is None:
            return
        self.path_assignments.setdefault(path, []).append((target, value))
        if path == 'Nexus':
            bootstrap = (value is not None and value.kind == 'operation' and value.ops == ['or']
                         and value.operands[0].kind == 'name'
                         and value.operands[0].binding is None
                         and value.operands[0].value == 'Nexus'
                         and value.operands[1].kind == 'table'
                         and not value.operands[1].fields)
            if not bootstrap:
                self.problem(target, 'binding-mutation', construct='nexus-reassigned',
                             detail='the global Nexus is assigned something other than '
                                    'Nexus or {}')
        elif path == _LOCALIZATION or path.startswith(_LOCALIZATION + '.'):
            self.seam_assignments.append((target, path))

    def expr(self, node, ctx):
        kind = node.kind
        if kind == 'call':
            self.call(node, ctx)
        elif kind == 'method':
            if _path(node.obj, True) == _LOCALIZATION and node.name in _SEAM_METHODS:
                self.problem(node, 'binding-unresolved', construct='method-call',
                             detail='%s:%s passes the seam table as its key'
                                    % (_LOCALIZATION, node.name))
            self.expr(node.obj, ctx)
            for arg in node.args:
                self.expr(arg, ctx)
        elif kind == 'index':
            self.member(node, ctx)
        elif kind == 'paren':
            self.expr(node.expr, ctx)
        elif kind == 'function':
            self.function(node, ctx, None)
        else:
            for child in _children(node):
                self.expr(child, ctx)

    def member(self, node, ctx, checked=False):
        """A field read. A consumer method read without being called (other
        than inside type()) is an indirect reference; a computed field of
        the seam is a dynamic member."""
        path = _path(node)
        if not checked and _seam_method(path) in _KEY_METHODS:
            self.problem(node, 'binding-unresolved', construct='indirect-key-method',
                         detail='%s is read without being called' % path)
        elif node.key.kind != 'string' and _path(node.obj) == _LOCALIZATION:
            self.unknown(node, 'dynamic-member')
        if node.obj.kind != 'name':
            self.expr(node.obj, ctx)
        self.expr(node.key, ctx)

    def call(self, node, ctx):
        func, args = node.func, node.args
        path = _path(func)
        method = _seam_method(path)
        if method in _SEAM_METHODS:
            self.seam_call(node, method)
        elif path is None and _seam_method(_path(func, True)) in _SEAM_METHODS:
            self.problem(node, 'binding-unresolved', construct='alias',
                         detail='a local alias of %s on the way is assigned again'
                                % _LOCALIZATION)
        elif path is None and func.kind == 'index' and func.key.kind == 'string' \
                and func.key.value in _KEY_METHODS and func.obj.kind == 'index' \
                and func.obj.key.kind == 'string' and func.obj.key.value == 'Localization' \
                and args and args[0].kind == 'string':
            self.unknown(node, 'unresolved-receiver', literal=args[0].value)
        elif func.kind == 'name' and func.binding in self.wrappers:
            self.wrapper_call(node, func.binding, ctx)
        if func.kind == 'index':
            self.member(func, ctx, checked=True)
        elif func.kind != 'name':
            self.expr(func, ctx)
        global_name = func.value if func.kind == 'name' and func.binding is None else None
        if global_name == 'rawget' and len(args) >= 2 and _path(args[0]) == _LOCALIZATION:
            if args[1].kind != 'string':
                self.unknown(node, 'dynamic-member')
            elif args[1].value in _KEY_METHODS:
                self.problem(node, 'binding-unresolved', construct='indirect-key-method',
                             detail='rawget reads %s.%s' % (_LOCALIZATION, args[1].value))
        for arg in args:
            if global_name == 'type' and len(args) == 1 and arg.kind == 'index':
                self.member(arg, ctx, checked=True)
            else:
                self.expr(arg, ctx)

    def seam_call(self, node, method):
        func = node.func
        while func.kind == 'paren':
            func = func.expr
        if func.kind != 'index':
            # A local alias of the method itself: its declaration is already
            # an indirect-key-method problem, and the call never binds.
            return
        arg = node.args[0] if node.args else None
        if arg is not None and arg.kind == 'string' and arg.value is not None:
            obj = func.obj
            while obj.kind == 'paren':
                obj = obj.expr
            if obj.kind == 'name' and obj.binding is not None:
                receiver = {'form': 'alias', 'name': obj.value, 'line': obj.binding.node.line}
            else:
                receiver = {'form': 'path', 'name': _LOCALIZATION}
            self.literals.append((arg, method, _KEY_METHODS.get(method), node, {
                'site': 'direct-call', 'method': method, 'receiver': receiver}, None))
        elif method in _KEY_METHODS and id(node) not in self.internal:
            self.unknown(node, 'dynamic-key', method=method)

    def wrapper_call(self, node, binding, ctx):
        wrapper = self.wrappers[binding]
        if binding.assigned:
            self.problem(node, 'binding-unresolved', construct='wrapper',
                         detail='the wrapper %s is assigned again' % wrapper['name'])
            return
        index = wrapper['parameter']
        arg = node.args[index] if index < len(node.args) else None
        if arg is not None and arg.kind == 'string' and arg.value is not None:
            self.literals.append((arg, wrapper['method'], wrapper['kind'], node, {
                'site': 'wrapper-call', 'method': wrapper['method'],
                'wrapper': {'name': wrapper['name'], 'line': wrapper['line']}}, binding))
        elif arg is not None and arg.kind == 'index' and arg.obj.kind == 'name' \
                and arg.key.kind == 'name' and arg.obj.binding is not None \
                and arg.obj.binding.kind == 'local' and arg.obj.binding.value is not None \
                and arg.obj.binding.value.kind == 'table':
            # A local table constructor indexed by a name: a map dispatch,
            # bound or explicitly unresolved, never silently dynamic.
            self.dispatch(node, binding, arg, ctx)
        else:
            self.unknown(node, 'dynamic-wrapper-argument', wrapper=wrapper['name'])

    # -- map dispatch ------------------------------------------------------

    def dispatch(self, node, wrapper, arg, ctx):
        """A wrapper(MAP[v], ...) call: checked here for its local shape and
        preceding guards; its dispatcher and output chain are proved when a
        receipt links the units."""
        mapping, variable = arg.obj.binding, arg.key.binding
        entries = _literal_map(mapping, True)
        if entries is None:
            self.problem(node, 'binding-unresolved', construct='map',
                         detail='%s is not a read-only local table of literal string pairs'
                                % arg.obj.value)
            return
        reason, shadow, frames = None, {}, _frames(ctx)
        start = max(index for index, entry in enumerate(frames) if entry[0] == 'function')
        _, func, funcstat = frames[start]
        tail = frames[start + 1:]
        statement = tail[0][1][tail[0][2]] if len(tail) == 2 and func is not None else None
        if statement is None or tail[0][1] is not func.body or statement.kind != 'if' \
                or len(statement.clauses) != 1 or statement.orelse is not None \
                or tail[1][1] is not statement.clauses[0][1]:
            reason = 'the call is not the return of an if MAP[v] then ... end in a function body'
        else:
            cond, returned = statement.clauses[0][0], tail[1][1][tail[1][2]]
            if not (cond.kind == 'index' and cond.obj.kind == 'name'
                    and cond.obj.binding is mapping and cond.key.kind == 'name'
                    and cond.key.binding is variable and returned.kind == 'return'
                    and len(returned.exprs) == 1 and returned.exprs[0] is node):
                reason = 'the call is not the sole return guarded by the same MAP[v]'
            elif not _unassigned_until(variable, func, tail[0][2]):
                reason = ('the dispatch variable is not a local of this function left unassigned '
                          'up to the dispatch')
            elif funcstat is None or funcstat.method is not None \
                    or funcstat.target.kind != 'index' or funcstat.target.obj.kind != 'name':
                reason = 'the dispatch is not in a function T.Name of a module table'
        if reason is None:
            for earlier in func.body[:tail[0][2]]:
                guard = _guard(earlier, variable)
                if guard is not None:
                    codes = _literal_map(guard.binding, False)
                    if codes is None:
                        reason = '%s is not a read-only local table of literal keys' % guard.value
                        break
                    for code, _ in codes:
                        shadow.setdefault(code, guard.value)
                elif any(item.kind == 'return' for item in _descendants([earlier])):
                    reason = 'an earlier statement at line %d can return first' % earlier.line
                    break
        if reason is not None:
            self.problem(node, 'binding-unresolved', construct='dispatch', detail=reason)
            return
        self.candidates.append({'node': node, 'wrapper': wrapper, 'map': mapping,
                                'entries': entries, 'shadow': shadow, 'func': func,
                                'funcstat': funcstat})


_STATEMENTS = frozenset(('local', 'localfunction', 'funcstat', 'assign', 'callstat', 'do',
                         'while', 'repeat', 'if', 'fornum', 'forin', 'return', 'break'))
# Evidenced output sinks: argument 1 of these widget, tooltip and chat-frame
# methods, and every argument of the global print.
_SINK_METHODS = frozenset(('SetText', 'AddLine', 'AddMessage'))
_SINK_FUNCTIONS = frozenset(('print',))
_COMPARISON = frozenset(('==', '~=', '<', '<=', '>', '>='))
_OPAQUE = None


def _bodies(stmt):
    """The nested blocks of a compound statement."""
    if stmt.kind == 'if':
        return [body for _, body in stmt.clauses] + ([stmt.orelse] if stmt.orelse else [])
    return [stmt.body]


def _unassigned_until(variable, func, index):
    """True when variable is a parameter of func or a local declared by an
    earlier statement of its body, and no statement of the body up to and
    including statement index, closures included, assigns it."""
    if variable is None:
        return False
    body = func.body[:index + 1]
    declared = (variable.kind == 'param' and variable.owner is func) or (
        variable.kind == 'local' and any(stmt.kind == 'local' and any(
            name.binding is variable for name in stmt.names) for stmt in body[:-1]))
    early = {id(node) for node in _descendants(body, True)}
    return declared and not any(id(node) in early for node in variable.assigned)


def _guard(stmt, variable):
    """The table name node of an 'if OTHER[v] then ... end' statement over
    the same variable, else None."""
    if stmt.kind != 'if' or len(stmt.clauses) != 1 or stmt.orelse is not None:
        return None
    cond = stmt.clauses[0][0]
    if cond.kind == 'index' and cond.obj.kind == 'name' and cond.key.kind == 'name' \
            and cond.key.binding is variable and variable is not None:
        return cond.obj
    return None


def _flowing_operands(node):
    """The operands of an operation whose text can be part of its value, by
    Lua 5.1 precedence: in each 'or' alternative only the last element of
    its 'and' chain, and in that element each single operand joined by '..'.
    A comparison, arithmetic or unary result carries no text."""
    operands, ops = node.operands, node.ops
    if len(operands) == 1:
        return []

    def split(start, end, op):
        pieces, begin = [], start
        for index in range(start, end - 1):
            if ops[index] == op:
                pieces.append((begin, index + 1))
                begin = index + 1
        return pieces + [(begin, end)]
    flowing = []
    for low, high in split(0, len(operands), 'or'):
        start, end = split(low, high, 'and')[-1]
        if any(ops[index] in _COMPARISON for index in range(start, end - 1)):
            continue
        flowing.extend(operands[begin] for begin, stop in split(start, end, '..')
                       if stop - begin == 1)
    return flowing


def _module_root(binding):
    """The binding a chain of unassigned local aliases (local a = b) names."""
    for _ in range(16):
        value = binding.value
        if binding.kind != 'local' or binding.assigned or value is None \
                or value.kind != 'name' or value.binding is None:
            return binding
        binding = value.binding
    return binding


class _UnitFlow:
    """The may-flow graph of one parsed file, built once with its parse.

    A value flows from an expression into a paren, into an operation for the
    operands _flowing_operands names, into the binding a local statement or
    assignment gives it, into a table field by name (constructor or literal
    field assignment), into the return of its function (first value only),
    into the parameter of a local function it is passed to, and into
    argument 1 of a _SINK_METHODS call or any argument of a _SINK_FUNCTIONS
    call, the outputs. A binding passes a value on to its reads only when
    every definition (its declared value and every assignment, closures
    included) carries a value of the same proof; a value-less definition
    such as a for variable or a later multiple-value position never does.
    A field name is one channel across every table and file, under the
    same every-definition rule. Function results reach the calls the
    receipt can resolve: local functions here, module functions and their
    Nexus exports when the units are linked."""

    def __init__(self, body):
        self.edges, self.defs, self.def_of = {}, {}, {}
        self.field_writes, self.field_reads, self.field_def_of = {}, {}, {}
        self.path_calls, self.module_calls = {}, []
        self.module_defs, self.dynamic_modules = {}, set()
        self.alias_of, self.export_values, self.exports = {}, set(), []
        self.chunk_returns = set()
        self.block(body, None)
        self.module_funcs = {}
        for module, fields in self.module_defs.items():
            for name, values in fields.items():
                value = values[0] if len(values) == 1 else None
                self.module_funcs[(module, name)] = (
                    value if value is not None and value.kind == 'function' else None,
                    len(values))

    def edge(self, source, target):
        self.edges.setdefault(source, []).append(target)

    def define(self, binding, value):
        self.defs.setdefault(binding, []).append(value)
        if value is not _OPAQUE:
            self.edge(value, binding)
            self.def_of.setdefault(value, []).append(binding)

    def write_field(self, name, value):
        self.field_writes.setdefault(name, []).append(value)
        if value is not _OPAQUE:
            self.edge(value, ('field', name))
            self.field_def_of.setdefault(value, []).append(name)

    def module_ok(self, binding, depth=0):
        """A local module table (or alias of one) whose identity stays here:
        never assigned again, never written through a computed key, and used
        only through literal fields, by its Nexus export, as a value the
        file chunk returns (discarded by the TOC loader) or by a local alias
        with the same properties."""
        if depth > 16 or binding.kind != 'local' or binding.assigned \
                or binding in self.dynamic_modules:
            return False
        for use, node in binding.uses:
            if use in ('index', 'field-target'):
                continue
            alias = self.alias_of.get(node) if use == 'value' else None
            if use == 'value' and (node in self.export_values or node in self.chunk_returns or (
                    alias is not None and self.module_ok(alias, depth + 1))):
                continue
            return False
        return True

    def block(self, body, func):
        for stmt in body:
            self.statement(stmt, func)

    def statement(self, stmt, func):
        kind = stmt.kind
        if kind == 'local':
            for expr in stmt.exprs:
                self.expr(expr, func)
            for index, name in enumerate(stmt.names):
                if index < len(stmt.exprs):
                    value = stmt.exprs[index]
                    self.define(name.binding, value)
                    if value.kind == 'name' and value.binding is not None:
                        self.alias_of[value] = name.binding
                elif stmt.exprs:
                    self.define(name.binding, _OPAQUE)
        elif kind == 'localfunction':
            self.function(stmt.func)
        elif kind in ('funcstat', 'assign'):
            if kind == 'funcstat':
                targets, values = [stmt.target], [stmt.func]
                self.function(stmt.func)
            else:
                targets, values = stmt.targets, stmt.exprs
                for expr in values:
                    self.expr(expr, func)
            for index, target in enumerate(targets):
                value = values[index] if index < len(values) else _OPAQUE
                self.target(target, value, func)
        elif kind == 'callstat':
            self.expr(stmt.call, func)
        elif kind == 'return':
            for expr in stmt.exprs:
                self.expr(expr, func)
            if func is not None and stmt.exprs:
                self.edge(stmt.exprs[0], ('ret', func))
            elif func is None:
                # The WoW TOC loader discards a file chunk's return values.
                self.chunk_returns.update(expr for expr in stmt.exprs if expr.kind == 'name')
        elif kind in ('fornum', 'forin'):
            for expr in (stmt.start, stmt.stop, stmt.step) if kind == 'fornum' else stmt.exprs:
                if expr is not None:
                    self.expr(expr, func)
            for name in [stmt.var] if kind == 'fornum' else stmt.names:
                self.define(name.binding, _OPAQUE)
            self.block(stmt.body, func)
        elif kind in ('do', 'while', 'repeat', 'if'):
            for child in _children(stmt):
                if child.kind not in _STATEMENTS:
                    self.expr(child, func)
            for body in _bodies(stmt):
                self.block(body, func)

    def target(self, target, value, func):
        if target.kind == 'name':
            if target.binding is not None:
                self.define(target.binding, value)
            elif _path(target) is not None and value is not _OPAQUE and value.kind == 'name':
                self.export_values.add(value)
            return
        if target.obj.kind != 'name':
            self.expr(target.obj, func)
        self.expr(target.key, func)
        base = target.obj.binding if target.obj.kind == 'name' else None
        if target.key.kind != 'string' or target.key.value is None:
            if base is not None:
                self.dynamic_modules.add(_module_root(base))
            return
        self.write_field(target.key.value, value)
        if base is not None:
            fields = self.module_defs.setdefault(_module_root(base), {})
            fields.setdefault(target.key.value, []).append(value)
        path = _path(target)
        if path is not None and path.count('.') == 1 and value is not _OPAQUE \
                and value.kind == 'name' and value.binding is not None:
            self.export_values.add(value)
            self.exports.append((path, value.binding))

    def function(self, func):
        for param in func.params:
            self.defs.setdefault(param.binding, [])
        self.block(func.body, func)

    def expr(self, node, func):
        kind = node.kind
        if kind == 'name':
            if node.binding is not None:
                self.edge(node.binding, node)
        elif kind == 'index':
            self.expr(node.obj, func)
            self.expr(node.key, func)
            if node.key.kind == 'string' and node.key.value is not None:
                self.field_reads.setdefault(node.key.value, []).append(node)
        elif kind == 'paren':
            self.expr(node.expr, func)
            self.edge(node.expr, node)
        elif kind == 'operation':
            for operand in node.operands:
                self.expr(operand, func)
            for operand in _flowing_operands(node):
                self.edge(operand, node)
        elif kind == 'call':
            self.call(node, func)
        elif kind == 'method':
            self.expr(node.obj, func)
            for arg in node.args:
                self.expr(arg, func)
            if node.name in _SINK_METHODS and node.args:
                self.edge(node.args[0], ('sink', node))
        elif kind == 'function':
            self.function(node)
        elif kind == 'table':
            for field in node.fields:
                if field.key is not None:
                    self.expr(field.key, func)
                self.expr(field.value, func)
                if field.key is not None and field.key.kind == 'string' \
                        and field.key.value is not None:
                    self.write_field(field.key.value, field.value)

    def call(self, node, func):
        callee, args = node.func, node.args
        self.expr(callee, func)
        for arg in args:
            self.expr(arg, func)
        if callee.kind == 'name' and callee.binding is None and callee.value in _SINK_FUNCTIONS:
            for arg in args:
                self.edge(arg, ('sink', node))
        binding = callee.binding if callee.kind == 'name' else None
        if binding is not None and not binding.assigned and binding.value is not None \
                and binding.value.kind == 'function' and binding.kind in ('local',
                                                                          'localfunction'):
            target = binding.value
            self.edge(('ret', target), node)
            for param, arg in zip(target.params, args):
                self.edge(arg, param.binding)
        if callee.kind == 'index' and callee.obj.kind == 'name' and callee.obj.binding \
                is not None and callee.key.kind == 'string':
            self.module_calls.append((_module_root(callee.obj.binding), callee.key.value,
                                      node))
        path = _path(callee)
        if path is not None:
            self.path_calls.setdefault(path, []).append(node)


class _Unit:
    """One loaded Lua source and its memoized parse, scan and flow graph."""

    def __init__(self, path, data, order, fresh):
        self.path, self.data, self.order = path, data, order
        self.body, self.error, self.leads, self.scan, self.flow = _parsed(data, fresh)


# Parsed files memoized by the SHA-256 of their exact bytes, oldest dropped
# first. A parse, its scan and its flow graph depend only on those bytes,
# and linking never changes them, so a memoized parse is the same parse;
# nothing is read or written. Two equal files of one call get separate
# parses (fresh), so their local names stay distinct.
_PARSE_MEMO = {}
_PARSE_MEMO_LIMIT = 256


def _parsed(data, fresh=False):
    """(syntax tree or None, error or None, string literals as (value, line,
    column), scan, flow) of the exact bytes of one Lua file."""
    digest = hashlib.sha256(data).digest()
    if digest in _PARSE_MEMO and not fresh:
        return _PARSE_MEMO[digest]
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        result = None, {'code': 'not-utf8'}, [], None, None
    else:
        try:
            tokens = _lua_tokens(text)
            body = _LuaParser(tokens).chunk()
            resolver = _Resolver()
            resolver.block(body, [])
            scan, flow = _UnitScan(body, resolver.localfunctions), _UnitFlow(body)
        except CatalogSyntaxError as error:
            result = None, {'code': error.code, 'line': error.line,
                            'column': error.column}, [], None, None
        except RecursionError:
            result = None, {'code': 'nesting-too-deep'}, [], None, None
        else:
            leads = [(token.value, token.line, token.column) for token in tokens
                     if token.kind == 'string']
            result = body, None, leads, scan, flow
    while len(_PARSE_MEMO) >= _PARSE_MEMO_LIMIT:
        del _PARSE_MEMO[next(iter(_PARSE_MEMO))]
    _PARSE_MEMO[digest] = result
    return result


class _Linker:
    """Joins the parsed units of one receipt: module exports, function
    results across files, field channels, wrappers, map dispatches and the
    output proof of every literal site (see the S8 notes above)."""

    def __init__(self, units, declarations):
        self.units = [unit for unit in units if unit.scan is not None]
        self.declarations = declarations
        self.owner = {id(unit.flow): unit for unit in self.units}
        self.assignments = {}
        for unit in self.units:
            for path, rows in unit.scan.path_assignments.items():
                self.assignments.setdefault(path, []).extend(rows)
        self.field_cache, self.ret_links = {}, {}
        for unit in self.units:
            flow = unit.flow
            exports = {}
            for path, module in flow.exports:
                exports.setdefault(module, []).append(path)
            for module, name, call in flow.module_calls:
                func = self.module_function(flow, module, name, exports.get(module, ()))[0]
                if func is not None:
                    self.ret_links.setdefault(func, []).append((call, flow))
            for module, paths in exports.items():
                for (owner, name), _ in flow.module_funcs.items():
                    if owner is not module:
                        continue
                    func = self.module_function(flow, module, name, paths)[0]
                    if func is not None:
                        self.ret_links.setdefault(func, []).extend(
                            (('pret', path + '.' + name), None) for path in paths)

    def export_ok(self, path, module, name):
        rows = self.assignments.get(path, ())
        return (len(rows) == 1 and rows[0][1] is not None and rows[0][1].kind == 'name'
                and rows[0][1].binding is module and not self.assignments.get(path + '.' + name))

    def module_function(self, flow, module, name, exports):
        """(function node or None, reason) for module.name: one definition,
        on a module table whose identity stays in its file, with every Nexus
        export of it assigned once and its field never assigned by path."""
        if module.value is None or module.value.kind != 'table' or not flow.module_ok(module):
            return None, ('the module table %s is assigned again, written through a computed '
                          'key or escapes its file' % module.node.value)
        func, count = flow.module_funcs.get((module, name), (None, 0))
        if count != 1 or func is None:
            return None, ('%s.%s has %d definitions, directly or through a local alias'
                          % (module.node.value, name, count))
        for path in exports:
            if not self.export_ok(path, module, name):
                return None, '%s or %s.%s is assigned elsewhere' % (path, path, name)
        return func, None

    # -- the may-flow search -----------------------------------------------

    def field_defs(self, name):
        if name not in self.field_cache:
            self.field_cache[name] = [value for unit in self.units
                                      for value in unit.flow.field_writes.get(name, ())]
        return self.field_cache[name]

    def gate(self, key, flow):
        """The definitions a binding or field node needs, else None."""
        if type(key) is tuple:
            return self.field_defs(key[1]) if key[0] == 'field' else None
        if type(key) is _Binding:
            return flow.defs.get(key, ())
        return None

    def successors(self, key, flow):
        if type(key) is tuple:
            tag = key[0]
            if tag == 'field':
                return [(read, unit.flow) for unit in self.units
                        for read in unit.flow.field_reads.get(key[1], ())]
            if tag == 'pret':
                return [(call, unit.flow) for unit in self.units
                        for call in unit.flow.path_calls.get(key[1], ())]
            if tag == 'ret':
                out = [(nxt, flow) for nxt in flow.edges.get(key, ())]
                for nxt, owner in self.ret_links.get(key[1], ()):
                    out.append((nxt, owner))
                return out
            if tag == 'sink':
                return []
        return [(nxt, flow) for nxt in flow.edges.get(key, ())]

    def search(self, roots, allowed=None, stop=None):
        """Every key reached from roots [(key, flow)]. A binding or field
        passes a value on only when all its definitions are in allowed, or,
        with allowed None, in the reached set itself (a fixpoint). Returns
        (reached keys, sink keys with their flow)."""
        reached, waiting, sinks = set(), {}, {}
        queue = list(roots)
        while queue:
            key, flow = queue.pop()
            if key in reached:
                continue
            needs = self.gate(key, flow)
            if needs is not None:
                pool = reached if allowed is None else allowed
                if any(value is _OPAQUE or value not in pool for value in needs):
                    waiting[key] = flow
                    continue
            reached.add(key)
            if type(key) is tuple and key[0] == 'sink':
                sinks[key] = flow
                continue
            if allowed is None and flow is not None:
                for binding in flow.def_of.get(key, ()):
                    if binding in waiting:
                        queue.append((binding, waiting.pop(binding)))
                for name in flow.field_def_of.get(key, ()):
                    if ('field', name) in waiting:
                        queue.append((('field', name), waiting.pop(('field', name))))
            if key == stop:
                continue
            queue.extend(self.successors(key, flow))
        return reached, sinks

    def outputs(self, sinks):
        rows = []
        for (_, node), flow in sinks.items():
            unit = self.owner[id(flow)]
            name = node.name if node.kind == 'method' else node.func.value
            rows.append(((unit.order, node.line, node.column),
                         {'path': unit.path, 'line': node.line, 'column': node.column,
                          'output': name}))
        return [row for _, row in sorted(rows, key=lambda item: item[0])]

    def wrapper_returns(self, binding, unit):
        """True when a wrapper's own consumer-method result reaches its return."""
        info = unit.scan.wrappers[binding]
        stop = ('ret', binding.value)
        reached, _ = self.search([(node, unit.flow) for node in info['internal']], stop=stop)
        return stop in reached

    def prove(self, roots_by_key):
        """{key: {id(root): outputs}} for the roots of each key whose value
        reaches an output, under the every-definition rule of that key."""
        proofs = {}
        for key, roots in roots_by_key.items():
            allowed, _ = self.search(roots)
            proofs[key] = {}
            for root in roots:
                _, sinks = self.search([root], allowed)
                if sinks:
                    proofs[key][id(root[0])] = self.outputs(sinks)
        return proofs


def consumer_binding_report(english_source: bytes, packs_source: bytes, key_context_json: bytes,
                            release_json: bytes, localization_source: bytes, toc_records,
                            source_records) -> dict:
    """The static consumer binding receipt (see above) for the exact bytes of
    the five registry-bound inputs, the TOC records and the source records.
    A non-bytes registry input is a TypeError, an invalid catalog raises its
    strict error unchanged and a record failure raises CatalogConsumerError.
    No file is read or written, nothing is fetched, executed or modified, and
    only the in-memory parse memo (_PARSE_MEMO) is kept between calls."""
    registry = (english_source, packs_source, key_context_json, release_json,
                localization_source)
    for name, value in zip(('english_source', 'packs_source', 'key_context_json',
                            'release_json', 'localization_source'), registry):
        if not isinstance(value, (bytes, bytearray)):
            raise TypeError('%s must be bytes, not %s' % (name, type(value).__name__))
    registry = tuple(bytes(value) for value in registry)
    tocs, supplied, listed = _consumer_inputs(
        (registry[0], registry[1], registry[4]), toc_records, source_records)
    # The strict registry-bound verdict first: an invalid catalog gets no receipt.
    registry_catalog_report(*registry)
    validated = validate_registry_catalog_data(*registry)
    declarations, context = validated['declarations'], validated['keyContext']
    units, contents = [], set()
    for path in listed:
        data = supplied[path]
        units.append(_Unit(path, data, listed[path][2], data in contents))
        contents.add(data)
    linker = _Linker(units, declarations)
    problems, dynamic, shadowed, chains = [], [], [], []

    def located(unit, row):
        """A copy of a memoized row with the unit's current path; nested
        dicts are copied too, so no receipt shares an object with the memo."""
        out = {'code': row['code'], 'path': unit.path} if 'code' in row else {'path': unit.path}
        out.update((field, dict(value) if type(value) is dict else value)
                   for field, value in row.items() if field != 'code')
        return (unit.order, row['line'], row['column']), out

    candidates = {key: [] for key in declarations}   # key -> [(root, flow, unit, row, wrapper)]
    for unit in linker.units:
        scan = unit.scan
        problems.extend(located(unit, row) for row in scan.problems)
        dynamic.extend(located(unit, row) for row in scan.dynamic)
        for target, path in scan.seam_assignments:
            if unit.path != _AUTHORITY:
                problems.append(located(unit, {
                    'code': 'binding-mutation', 'line': target.line, 'column': target.column,
                    'construct': 'seam-assignment',
                    'detail': '%s is assigned outside %s' % (path, _AUTHORITY)}))
        for arg, method, kind, root, site, wrapper in scan.literals:
            declaration = declarations.get(arg.value)
            where = {'line': arg.line, 'column': arg.column}
            if declaration is None:
                problems.append(located(unit, dict(where, code='binding-orphan', key=arg.value,
                                                   method=method)))
            elif kind is None:
                continue
            elif declaration['kind'] != kind:
                problems.append(located(unit, dict(where, code='binding-kind', key=arg.value,
                                                   method=method,
                                                   declaredKind=declaration['kind'])))
            else:
                row = located(unit, dict(where, **site))
                if wrapper is not None:
                    row[1]['wrapper'] = dict(row[1]['wrapper'], path=unit.path)
                candidates[arg.value].append((root, unit.flow, unit, row, wrapper))
    wrappers = {}

    def wrapper_proved(binding, unit):
        if binding not in wrappers:
            wrappers[binding] = linker.wrapper_returns(binding, unit)
        return wrappers[binding]

    for unit in linker.units:
        for candidate in unit.scan.candidates:
            node, funcstat, wrapper = candidate['node'], candidate['funcstat'], candidate['wrapper']
            info = unit.scan.wrappers[wrapper]
            module = _module_root(funcstat.target.obj.binding) \
                if funcstat.target.obj.binding is not None else None
            name = funcstat.target.key.value
            exports = sorted(path for path, binding in unit.flow.exports if binding is module)
            func, reason = (None, 'the dispatcher is not defined on a local module table') \
                if module is None else linker.module_function(unit.flow, module, name, exports)
            if reason is None and func is not candidate['func']:
                reason = '%s.%s is not this function' % (module.node.value, name)
            if reason is None and not exports:
                reason = 'the module table %s is not exported as a Nexus path' % module.node.value
            if reason is not None:
                problems.append(located(unit, {
                    'code': 'binding-unresolved', 'line': node.line, 'column': node.column,
                    'construct': 'dispatcher', 'detail': reason}))
                continue
            chain = {'map': {'name': candidate['map'].node.value, 'path': unit.path,
                             'line': candidate['map'].node.line},
                     'wrapper': {'name': info['name'], 'path': unit.path, 'line': info['line'],
                                 'method': info['method']},
                     'dispatch': {'path': unit.path, 'line': node.line, 'column': node.column},
                     'dispatcher': exports[0] + '.' + name,
                     'entries': len(candidate['entries']), 'boundKeys': [],
                     'shadowedEntries': [], 'wrapperReturnsResult': wrapper_proved(wrapper, unit),
                     'outputs': []}
            chains.append((unit, node, chain))
            for code, value in candidate['entries']:
                if code in candidate['shadow']:
                    row = {'code': code, 'key': value.value, 'path': unit.path,
                           'line': value.line, 'column': value.column,
                           'shadowedBy': candidate['shadow'][code]}
                    chain['shadowedEntries'].append(row)
                    shadowed.append(((unit.order, value.line, value.column), row))
                    continue
                declaration = declarations.get(value.value)
                where = {'line': value.line, 'column': value.column}
                if declaration is None:
                    problems.append(located(unit, dict(where, code='binding-orphan',
                                                       key=value.value, method=info['method'])))
                elif declaration['kind'] != info['kind']:
                    problems.append(located(unit, dict(where, code='binding-kind',
                                                       key=value.value, method=info['method'],
                                                       declaredKind=declaration['kind'])))
                else:
                    candidates[value.value].append((node, unit.flow, unit, located(unit, dict(
                        where, site='map-value', code=code, map=candidate['map'].node.value,
                        dispatcher=chain['dispatcher'])), wrapper))
    roots = {key: [(root, flow) for root, flow, unit, row, wrapper in rows
                   if wrapper is None or wrapper_proved(wrapper, unit)]
             for key, rows in candidates.items()}
    proofs = linker.prove(roots)
    for unit, node, chain in chains:
        for key in declarations:
            outputs = proofs[key].get(id(node))
            if outputs and any(root is node and row[1]['site'] == 'map-value'
                               for root, _, _, row, _ in candidates[key]):
                chain['boundKeys'].append(key)
                chain['outputs'] = outputs
        chain['established'] = bool(chain['boundKeys'])
    for unit in units:
        if unit.error is not None:
            row = {'code': 'binding-unparsed', 'path': unit.path}
            row.update({('detail' if field == 'code' else field): value
                        for field, value in unit.error.items()})
            problems.append(((unit.order, 0, 0), row))
    families = {}
    for family in context['windowFamilies']:
        for key in family['adoptedKeys']:
            families.setdefault(key, []).append({
                'name': family['name'], 'semanticStatus': family['semanticStatus'],
                'coverageStatus': family['coverageStatus']})
    surfaces = {row['key']: row.get('familySurface') for row in context['keys']
                if type(row) is dict}
    rows, unbound, positions, proven_rows = [], [], set(), {}
    for key in declarations:
        proven, unproven = [], []
        for root, flow, unit, (order, row), wrapper in candidates[key]:
            outputs = proofs[key].get(id(root))
            if outputs:
                proven.append((order, dict(row, outputs=outputs)))
            else:
                reason = ('wrapper-result-not-returned' if wrapper is not None
                          and not wrapper_proved(wrapper, unit) else 'output-not-reached')
                unproven.append((order, dict(row, reason=reason)))
            positions.add((row['path'], row['line'], row['column']))
        proven_rows[key] = ([row for _, row in sorted(proven, key=lambda item: item[0])],
                            [row for _, row in sorted(unproven, key=lambda item: item[0])])
    leads = {key: {} for key in declarations}
    for unit in units:
        for value, line, column in unit.leads:
            if value in leads and (unit.path, line, column) not in positions:
                leads[value][unit.path] = leads[value].get(unit.path, 0) + 1
    for key, declaration in declarations.items():
        sites, unproven = proven_rows[key]
        kinds = {row['site'] for row in sites}
        binding = (_DIRECT if kinds & {'direct-call', 'wrapper-call'}
                   else _MAPPED if kinds else _UNBOUND)
        if binding == _UNBOUND:
            unbound.append({'code': 'binding-unbound', 'path': None, 'key': key,
                            'detail': 'no static consumer of this declared key reaches an output'})
        declared = families.get(key, [])
        rows.append({'key': key, 'kind': declaration['kind'], 'binding': binding,
                     'sites': sites, 'unprovenSites': unproven,
                     'excludedLiteralLeads': {'count': sum(leads[key].values()),
                                              'byPath': leads[key]},
                     'family': {'state': 'DECLARED' if declared else 'UNCLASSIFIED',
                                'families': declared, 'familySurface': surfaces.get(key)}})
    problems = [row for _, row in sorted(problems, key=lambda item: item[0])] + unbound
    return {
        'schema': CONSUMER_SCHEMA,
        'schemaVersion': CONSUMER_SCHEMA_VERSION,
        'tool': _TOOL_PATH,
        'status': STATUS,
        'scope': CONSUMER_SCOPE,
        'mode': _CONSUMER_MODE,
        'inputs': _input_rows(_REGISTRY_INPUTS, registry),
        'hashBasis': _HASH_BASIS,
        'tocs': [{'path': path, 'sha256': hashlib.sha256(data).hexdigest(),
                  'byteLength': len(data),
                  'loaded': [entry for entry, (toc, _, _) in listed.items() if toc == path]}
                 for path, data in tocs],
        'sources': [{'path': unit.path, 'toc': listed[unit.path][0],
                     'tocLine': listed[unit.path][1],
                     'sha256': hashlib.sha256(unit.data).hexdigest(),
                     'byteLength': len(unit.data),
                     'role': ('provider' if unit.path == _AUTHORITY else 'catalog-data'
                              if unit.path in (_ENGLISH_SOURCE, _PACKS_SOURCE) else 'scanned'),
                     'analysis': 'UNPARSED' if unit.error else 'PARSED'} for unit in units],
        'valid': not problems,
        'counts': {
            'keys': len(rows),
            _DIRECT: sum(1 for row in rows if row['binding'] == _DIRECT),
            _MAPPED: sum(1 for row in rows if row['binding'] == _MAPPED),
            _UNBOUND: len(unbound),
            'sites': sum(len(row['sites']) for row in rows),
            'unprovenSites': sum(len(row['unprovenSites']) for row in rows),
            'problems': len(problems),
            'dynamicUnknown': len(dynamic),
            'shadowedMapEntries': len(shadowed)},
        'keys': rows,
        'mapChains': [chain for _, _, chain in chains],
        'shadowedMapEntries': [row for _, row in sorted(shadowed, key=lambda item: item[0])],
        'dynamicUnknown': [row for _, row in sorted(dynamic, key=lambda item: item[0])],
        'problems': problems,
        'bindingRule': _BINDING_RULE,
        'outputRule': _OUTPUT_RULE,
        'familyRule': _FAMILY_RULE,
        'limits': list(_CONSUMER_LIMITS),
        'completeness': {'established': False, 'rule': _CONSUMER_COMPLETENESS},
        'nonexecution': 'sources are tokenized and parsed from the supplied bytes; no Lua is '
                        'executed',
    }


def _cli_consumers(root, data, localization, toc, require_complete):
    """Read both TOCs and every Lua file they load from the confined root,
    write one consumers record on stdout and return its exit status: 2
    while the receipt is not valid, else 1 with --require-complete (never
    established) or 0."""
    read = {_ENGLISH_SOURCE: data[0], _PACKS_SOURCE: data[1], _AUTHORITY: localization,
            _MAIN_TOC: data[-1]}
    tocs, sources, seen = [], [], set()
    for toc_path in _CONSUMER_TOCS:
        if toc_path not in read:
            read[toc_path] = _cli_read(root, toc_path)
        tocs.append(toc_path)
    for toc_path in tocs:
        for path, _ in _toc_entries(toc_path, read[toc_path]):
            if path in seen:
                continue
            seen.add(path)
            if path not in read:
                read[path] = _cli_read(root, path)
            sources.append(path)

    def records(paths):
        return [{'path': path, 'sha256': hashlib.sha256(read[path]).hexdigest(),
                 'byteLength': len(read[path]), 'data': read[path]} for path in paths]
    receipt = consumer_binding_report(data[0], data[1], data[2], data[3], localization,
                                      records(tocs), records(sources))
    if not receipt['valid']:
        exit_code = _EXIT_ERROR
    else:
        exit_code = _EXIT_NOT_ESTABLISHED if require_complete else _EXIT_REPORT
    _cli_emit(sys.stdout, {
        'schema': CLI_SCHEMA,
        'schemaVersion': CLI_SCHEMA_VERSION,
        'record': 'consumers',
        'tool': _TOOL_PATH,
        'status': STATUS,
        'requireComplete': 'requested' if require_complete else 'not_requested',
        'registryBinding': 'requested',
        'exitCode': exit_code,
        'inputBinding': _CONSUMER_INPUT_BINDING,
        'toc': toc,
        'consumers': receipt,
    })
    return exit_code


if __name__ == '__main__':
    raise SystemExit(main())
