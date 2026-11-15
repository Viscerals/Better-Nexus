#!/usr/bin/env python3
"""Syntax foundation, pure schema API, pure coverage report API and read-only
report command line for the Nexus localization data (#147).

Status: IMPLEMENTED_DRAFT_REVIEW_PENDING. parse_english and parse_packs
below check syntax only, and a successful parse alone does not make a catalog
valid. validate_catalog_data, appended after them, is a pure in-memory schema
API: from the exact bytes of the English base, the packs file, KEY_CONTEXT.json
and RELEASE_LANGUAGES.json it checks keys, text, blocks, the template grammar,
pack IDs, autonyms and entries, the key-context rows and the release product
metadata against the runtime contract of core/Localization.lua (text, block,
format and template kinds within its 5120-entry cap), and raises
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
IMPLEMENTED_DRAFT denotes a scoped draft for the text, block and template
keys of the key-context rows and the single code-owned charge-count format,
not whole #147;
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
    'validationScope': 'Scoped draft for the text, block and template keys of the key-context rows and the single code-owned charge-count format, within the runtime entry cap; not whole #147. Plural variants, dynamic-key coverage per family, runtime load/fallback parity, per-pack translator provenance/rights and approved terminology validation are not implemented by this component.',
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


def _snapshot(value, name='source'):
    """The one immutable snapshot of an accepted input (bytes or bytearray,
    subclasses included), else TypeError. A subclass is read once through its
    buffer, never through an overridable conversion such as __bytes__, and
    every later hash, decode, memo key and report of the call uses this
    snapshot only, so no stage can observe other bytes than another."""
    if not isinstance(value, (bytes, bytearray)):
        raise TypeError('%s must be bytes, not %s' % (name, type(value).__name__))
    return value if type(value) is bytes else bytes(memoryview(value))


_FOUR_INPUTS = ('english_source', 'packs_source', 'key_context_json', 'release_json')
_FIVE_INPUTS = _FOUR_INPUTS + ('localization_source',)


def _snapshots(names, values):
    """The snapshot of each named input, in order (TypeError names the first
    that is not bytes or bytearray)."""
    return tuple(_snapshot(value, name) for name, value in zip(names, values))


def _parse(source, target, table):
    source = _snapshot(source)

    def parse(data):
        try:
            text = bytes(data).decode('utf-8')
        except UnicodeDecodeError:
            raise CatalogSyntaxError('not-utf8') from None
        parser = _Parser(_tokens(text))
        return parser.chunk(target, getattr(parser, table))
    return _memoized(target, source, parse)


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
# Full visible-UI scope (Refs #143-#148): the input memo. Every seam below
# parses all of its inputs, and the registry-bound, diagnostic, provenance
# and consumer receipts each also run the strict verdict, so the same exact
# bytes of the 4078-key catalog were lexed and decoded many times per run.
# _memoized keeps a successful parse of the exact bytes of one input, keyed by
# the parser and the SHA-256 of those bytes: any changed byte is a new key and
# is parsed afresh, so nothing is served for other bytes. A failure is never
# kept: the same bytes raise the same error again. A hit returns new objects
# (a marshal copy of the kept result: dicts in their order, lists, tuples,
# strings, numbers, booleans and None only), so a caller that changes a
# returned value cannot change a later result. At most _INPUT_MEMO_LIMIT
# results are kept, the least recently used leaving first. Results never
# depend on the memo.

import functools
import gc
import hashlib
import marshal
import re

_INPUT_MEMO = {}
_INPUT_MEMO_LIMIT = 32
# A lone UTF-16 surrogate code point (the JSON check json-surrogate).
_SURROGATE = re.compile('[\ud800-\udfff]')
# A JSON escape of a code point in that range, in either letter case (or a
# false match such as an escaped backslash before "ud800", which only costs
# the full check).
_SURROGATE_ESCAPE = re.compile(r'\\u[dD][89a-fA-F]')


_DIGESTS = {}
_DIGESTS_LIMIT = 1024
_DIGESTS_BYTES = 64 * 1024 * 1024


def _digest(data):
    """The SHA-256 digest of exact bytes, cached by their value (a dict key
    compares the bytes themselves, never an object identity), least recently
    used out first within _DIGESTS_LIMIT entries and _DIGESTS_BYTES bytes. An
    input larger than _DIGESTS_BYTES alone is hashed and never kept, and
    evicts nothing (STD-V15-3)."""
    digest = _DIGESTS.pop(data, None)
    if digest is None:
        digest = hashlib.sha256(data).digest()
        if len(data) > _DIGESTS_BYTES:
            return digest
        while _DIGESTS and (len(_DIGESTS) >= _DIGESTS_LIMIT
                            or sum(map(len, _DIGESTS)) + len(data) > _DIGESTS_BYTES):
            del _DIGESTS[next(iter(_DIGESTS))]
    _DIGESTS[data] = digest
    return digest


def _memoized(kind, source, parse):
    """parse(source), or a copy of its kept result for the same kind and the
    exact same bytes (see above). source is one byte string, or a tuple of
    them for a result of several inputs (each hashed apart, in order). Each
    is snapshotted (_snapshot) once, and that same snapshot is both hashed for
    the key and handed to parse."""
    if type(source) is tuple:
        source = tuple(_snapshot(data) for data in source)
        sources = source
    else:
        source = _snapshot(source)
        sources = (source,)
    key = (kind,) + tuple(_digest(data) for data in sources)
    kept = _INPUT_MEMO.pop(key, None)
    if kept is not None:
        _INPUT_MEMO[key] = kept
        return marshal.loads(kept)
    result = parse(source)
    while len(_INPUT_MEMO) >= _INPUT_MEMO_LIMIT:
        del _INPUT_MEMO[next(iter(_INPUT_MEMO))]
    _INPUT_MEMO[key] = marshal.dumps(result)
    return result


def _collector_paused(seam):
    """seam with the cyclic collector paused for the whole call and always
    restored as it was: the rule _parsed applies to one syntax-tree build
    (S8 review fix 4), applied to a seam call. A call holds large acyclic
    copies of its inputs (and a consumer receipt its search state) while it
    runs; a collection meanwhile would promote them and then rescan every
    memoized syntax tree. Reference counting still frees memory, and no
    result depends on the collector.

    Ownership boundary: the collector switch is interpreter-wide, so this is
    correct for serial use only, one seam call (and its nested seam calls)
    at a time in a process, as the command line and the registered tests
    use it. Each call restores exactly the state it found, nested calls
    included and on error. Overlapping calls from several threads, or
    another component switching the collector during a call, are not
    supported: an outer call may then re-enable collection while another is
    still running. The input and parse memos are module state with the same
    serial boundary."""
    @functools.wraps(seam)
    def call(*args, **kwargs):
        collecting = gc.isenabled()
        gc.disable()
        try:
            return seam(*args, **kwargs)
        finally:
            if collecting:
                gc.enable()
    return call


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
# Full visible-UI scope (issues #143-#148): the runtime's MAX_BASE_ENTRIES
# bounds the declarations, the English base and each pack. It was 64 for the
# pilot cohort, then 4096; the runtime now declares 5120 and fails closed
# above it, and so does every API here (english-too-many, registry-too-many,
# pack-too-many-entries).
_MAX_BASE_ENTRIES = 5120
_MAX_BLOCK_BYTES = 1024
_MAX_TEMPLATE_RESULT_BYTES = 2048
_MAX_NAME_BYTES = 64
_MAX_LANGUAGES = 16
_ASCII_WHITESPACE = (9, 10, 11, 12, 13, 32)
# The byte rules of _valid_text and _valid_key as patterns (one pass each in
# C; the rules themselves are the docstrings'): only ASCII whitespace bytes,
# a refused text byte (0-31, 127, |), a refused block byte (the same but the
# line feed), and the whole key shape.
_BLANK_BYTES = re.compile(rb'[\t\n\x0b\x0c\r ]*')
_TEXT_FORBIDDEN = re.compile(rb'[\x00-\x1f\x7f|]')
_BLOCK_FORBIDDEN = re.compile(rb'[\x00-\x09\x0b-\x1f\x7f|]')
_KEY_SHAPE = re.compile('[a-z][a-z0-9_]*(?:[.][a-z][a-z0-9_]*)+')
_SLOT_TYPE = 'count'
_TEMPLATE_SLOTS = ('count', 'text')
_KINDS = ('text', 'block', 'format', 'template')
# The contract of one key that is not static text: its kind, its placeholder
# fields and their slot types in order, its result limit (None for a block)
# and whether the block contract applies to its own bytes (lines). A static
# text key has no shape.
_Shape = namedtuple('_Shape', 'kind fields slots limit lines')
_BLOCK = _Shape('block', (), (), None, True)
_FORMAT_FIELDS = types.MappingProxyType({'readout.charge_counts': ('banish', 'reroll', 'freeze')})
_FORMAT_LIMITS = types.MappingProxyType({'readout.charge_counts': _MAX_TEXT_BYTES - 2})
# The four-input API's fixed, code-owned format shapes. The four-input API
# adds the block and template shapes of the key-context rows to them
# (_context_shapes); the registry-bound API (end of this file) passes the
# shapes of the parsed declarations instead and never reads these constants.
_V1_FORMATS = types.MappingProxyType({
    key: _Shape('format', fields, (_SLOT_TYPE,) * len(fields), _FORMAT_LIMITS[key], False)
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
    return _SURROGATE.search(text) is not None


def _strict_json(source, where):
    """Decode one JSON object from strict UTF-8 bytes, without any repair.
    A successful decode is kept in the input memo (_memoized)."""
    return _memoized('json', source, lambda data: _decode_json(data, where))


def _decode_json(source, where):
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
    if _SURROGATE_ESCAPE.search(text) is None:
        # Strict UTF-8 text holds no surrogate, so a decoded one can only come
        # from a \uD800-\uDFFF escape; without one the walk below finds none.
        return document
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
    return _KEY_SHAPE.fullmatch(key) is not None


def _valid_text(text, limit=_MAX_TEXT_BYTES, line_feed=False):
    """The runtime text contract on the exact UTF-8 bytes: 1 to limit bytes, a
    byte outside ASCII whitespace, no byte 0-31, 127 or |. With line_feed
    (the block contract) the line feed, byte 10, is the one control byte
    allowed. Other Unicode scalars are allowed and nothing is normalized."""
    if type(text) is not str:
        return False
    try:
        data = text.encode('utf-8')
    except UnicodeEncodeError:
        return False
    if not 1 <= len(data) <= limit:
        return False
    if _BLANK_BYTES.fullmatch(data) is not None:
        return False
    return (_BLOCK_FORBIDDEN if line_feed else _TEXT_FORBIDDEN).search(data) is None


def _valid_block(text):
    """The runtime block contract (ValidBlock): the text contract with at most
    _MAX_BLOCK_BYTES bytes and the line feed allowed; carriage return, every
    other control byte and | stay refused."""
    return _valid_text(text, _MAX_BLOCK_BYTES, line_feed=True)


def _valid_template(text, fields, lines=False):
    """The text contract (the block contract with lines) plus the named
    template grammar: each field as {name} exactly once in any order, {{ and
    }} literal braces, every other character (% included) literal. Nothing
    is rendered or substituted."""
    if not (_valid_block(text) if lines else _valid_text(text)):
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


def _check_value(text, key, path, shapes=_V1_FORMATS):
    """One English or pack value under its key's shape: static text (no
    shape) and a block are invalid-text, a format or template that does not
    compile under its fields is invalid-template."""
    shape = shapes.get(key)
    if shape is None:
        _require(_valid_text(text), 'invalid-text', path, key)
    elif shape.kind == 'block':
        _require(_valid_block(text), 'invalid-text', path, key)
    else:
        _require(_valid_template(text, shape.fields, shape.lines), 'invalid-template', path, key)


def _slots_match(placeholders, fields):
    names = []
    for slot in placeholders:
        if type(slot) is not dict or set(slot) != {'name', 'type'}:
            return False
        if type(slot['name']) is not str or slot['type'] != _SLOT_TYPE:
            return False
        names.append(slot['name'])
    return len(names) == len(fields) and set(names) == set(fields)


def _valid_field(name):
    """A placeholder field name as the runtime admits it: a lower-case word
    of at most _MAX_KEY_BYTES bytes."""
    return (type(name) is str and len(name) <= _MAX_KEY_BYTES
            and _FIELD_NAME.fullmatch(name) is not None)


def _template_slots(placeholders):
    """(fields, slots) of complete typed template placeholders, or None: a
    nonempty list of objects with exactly name, type and meaning, each name a
    distinct field name, each type a template slot type and each meaning a
    nonblank string, in placeholder order."""
    if type(placeholders) is not list or not placeholders:
        return None
    fields, slots = [], []
    for slot in placeholders:
        if type(slot) is not dict or set(slot) != {'name', 'type', 'meaning'}:
            return None
        name, kind, meaning = slot['name'], slot['type'], slot['meaning']
        if not _valid_field(name) or name in fields or type(kind) is not str \
                or kind not in _TEMPLATE_SLOTS or type(meaning) is not str or not meaning.strip():
            return None
        fields.append(name)
        slots.append(kind)
    return tuple(fields), tuple(slots)


def _row_template_shape(row, path, key):
    """The template shape a key-context row of kind template declares,
    checked in full: complete typed placeholders, a whole resultLimitBytes
    from 1 to _MAX_TEMPLATE_RESULT_BYTES and lines absent or exactly true."""
    found = _template_slots(row.get('placeholders'))
    _require(found is not None, 'context-placeholders', path + '.placeholders', key)
    limit = row.get('resultLimitBytes')
    _require(type(limit) is int and 1 <= limit <= _MAX_TEMPLATE_RESULT_BYTES,
             'context-result-limit', path + '.resultLimitBytes', key)
    _require('lines' not in row or row['lines'] is True, 'context-kind', path + '.lines', key)
    return _Shape('template', found[0], found[1], limit, 'lines' in row)


def _context_shapes(document, formats=_V1_FORMATS):
    """The shapes the four-input API applies: the code-owned formats, plus the
    block and template shape each key-context row of kind block or template
    declares, checked in full here (the four-input API has no declarations;
    the registry-bound API takes them from the declarations instead and
    requires each row to equal its declaration). A row for a code-owned
    format key never redefines it, and malformed containers or rows are left
    to _check_context."""
    rows = document.get('keys')
    shapes = dict(formats)
    for index, row in enumerate(rows if type(rows) is list else ()):
        key = row.get('key') if type(row) is dict else None
        if not _valid_key(key) or key in formats or key in shapes:
            continue
        path = 'keyContext.keys[%d]' % index
        if row.get('kind') == 'block':
            shapes[key] = _BLOCK
        elif row.get('kind') == 'template':
            shapes[key] = _row_template_shape(row, path, key)
    return types.MappingProxyType(shapes)


def _context_keys(document):
    """The keys of the key-context rows (malformed rows are left to
    _check_context)."""
    rows = document.get('keys')
    return frozenset(row['key'] for row in (rows if type(rows) is list else ())
                     if type(row) is dict and type(row.get('key')) is str)


def _check_english(english, shapes=_V1_FORMATS, known=None):
    """The English base: within the runtime cap, valid keys and each value
    under its key's shape. When known is given (the keys whose kind a
    key-context row or declaration states), the value of any other key is
    not judged here: such a key has no kind, and the key-set check that
    follows (context-key-mismatch or undeclared-entry) always refuses it."""
    _require(len(english) > 0, 'english-empty', 'english')
    _require(len(english) <= _MAX_BASE_ENTRIES, 'english-too-many', 'english')
    for key, text in english.items():
        _require(_valid_key(key), 'invalid-key', 'english', key)
        if known is None or key in known:
            _check_value(text, key, 'english', shapes)


def _check_context(document, english, shapes=_V1_FORMATS):
    """The key-context document: header, containers, the limits this stage
    uses, and one row per English key whose kind, English text, meaning,
    placeholders, result limit and lines flag agree with the source and the
    governing shapes (runtime schema)."""
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
        shape = shapes.get(key)
        _require(row.get('kind') == ('text' if shape is None else shape.kind),
                 'context-kind', path + '.kind', key)
        _require(type(row.get('english')) is str and row['english'] == english[key],
                 'context-english-mismatch', path + '.english', key)
        meaning = row.get('meaning')
        _require(type(meaning) is str and meaning.strip() != '', 'context-meaning',
                 path + '.meaning', key)
        placeholders = row.get('placeholders')
        _require(type(placeholders) is list, 'context-structure', path + '.placeholders', key)
        if shape is None or shape.kind == 'block':
            _require(placeholders == [], 'context-placeholders', path + '.placeholders', key)
            _require('resultLimitBytes' not in row, 'context-result-limit',
                     path + '.resultLimitBytes', key)
            _require('lines' not in row, 'context-kind', path + '.lines', key)
        elif shape.kind == 'format':
            _require(_slots_match(placeholders, shape.fields), 'context-placeholders',
                     path + '.placeholders', key)
            _require(_is_int(row.get('resultLimitBytes'), shape.limit),
                     'context-result-limit', path + '.resultLimitBytes', key)
            _require('lines' not in row, 'context-kind', path + '.lines', key)
        else:
            _require(_template_slots(placeholders) == (shape.fields, shape.slots),
                     'context-placeholders', path + '.placeholders', key)
            _require(_is_int(row.get('resultLimitBytes'), shape.limit),
                     'context-result-limit', path + '.resultLimitBytes', key)
            _require(('lines' in row) == shape.lines
                     and ('lines' not in row or row['lines'] is True),
                     'context-kind', path + '.lines', key)


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


def _check_entry(key, text, english, path, shapes):
    """One pack entry: a valid key of the English base with a valid value
    under that key's shape."""
    _require(_valid_key(key), 'invalid-key', path, key)
    _require(key in english, 'orphan-entry', path, key)
    _check_value(text, key, path, shapes)


def _check_pack_autonym(pack_id, pack, products):
    product_path, product = products[pack_id]
    _require(product['autonym'] == pack['name'], 'release-autonym', product_path + '.autonym',
             pack_id)


def _check_packs(packs, english, products, shapes=_V1_FORMATS):
    """The packs: within the runtime pack limit, no English pack, exactly the
    selected optional products, each autonym and entry inside the contract
    and each autonym equal to the release metadata. A missing entry is valid
    partial data and is not replaced by English."""
    _check_pack_set(packs, products)
    for pack_id, pack in packs.items():
        path = _check_pack_shape(pack_id, pack)
        for key, text in pack['entries'].items():
            _check_entry(key, text, english, path, shapes)
        _check_pack_autonym(pack_id, pack, products)


@_collector_paused
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
    surrogate. A semantic failure raises CatalogValidationError. Without a
    declaration input, the kind of each key is the code-owned charge format
    or the block or template its key-context row declares (_context_shapes),
    else static text. Missing translated entries are valid partial data;
    nothing is rendered, and this is not a coverage, review or evidence
    check."""
    sources = _snapshots(_FOUR_INPUTS, (english_source, packs_source, key_context_json,
                                        release_json))
    return _memoized('catalog', sources, lambda sources: _validate_catalog(*sources))


def _validate_catalog(english_source, packs_source, key_context_json, release_json):
    english = parse_english(english_source)
    packs = parse_packs(packs_source)
    key_context = _strict_json(key_context_json, 'keyContext')
    release = _strict_json(release_json, 'release')
    shapes = _context_shapes(key_context)
    _core_checks('catalog-core', (english_source, key_context_json), lambda: (
        _check_english(english, shapes, _context_keys(key_context) | set(shapes)),
        _check_context(key_context, english, shapes)))
    products = _check_release(release)
    _check_packs(packs, english, products, shapes)
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


@_collector_paused
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
    sources = _snapshots(_FOUR_INPUTS, (english_source, packs_source, key_context_json,
                                        release_json))
    # The whole report is a function of the exact bytes of the four inputs,
    # so a report of the same bytes is kept in the input memo (_memoized: a
    # new copy per call, an invalid input never kept and refused again).
    return _memoized('report', sources, lambda sources: _coverage_report(
        validate_catalog_data(*sources), sources, _REPORT_INPUTS, REPORT_SCHEMA_VERSION,
        NOTICE['validationScope']))


def _input_rows(input_names, sources):
    """One row per (name, source) of input_names with the SHA-256 and length
    of its exact bytes in sources."""
    return [{'name': name, 'source': source, 'sha256': _digest(bytes(data)).hex(),
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
    source = _snapshot(source)
    try:
        text = source.decode('utf-8')
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
# repeated key is duplicate-key. Each declaration must be one the runtime
# admits (FormatSchema, TemplateSchema): exactly {kind = "text"}, exactly
# {kind = "block"}, exactly {kind = "format", fields = {"name", ...},
# slot = "count", resultLimit = 254} (the runtime's MAX_TEXT_BYTES - 2), or
# exactly {kind = "template", fields = {"name", ...}, slots = {"count" or
# "text", ...}, resultLimit = N} with optionally lines = true: one or more
# distinct lower-case field names, a slot type per field and N a whole number
# from 1 to MAX_TEMPLATE_RESULT_BYTES (2048). At most MAX_BASE_ENTRIES (5120)
# declarations. Any other declaration, key or count is a CatalogRegistryError
# (REGISTRY_CODES). The runtime leaves such a declaration out at load (or,
# above the cap, every declaration); offline it fails.
#
# validate_registry_catalog_data and registry_catalog_report are the
# five-input registry-bound API and report schemaVersion 2. They take the
# exact bytes of the four catalog inputs plus core/Localization.lua, and the
# shapes of the parsed declarations, never _FORMAT_FIELDS, _FORMAT_LIMITS or
# the key-context rows, govern the English, pack and key-context checks. They
# add: every English key is declared (undeclared-entry), every declared key
# has English (english-incomplete), and each key-context row's kind,
# placeholder names in order with their type, result limit and lines flag
# equal its declaration (context-declaration-mismatch).
# validate_catalog_data and catalog_report above keep four inputs, report
# schemaVersion 1 and their scoped label; they are not registry validation.
# Nothing here reads a file: main() passes the sixth fixed input only when
# --registry is given.

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
    'for the currently declared text, block, format and template keys within the runtime '
    'entry cap; not whole #147. Plural variants, dynamic-key coverage per family, runtime '
    'load/fallback parity, per-pack translator provenance/rights and approved terminology '
    'validation are not implemented by this component.')
_REGISTRY_TOKEN = 'NEXUS-L10N-REGISTRY'
_REGISTRY_OPEN = '-- NEXUS-L10N-REGISTRY BEGIN'
_REGISTRY_CLOSE = '-- NEXUS-L10N-REGISTRY END'
_REGISTRY_TABLE = 'DECLARATIONS'
_TEXT_DECLARATION = frozenset(('kind',))
_FORMAT_DECLARATION = frozenset(('kind', 'fields', 'slot', 'resultLimit'))
_TEMPLATE_DECLARATION = frozenset(('kind', 'fields', 'slots', 'resultLimit'))
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
    """One checked declaration as {'kind': 'text'}, {'kind': 'block'},
    {'kind': 'format', 'fields': (names...), 'slot': 'count', 'resultLimit':
    254} or {'kind': 'template', 'fields': (names...), 'slots': (types...),
    'resultLimit': N}, the last with 'lines': True when declared."""
    path = '%s[%r]' % (_REGISTRY_TABLE, key)
    _registry(_valid_key(key), 'registry-key', path, key)
    _registry(type(value) is dict and value, 'registry-structure', path, key)
    kind = value.get('kind')
    _registry(type(kind) is str and kind in _KINDS, 'registry-kind', path + '.kind', key)
    if kind in ('text', 'block'):
        _registry(set(value) == _TEXT_DECLARATION, 'registry-field', path, key)
        return {'kind': kind}
    if kind == 'format':
        _registry(set(value) == _FORMAT_DECLARATION, 'registry-field', path, key)
    else:
        _registry(set(value) - {'lines'} == _TEMPLATE_DECLARATION
                  and value.get('lines', True) is True, 'registry-field', path, key)
    fields = value['fields']
    _registry(type(fields) is list and fields and len(set(map(repr, fields))) == len(fields)
              and all(_valid_field(name) for name in fields),
              'registry-placeholders', path + '.fields', key)
    if kind == 'format':
        _registry(value['slot'] == _SLOT_TYPE, 'registry-slot', path + '.slot', key)
        _registry(_is_int(value['resultLimit'], _MAX_TEXT_BYTES - 2), 'registry-limit',
                  path + '.resultLimit', key)
        return {'kind': 'format', 'fields': tuple(fields), 'slot': _SLOT_TYPE,
                'resultLimit': value['resultLimit']}
    slots, limit = value['slots'], value['resultLimit']
    _registry(type(slots) is list and len(slots) == len(fields)
              and all(type(slot) is str and slot in _TEMPLATE_SLOTS for slot in slots),
              'registry-slot', path + '.slots', key)
    _registry(type(limit) is int and 1 <= limit <= _MAX_TEMPLATE_RESULT_BYTES,
              'registry-limit', path + '.resultLimit', key)
    declaration = {'kind': 'template', 'fields': tuple(fields), 'slots': tuple(slots),
                   'resultLimit': limit}
    if 'lines' in value:
        declaration['lines'] = True
    return declaration


def parse_registry_declarations(source: bytes) -> dict:
    """Parse the declaration block of the exact bytes of core/Localization.lua
    into {key: declaration} in source order (grammar above). The source is
    never evaluated, imported or executed. A syntax failure raises
    CatalogSyntaxError (CODES); a marker or declaration failure raises
    CatalogRegistryError (REGISTRY_CODES)."""
    return _memoized('declarations', _snapshot(source), _parse_declarations)


def _parse_declarations(source):
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


def _declared_shapes(declarations):
    """The shape of each declared key that is not static text."""
    shapes = {}
    for key, value in declarations.items():
        if value['kind'] == 'block':
            shapes[key] = _BLOCK
        elif value['kind'] == 'format':
            shapes[key] = _Shape('format', value['fields'],
                                 (value['slot'],) * len(value['fields']),
                                 value['resultLimit'], False)
        elif value['kind'] == 'template':
            shapes[key] = _Shape('template', value['fields'], value['slots'],
                                 value['resultLimit'], value.get('lines', False))
    return types.MappingProxyType(shapes)


def _context_shape(declaration):
    """The key-context kind, placeholder names and slot types in order,
    result limit and lines flag a declaration requires (None: no
    resultLimitBytes member; False: no lines member)."""
    kind = declaration['kind']
    if kind in ('text', 'block'):
        return kind, [], None, False
    fields = declaration['fields']
    slots = declaration['slots'] if kind == 'template' else (declaration['slot'],) * len(fields)
    return (kind, [{'name': name, 'type': slot} for name, slot in zip(fields, slots)],
            declaration['resultLimit'], declaration.get('lines', False))


def _check_registry(declarations, english, context):
    """Complete English against the declarations, then each key-context row
    of a declared key against its declaration. A template row's placeholders
    are compared by name and type in order (each also carries its meaning,
    which _check_context requires); rows of other shapes are left to
    _check_context."""
    for key in english:
        _registry(key in declarations, 'undeclared-entry', 'english', key)
    for key in declarations:
        _registry(key in english, 'english-incomplete', _REGISTRY_TABLE, key)
    rows = context.get('keys')
    for index, row in enumerate(rows if type(rows) is list else ()):
        key = row.get('key') if type(row) is dict else None
        if type(key) is not str or key not in declarations:
            continue
        kind, placeholders, limit, lines = _context_shape(declarations[key])
        found = row.get('placeholders')
        if kind == 'template' and type(found) is list:
            found = [{'name': slot.get('name'), 'type': slot.get('type')}
                     if type(slot) is dict else slot for slot in found]
        limit_found = row.get('resultLimitBytes')
        limit_ok = ('resultLimitBytes' not in row) if limit is None else _is_int(limit_found, limit)
        lines_ok = row.get('lines') is True if lines else 'lines' not in row
        _registry(row.get('kind') == kind and found == placeholders and limit_ok and lines_ok,
                  'context-declaration-mismatch', 'keyContext.keys[%d]' % index, key)


@_collector_paused
def validate_registry_catalog_data(english_source: bytes, packs_source: bytes,
                                  key_context_json: bytes, release_json: bytes,
                                  localization_source: bytes) -> dict:
    """The registry-bound schema API: validate the exact bytes of the four
    catalog inputs of validate_catalog_data plus core/Localization.lua, with
    the parsed declarations governing (see above), and return a dict with
    english, packs, keyContext, release and declarations. Each argument must
    be bytes or bytearray, else TypeError. Failures raise CatalogSyntaxError,
    CatalogValidationError or CatalogRegistryError; nothing is executed."""
    sources = _snapshots(_FIVE_INPUTS, (english_source, packs_source, key_context_json,
                                        release_json, localization_source))
    return _memoized('registry', sources, lambda sources: _validate_registry(*sources))


def _core_checks(kind, sources, check):
    """Run check(), the release-independent part of a strict verdict, once
    per exact bytes of sources: a success is kept in the input memo
    (_memoized) and a failure, never kept, raises again on every call. The
    caller runs every earlier and later check itself, so the strict order of
    failures is unchanged."""
    _memoized(kind, sources, lambda _: (check(), True)[1])


def _registry_core(english_source, key_context_json, localization_source, english, key_context,
                   declarations, shapes):
    """The English, registry and key-context checks of the registry-bound
    verdict (see _core_checks)."""
    _core_checks('registry-core', (english_source, key_context_json, localization_source), lambda: (
        _check_english(english, shapes, declarations),
        _check_registry(declarations, english, key_context),
        _check_context(key_context, english, shapes)))


def _validate_registry(english_source, packs_source, key_context_json, release_json,
                       localization_source):
    english = parse_english(english_source)
    packs = parse_packs(packs_source)
    key_context = _strict_json(key_context_json, 'keyContext')
    release = _strict_json(release_json, 'release')
    declarations = parse_registry_declarations(localization_source)
    shapes = _declared_shapes(declarations)
    _registry_core(english_source, key_context_json, localization_source, english, key_context,
                   declarations, shapes)
    products = _check_release(release)
    _check_packs(packs, english, products, shapes)
    return {'english': english, 'packs': packs, 'keyContext': key_context, 'release': release,
            'declarations': declarations}


@_collector_paused
def registry_catalog_report(english_source: bytes, packs_source: bytes,
                            key_context_json: bytes, release_json: bytes,
                            localization_source: bytes) -> dict:
    """Report schemaVersion 2: validate_registry_catalog_data on the five
    inputs, then the catalog_report derivation with five input rows, the
    registry-bound validationScope and a registry section listing the
    declarations. An invalid input gets no report."""
    sources = _snapshots(_FIVE_INPUTS, (english_source, packs_source, key_context_json,
                                        release_json, localization_source))
    return _memoized('registry-report', sources, _registry_report)     # as catalog_report


def _registry_report(sources):
    """The uncached registry_catalog_report of the five snapshotted inputs."""
    validated = validate_registry_catalog_data(*sources)
    report = _coverage_report(validated, sources, _REGISTRY_INPUTS,
                              REGISTRY_REPORT_SCHEMA_VERSION, REGISTRY_SCOPE)
    report['registry'] = _registry_section(validated)
    return report


def _registry_section(validated):
    """The registry section of report schemaVersion 2."""
    rows = []
    for key, declaration in validated['declarations'].items():
        kind, placeholders, limit, lines = _context_shape(declaration)
        row = {'key': key, 'kind': kind}
        if limit is not None:
            row.update({'placeholders': placeholders, 'resultLimitBytes': limit})
        if lines:
            row['lines'] = True
        rows.append(row)
    return {
        'source': _AUTHORITY,
        'markers': {'open': _REGISTRY_OPEN, 'close': _REGISTRY_CLOSE},
        'declarationCount': len(rows),
        'englishKeys': len(validated['english']),
        'keyContextRows': len(validated['keyContext']['keys']),
        'declarations': rows,
        'rule': ('the declared keys, the English keys and the key-context rows are one set; '
                 'kind, placeholder names in order with their type, result limit and lines '
                 'come from the declarations'),
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
    the retired-key list. Returns (validated, retired keys, shapes)."""
    english_source, packs_source, key_context_json, release_json, localization_source = sources
    english = parse_english(english_source)
    packs = parse_packs(packs_source)
    key_context = _strict_json(key_context_json, 'keyContext')
    release = _strict_json(release_json, 'release')
    declarations = parse_registry_declarations(localization_source)
    shapes = _declared_shapes(declarations)
    _registry_core(english_source, key_context_json, localization_source, english, key_context,
                   declarations, shapes)
    products = _check_release(release)
    retired = _check_retired(key_context, declarations)
    _check_pack_set(packs, products)
    for pack_id, pack in packs.items():
        _check_pack_shape(pack_id, pack)
        _check_pack_autonym(pack_id, pack, products)
    validated = {'english': english, 'packs': packs, 'keyContext': key_context,
                 'release': release, 'declarations': declarations}
    return validated, retired, shapes


def _entry_code(key, text, english, path, shapes):
    """The strict code of one pack entry, or None when it is valid."""
    try:
        _check_entry(key, text, english, path, shapes)
    except CatalogValidationError as error:
        return error.code
    return None


def _entry_problems(validated, retired, shapes):
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
            code = _entry_code(key, entries[key], english, path, shapes)
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


@_collector_paused
def registry_catalog_diagnostics(english_source: bytes, packs_source: bytes,
                                 key_context_json: bytes, release_json: bytes,
                                 localization_source: bytes) -> dict:
    """The opt-in diagnostic receipt (see above) for the exact bytes of the
    five registry-bound inputs. Each argument must be bytes or bytearray,
    else TypeError; no catalog failure is raised. Nothing is read, written,
    executed or modified."""
    sources = (english_source, packs_source, key_context_json, release_json,
               localization_source)
    sources = _snapshots(_FIVE_INPUTS, sources)
    try:
        registry_catalog_report(*sources)
        strict = {'result': 'valid'}
    except _STRICT_FAILURES as error:
        strict = {'result': 'invalid', 'api': 'registry_catalog_report'}
        strict.update(_error_fields(error))
    retired, rows, coverage, boundary, stage = None, [], None, None, 'structure'
    try:
        validated, retired_keys, shapes = _trusted_catalog(sources)
        retired = retired_keys
        rows, problems = _entry_problems(validated, frozenset(retired_keys), shapes)
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


@_collector_paused
def pack_provenance_diagnostics(english_source: bytes, packs_source: bytes,
                                key_context_json: bytes, release_json: bytes,
                                localization_source: bytes) -> dict:
    """The opt-in provenance receipt (see above) for the exact bytes of the
    five registry-bound inputs. Each argument must be bytes or bytearray,
    else TypeError; no catalog or metadata failure is raised. Nothing is
    read, written, fetched, executed or modified."""
    sources = (english_source, packs_source, key_context_json, release_json,
               localization_source)
    sources = _snapshots(_FIVE_INPUTS, sources)
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
# again, or the call of a seam accessor (_seam_accessor): a local function
# that is never assigned again, takes no parameter and no ..., holds no nested
# function and whose every return gives exactly nil or that receiver (at
# least one of them the receiver), called without an argument; one level
# only, so an accessor is never read through another one or through itself,
# and a local declared with such a call is a receiver like a local alias. A
# function that can return anything else, takes a parameter or is assigned
# again names no receiver. Only Text, Resolve and Format are consumer
# methods, each bound to the
# declared kind class (text or block, text or block, format or template). A
# key is bound by:
#
# - direct-call: a consumer method called on a receiver with a literal key;
# - wrapper-call: a literal key passed to a local function whose parameter
#   goes unchanged into a consumer method call on a receiver, or to a local
#   function that hands its own parameter unchanged to such a wrapper as its
#   key (a forwarding wrapper: one level only, never a chain, the same
#   parameter and kind in every such call, nothing of it assigned again);
# - map-value: a value of a read-only local table of literal string pairs,
#   dispatched as wrapper(MAP[v], ...) by the sole return of
#   "if MAP[v] then ... end" in the body of an exported module function
#   (function T.Name, with Nexus.<Module> = T, defined once). Only an earlier
#   "if OTHER[v] then" guard over another such table may precede it; the
#   codes it holds shadow the map's entries. The guard of the dispatch itself
#   may also be "if GUARD[v] then" over a second read-only local table of
#   literal string pairs whose keys are exactly the map's keys
#   (_UnitScan.parallel_guard): every value of it is a string, so it passes
#   for exactly the map's codes. A missing or an extra key, a value that is
#   no literal string, a table that is assigned, passed or stored, or one
#   iterated by pairs while the loaded source assigns pairs, is unresolved.
#
# A site counts only when its localization result reaches an output (review
# fix 1): a may-flow path in _UnitFlow, from the call through parens, the
# text-carrying operands of and/or/.., bindings every definition of which
# carries the same proof, function returns into their resolved calls (each
# return position into the same result position only), field
# channels and parameters, ends at argument 1 of SetText, AddLine or
# AddMessage or an argument of print. A wrapper must return its own
# consumer-method result, and a forwarding wrapper the result of a wrapper
# that does. A discarded, overwritten or merely compared result,
# or one reaching only an unused helper or a stock widget outside the loaded
# source, is listed in unprovenSites and never counted. A module table is
# one identity with its local aliases (review fix 2): a field written through
# an alias is another definition, and a module table that escapes its file,
# is reassigned or is written through a computed key resolves no function.
# Review fix 2 adds identity: a field value reaches only a read of a table
# with the same object origin (a constructor, an unassigned local alias or a
# parameter it was passed to), a parameter value returns only to the call
# that passed it, and an output counts only on a client receiver, never on
# method spelling alone. Review fix 3 roots these proofs: a table written
# through a parameter is the one the value's own call passed; a receiver
# field counts only writes on the object it is read from; and a client
# receiver is proved from evidenced roots only (UIParent, GameTooltip or
# DEFAULT_CHAT_FRAME while never assigned, CreateFrame, and CreateFontString
# called on a proved client object), through locals, object-bound fields and
# parameters of fully resolved local functions. Review fix 4 keeps the same
# call context everywhere: a field read through a parameter (or a local alias
# of one) continues only under the call that passed the read table, so its
# function returns the value only there; a receiver field through a parameter
# is resolved on the table the value's own call passed; an output method that
# the loaded source may replace on the receiver (any write of that field on
# an object possibly the receiver, or on an untracked table) is no output;
# and only a nil given by a local's own declaration is neutral for a receiver.
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
# The consumer method class of each declared kind: the runtime answers a
# block exactly as static text (Text, Resolve) and a template exactly as a
# format (Format); the other method is wrong_key_kind or
# format_requires_arguments there, so it is binding-kind here.
_METHOD_KIND = types.MappingProxyType({'text': 'text', 'block': 'text', 'format': 'format',
                                       'template': 'format'})
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
                'rules of _UnitFlow, into argument 1 of SetText, AddLine or AddMessage on a client '
                'receiver proved from an evidenced client root, or an argument of a '
                'never-assigned print, keeping table identity and call-site correspondence; a '
                'site that does not is listed in unprovenSites and not counted. This is a static '
                'path, not proof that it runs or is displayed')
_FAMILY_RULE = ('binding and family classification are independent: DECLARED names the window '
                'families whose adoptedKeys hold the key, UNCLASSIFIED none; neither adopts a '
                'key or establishes family coverage')
_CONSUMER_COMPLETENESS = ('this receipt never establishes completeness: dynamic keys, branch '
                          'reachability, rendering and native display are outside it')
_CONSUMER_LIMITS = (
    'static syntax only: a bound site is not proved to run, to be reached or to be displayed',
    'a localization table passed to another function, stored in a global or a table field, '
    'reached through a computed name, or returned by a function other than the exact seam '
    'accessor shape described for this seam (a local function never assigned again, without '
    'parameters or a nested function, whose every return is nil or the seam itself, called '
    'without an argument, one level only) is not followed',
    'map dispatch is accepted only in the exact guarded shape described for this seam',
    'result flow is may-flow and flow-insensitive: field values follow table identity only '
    'through constructors, unassigned local aliases and local-function or pcall arguments in '
    'one file; values in globals, computed-key writes, method calls and calls deeper than '
    '8 frames are not followed; and an output outside the loaded source (such as the stock '
    'dropdown menu) or on a receiver not proved to be a client object is not an output',
    'a function result after the first is followed by its own position only: from that '
    'position of a return statement of a resolved local function, an established module '
    'function or its export, to the name that a local declaration or an assignment whose last '
    'expression is that call gives the position (only a local that its own function body alone '
    'reads and assigns), or on through a call that is the last expression of a return '
    'statement; at most 8 positions; a call that is not last or stands in parentheses gives '
    'its first value only; a later result of any other call (a consumer method, pcall, an '
    'unresolved or reassigned callee, ...), in a field, a global or a local a nested function '
    'uses, and a wrapper text returned after its first value are not followed',
    'a receiver field of a local that holds the result of a local helper is proved on the '
    'helper\'s object only for the exact singleton cache shape: a local function that is no '
    'method, takes no parameter and no ..., starts with "if CACHE then return CACHE end; local '
    'OBJECT = CreateFrame(...); CACHE = OBJECT" and ends with a return; CACHE is a local of the '
    'file chunk declared without a value (an initializer, nil included, is refused) and '
    'assigned nowhere else, so that the store is its only definition; every creator argument is a '
    'literal or a plain name (an index, an operator, a constructor, a call or a function is '
    'refused, since it could run loaded code before the store); OBJECT is never assigned '
    'again; every return gives exactly CACHE or OBJECT; and every use of the helper\'s name in '
    'the file is the callee of a call that is the one declared value of a local declared once '
    'and never assigned again, the helper never being assigned: any other use (an alias, a '
    'parenthesized, returned, passed, assigned or discarded call, pcall) refuses the helper as '
    'a whole. No name that holds the object may hand it on: CACHE, OBJECT and each such local '
    'are used only as the base of an index read, as the base of a field write with a literal '
    'key (a write with a computed key through any of them refuses the helper), as the '
    'receiver of a method call (unless the file gives one of these names a function for that '
    'field that can take an argument), as a value that is only tested or compared (the '
    'condition of an if, elseif, while or repeat, the operand of not, an operand of ==, ~=, <, '
    '<=, > or >=, or an and/or operand of an expression that is itself only tested or '
    'compared, through parentheses), and in the shape itself (the guard, the store, the '
    'helper\'s returns, and OBJECT as an argument of the creator); an operand of arithmetic, '
    '.. or ^, of unary minus or #, an and/or expression used as a value, and a holder, CACHE '
    'or OBJECT returned by another function, stored in a field, a table or a global, passed '
    'to a function or aliased by a local refuse the helper as a whole. Three things are '
    'assumed about the client and are not proved; the routes named are examples, not a '
    'complete list: that the creator, a client function no loaded source assigns, runs no '
    'loaded code itself (for example a frame template with load scripts, or a hook on the '
    'creator); that the client does not hand the object back to loaded code by another route '
    '(for example a script handler\'s self, the global name of a named frame, GetParent); and '
    'that the methods called on these names are the client\'s own, neither added to nor '
    'hooked on the method table that the widgets of a type share, by loaded code or by '
    'another addon. '
    'The model treats the result of any other helper as a separate object per local, so a '
    'field set through one result of an uncached factory proves nothing for another; and the '
    'flow of values through fields does not use this rule',
    'trusted globals (sinks, client roots, pairs, setmetatable and the string transforms) are '
    'trusted only while no loaded source assigns them, by name or through _G, writes the '
    'string library field used, or reaches the string metatable through a getmetatable result '
    'that leaves a test or comparison; _G as a value, a computed _G write or an environment '
    'function (getfenv, setfenv, debug other than debug.traceback, code loading) is a '
    'global-environment mutation problem, and so is a computed _G[k] read unless its key is '
    'proved to name no trusted global (static strings, read-only literal tables, loops over '
    'them, a distinguishing concatenation piece) or the global it reads is only tested, '
    'compared, typed, field-tested or called as a method no loaded source defines (a method '
    'an unknown object reaches through a metatable __index is not modelled)',
    'format follows only the arguments a static Lua 5.1 format shows with %s, and only when '
    'every conversion has a value proved present (a last call gives only the results proved '
    'for a seam key method or an unassigned local function, none for any other callee; a value '
    'cut to one, by position or parentheses, keeps what is known of it, or nil for a call path '
    'giving none, and a never-assigned local is followed to its declared value, at most 16 '
    'links, a longer chain giving an unproved value; any other '
    'local, parameter or global is of unknown type) and no value is refused for its '
    'conversion: nil, booleans, tables and functions for any conversion (for %s by the Lua 5.1 rule; LuaJIT shows an explicit nil or '
    'boolean, so that refusal is conservative), non-numeric strings and unproved call values '
    'for numeric ones; other values of unknown type are not checked; gsub and sub are not '
    'followed',
    'a module function or export counts only when the file chunk, or an initializer it calls '
    'as a statement, runs it at load; a call in chunk code before that point never reaches it, '
    'and a call inside a function is assumed to run after the files have loaded',
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
        data = _snapshot(row['data'])
        _consumer(_digest(data).hex() == row['sha256'], 'consumer-hash-mismatch', path)
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
        # {id(name node): the function whose own body holds the reference
        # (None: the file chunk)}, for _UnitFlow's reaching definitions.
        self.owners, self.current = {}, None
        # Every function node and every for-in statement of the file, in the
        # order resolved, so _UnitFlow and _UnitScan need no walk of their own.
        self.functions, self.forins = [], []

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
        self.owners[id(node)] = self.current
        if binding is not None:
            binding.uses.append((use, node))
            if use == 'target':
                binding.assigned.append(node)

    def block(self, body, scopes):
        scopes = scopes + [{}]
        for stmt in body:
            self.statement(stmt, scopes)

    def function(self, func, scopes):
        self.functions.append(func)
        outer, self.current = self.current, func
        try:
            self.function_body(func, scopes)
        finally:
            self.current = outer

    def function_body(self, func, scopes):
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
            self.forins.append(stmt)
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


def _path(node, loose=False, depth=0, env=False, accessor=True):
    """The dotted Nexus path an expression names ('Nexus',
    'Nexus.Localization', ...) through the global Nexus, literal fields and
    local aliases, else None. An alias that is assigned again names no path;
    loose=True ignores that, to tell a broken alias of a path apart from an
    unrelated name. env=True also reads _G.Nexus as Nexus, for assignment
    targets only (a mutation is never hidden behind _G; no consumer is
    accepted through it). A call names a path only as the call of a seam
    accessor (_seam_accessor), and then only Nexus.Localization itself;
    accessor=False refuses every call, so that an accessor is never read
    through another one."""
    if depth > 64:
        return None
    kind = node.kind
    if kind == 'paren':
        return _path(node.expr, loose, depth + 1, env, accessor)
    if kind == 'name':
        binding = node.binding
        if binding is None:
            return 'Nexus' if node.value == 'Nexus' else None
        if binding.kind != 'local' or binding.value is None or (binding.assigned and not loose):
            return None
        return _path(binding.value, loose, depth + 1, env, accessor)
    if kind == 'index':
        if env and node.key.kind == 'string' and node.key.value == 'Nexus' \
                and _global_ref(node.obj) == _ENV:
            return 'Nexus'
        base = _path(node.obj, loose, depth + 1, env, accessor)
        if base is not None and node.key.kind == 'string' and node.key.value is not None:
            return base + '.' + node.key.value
    if kind == 'call' and accessor:
        return _seam_accessor(node, loose, depth + 1, env)
    return None


def _seam_accessor(call, loose, depth, env):
    """Nexus.Localization when call is the call of a seam accessor, else
    None. A seam accessor is a local function (local function f, or local
    f = function) that is never assigned again, is no method, takes no
    parameter and no ..., holds no nested function, ends with a return
    statement, and whose every return statement gives exactly one value
    that is either the literal nil or names Nexus.Localization itself by
    the rules of _path without this one (the global path or a local alias
    never assigned again), at least one of them the seam. The call passes
    no argument. Its value is then the seam table as read while the
    accessor runs, or nil: a local declared with it (as the first value of
    that call) is the same kind of name as a local alias declared at that
    place. Exactly one level: a return that is itself a call, or an alias
    declared with a call, is refused, so there is no chain and no
    recursion. loose=True ignores an accessor or an inner alias that is
    assigned again, as for an alias; every other condition stays.

    The last statement is checked first, so a function that does not end
    with such a return costs no walk of its body."""
    callee = call.func
    if call.args or callee.kind != 'name':
        return None
    binding = callee.binding
    if binding is None or binding.kind not in ('local', 'localfunction') \
            or binding.value is None or binding.value.kind != 'function' \
            or (binding.assigned and not loose):
        return None
    func = binding.value
    if func.params or func.vararg or func.method or not func.body \
            or func.body[-1].kind != 'return':
        return None

    def returned(stmt):
        """True: the seam; False: the literal nil; None: anything else."""
        if len(stmt.exprs) != 1:
            return None
        value = stmt.exprs[0]
        if value.kind == 'constant' and value.value == 'nil':
            return False
        if _path(value, loose, depth, env, False) == _LOCALIZATION:
            return True
        return None

    if returned(func.body[-1]) is None:
        return None
    seam = False
    for node in _descendants(func.body):
        if node.kind == 'function':
            return None
        if node.kind == 'return':
            result = returned(node)
            if result is None:
                return None
            seam = seam or result
    return _LOCALIZATION if seam else None


def _seam_method(path):
    """The seam method name a path names (Nexus.Localization.<name>), else None."""
    prefix = _LOCALIZATION + '.'
    if path is not None and path.startswith(prefix) and '.' not in path[len(prefix):]:
        return path[len(prefix):]
    return None


def _literal_map(binding, string_values, iterated=frozenset()):
    """[(code, value node)] of a read-only local table of literal string keys
    (and literal string values when string_values), else None. The table
    must never be assigned again and only ever be indexed, or iterated by
    a for-in header pairs(table) whose name node is in iterated (the caller
    then requires the global pairs to stay unassigned)."""
    if binding is None or binding.kind != 'local' or binding.value is None:
        return None
    table = binding.value
    if table.kind != 'table' or binding.assigned or any(
            use != 'index' and not (use == 'value' and node in iterated)
            for use, node in binding.uses):
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

    def __init__(self, body, localfunctions, forins=None):
        self.problems, self.dynamic, self.literals = [], [], []
        self.wrappers, self.internal = {}, set()
        self.candidates, self.seam_assignments, self.path_assignments = [], [], {}
        if forins is None:      # the resolver's list, else one walk of the file
            forins = [stmt for stmt in _descendants(body, True) if stmt.kind == 'forin']
        # Name nodes T of each for-in header pairs(T) (a read-only iteration).
        self.iterated = frozenset(
            stmt.exprs[0].args[0] for stmt in forins
            if len(stmt.exprs) == 1 and stmt.exprs[0].kind == 'call'
            and stmt.exprs[0].func.kind == 'name' and stmt.exprs[0].func.binding is None
            and stmt.exprs[0].func.value == 'pairs' and len(stmt.exprs[0].args) == 1
            and stmt.exprs[0].args[0].kind == 'name')
        self.find_wrappers(localfunctions)
        self.find_forwarders(localfunctions)
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
        assigned, as the key. The receiver is the seam path, a local alias
        of it or a local declared with the call of a seam accessor (_path,
        _seam_accessor). Through a reassigned alias it is no wrapper;
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

    def find_forwarders(self, localfunctions):
        """A local function that is no wrapper itself is a forwarding wrapper
        when a call in its own body (not in a nested function) hands one of
        its own parameters, never assigned, to a direct wrapper
        (find_wrappers) as that wrapper's key. Exactly one forwarding level
        is admitted: the callee must be a direct wrapper, never another
        forwarding wrapper, so no chain and no cycle is followed. Every such
        call must agree on the parameter and the kind, and neither the
        function nor a direct wrapper it calls may be assigned again.
        Otherwise the function is no wrapper and everything stays as it was:
        its inner calls are listed as dynamic-wrapper-argument (or carry the
        direct wrapper's own reassignment problem) and a literal passed to it
        is no site. Only a literal key at a call of the forwarding wrapper is
        a site (wrapper_call); a map dispatch through it is not admitted.
        Passing the key on proves no output: whether the forwarding wrapper
        returns the direct wrapper's result, and that wrapper its own
        consumer-method result, is proved when a receipt links the units
        (_Linker.wrapper_returns), and the site then needs its own output."""
        direct = dict(self.wrappers)
        for binding in localfunctions:
            if binding in direct or binding.assigned:
                continue
            func = binding.value
            found = []
            for node in _descendants(func.body):
                if node.kind != 'call' or node.func.kind != 'name':
                    continue
                target = node.func.binding
                wrapper = direct.get(target) if target is not None else None
                if wrapper is None or target.assigned:
                    continue
                index = wrapper['parameter']
                arg = node.args[index] if index < len(node.args) else None
                if arg is None or arg.kind != 'name':
                    continue
                param = arg.binding
                if param is None or param.kind != 'param' or param.owner is not func \
                        or param.index is None or param.assigned:
                    continue
                found.append((node, target, param.index, wrapper['kind']))
            kinds = {(index, kind) for _, _, index, kind in found}
            if len(kinds) != 1:
                continue
            index, kind = kinds.pop()
            self.wrappers[binding] = {
                'name': binding.node.value, 'line': binding.node.line, 'parameter': index,
                'kind': kind, 'method': direct[found[0][1]]['method'],
                'internal': [node for node, _, _, _ in found],
                'forwards': [(node, target) for node, target, _, _ in found]}
            self.internal.update(id(node) for node, _, _, _ in found)

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
        path = _path(target, env=True)
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
        elif 'forwards' not in wrapper and arg is not None and arg.kind == 'index' \
                and arg.obj.kind == 'name' \
                and arg.key.kind == 'name' and arg.obj.binding is not None \
                and arg.obj.binding.kind == 'local' and arg.obj.binding.value is not None \
                and arg.obj.binding.value.kind == 'table':
            # A local table constructor indexed by a name: a map dispatch,
            # bound or explicitly unresolved, never silently dynamic. (Not
            # through a forwarding wrapper: that call is listed as dynamic.)
            self.dispatch(node, binding, arg, ctx)
        elif id(node) not in self.internal:
            # The call by which a forwarding wrapper hands its key parameter
            # to its direct wrapper (find_forwarders) is resolved, not dynamic.
            self.unknown(node, 'dynamic-wrapper-argument', wrapper=wrapper['name'])

    # -- map dispatch ------------------------------------------------------

    def dispatch(self, node, wrapper, arg, ctx):
        """A wrapper(MAP[v], ...) call: checked here for its local shape and
        preceding guards; its dispatcher and output chain are proved when a
        receipt links the units. The guard of the call indexes MAP itself or
        a parallel table with exactly MAP's keys (parallel_guard); every
        other condition is the same for both."""
        mapping, variable = arg.obj.binding, arg.key.binding
        entries = _literal_map(mapping, True)
        if entries is None:
            self.problem(node, 'binding-unresolved', construct='map',
                         detail='%s is not a read-only local table of literal string pairs'
                                % arg.obj.value)
            return
        reason, shadow, frames = None, {}, _frames(ctx)
        pairs_read = False
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
            # The guard indexes a local table by the dispatch variable and
            # the call is its sole return. The table is the map itself, or a
            # parallel table (parallel_guard) that passes for the same codes.
            shaped = (cond.kind == 'index' and cond.obj.kind == 'name'
                      and cond.key.kind == 'name' and cond.key.binding is variable
                      and returned.kind == 'return' and len(returned.exprs) == 1
                      and returned.exprs[0] is node)
            parallel = shaped and cond.obj.binding is not mapping \
                and cond.obj.binding is not None and cond.obj.binding.kind == 'local' \
                and cond.obj.binding.value is not None and cond.obj.binding.value.kind == 'table'
            pairs_read = self.parallel_guard(cond.obj.binding, entries) if parallel else False
            if not shaped or (cond.obj.binding is not mapping and not parallel):
                reason = 'the call is not the sole return guarded by the same MAP[v]'
            elif pairs_read is None:
                reason = ('%s is not a read-only local table of literal strings with exactly '
                          'the keys of %s' % (cond.obj.value, arg.obj.value))
            elif not _unassigned_until(variable, func, tail[0][2]):
                reason = ('the dispatch variable is not a local of this function left unassigned '
                          'up to the dispatch')
            elif funcstat is None or funcstat.method is not None \
                    or funcstat.target.kind != 'index' or funcstat.target.obj.kind != 'name':
                reason = 'the dispatch is not in a function T.Name of a module table'
        # A parallel guard read by a for-in pairs header keeps the condition
        # of every such guard: the global pairs stays unassigned (the linker
        # refuses the chain otherwise).
        iterated = pairs_read is True
        if reason is None:
            for earlier in func.body[:tail[0][2]]:
                guard = _guard(earlier, variable)
                if guard is not None:
                    codes = _literal_map(guard.binding, False)
                    if codes is None:
                        codes = _literal_map(guard.binding, False, self.iterated)
                        iterated = iterated or codes is not None
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
                                'funcstat': funcstat, 'iterated': iterated})

    def parallel_guard(self, binding, entries):
        """A guard 'if GUARD[v] then return wrapper(MAP[v], ...) end' over a
        second table: GUARD must be a read-only local table of literal string
        keys and literal string values (_literal_map: never assigned, only
        indexed, or iterated by a for-in pairs header), and its keys must be
        exactly the keys of MAP (entries). Every value is then a string, so
        truthy, and no other key has a value: the guard passes for exactly
        the codes MAP holds, as 'if MAP[v]' does, and MAP[v] is the literal
        value of an entry whenever it passes. A key of GUARD that MAP lacks
        (MAP[v] could be nil), a key of MAP that GUARD lacks (an entry that
        is never dispatched) and a value that is no literal string are
        refused. False: accepted with no pairs iteration; True: accepted,
        GUARD being iterated by pairs (the chain then needs the global pairs
        unassigned); None: refused."""
        rows, iterated = _literal_map(binding, True), False
        if rows is None:
            rows, iterated = _literal_map(binding, True, self.iterated), True
        if rows is None or {code for code, _ in rows} != {code for code, _ in entries}:
            return None
        return iterated


_STATEMENTS = frozenset(('local', 'localfunction', 'funcstat', 'assign', 'callstat', 'do',
                         'while', 'repeat', 'if', 'fornum', 'forin', 'return', 'break'))
# Evidenced output sinks: argument 1 of these widget, tooltip and chat-frame
# methods, and every argument of the global print.
_SINK_METHODS = frozenset(('SetText', 'AddLine', 'AddMessage'))
_SINK_FUNCTIONS = frozenset(('print',))
# Text-preserving transforms (Source25 continuation): the result of each is a
# string made from the whole text it is given, so a localization result
# followed into one is followed out of it. A string method called on a
# followed value (a string, so the string library method through the string
# metatable): its receiver flows to the result. A call of a standard global
# library function: the argument positions listed flow to the result. For
# format (either form) the format itself flows, and a later argument only
# when a static Lua 5.1 format consumes it with a %s conversion
# (_format_consumed, STD-V15-1); an ignored, non-text or unknown argument
# position never does. gsub and sub are not transforms: a pattern or range
# can discard the whole text (a constant or empty result). The linker drops
# every such edge while the trusted implementation is not established
# (_Linker.trusted, STD-V15-2): the loaded source may write that global, a
# field of the string library or the global environment, or may reach the
# string metatable.
_TEXT_METHODS = frozenset(('upper', 'lower', 'format'))
_TEXT_CALLS = types.MappingProxyType({
    'tostring': (0,), 'string.upper': (0,), 'string.lower': (0,), 'string.format': (0,)})
_FORMAT_CONVERSION = re.compile('%([-+ #0]*)([0-9]{0,2})(?:[.]([0-9]{0,2}))?(.)', re.S)
_FORMAT_OPTIONS = frozenset('cdiouxXeEfgGqs')
# The global environment table and the library table whose fields the
# transforms trust, and the globals through which the loaded source can
# reach every global (an environment function, the debug library or code
# loading): a reference to one of those opens the environment (V15 review
# fix SPEC-V15-1: _G.pairs and _G.setmetatable).
_ENV = '_G'
_STRING = 'string'
_ENV_OPENERS = frozenset(('getfenv', 'setfenv', 'debug', 'loadstring', 'load', 'loadfile',
                          'dofile', 'RunScript'))
# The debug library fields whose read does not open the environment.
_DEBUG_READS = frozenset(('traceback',))
_COMPARISON = frozenset(('==', '~=', '<', '<=', '>', '>='))


class _AnyName:
    """The global names the loaded source may write once the global
    environment is open: every name."""

    def __contains__(self, name):
        return True


_ANY_NAME = _AnyName()
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


_LOOPS = frozenset(('while', 'repeat', 'fornum', 'forin'))


def _straight(body):
    """(the statements of body that run whenever body runs to its end, True
    when body can only end by running past its last statement): in order,
    entering do blocks, up to the first statement that can return (or, an
    if, break). A compound statement itself is kept out: its body is
    conditional, so nothing in it is established."""
    out = []
    for stmt in body:
        if stmt.kind == 'do':
            inner, complete = _straight(stmt.body)
            out.extend(inner)
            if not complete:
                return out, False
            continue
        if stmt.kind in ('return', 'break'):
            return out, False
        if stmt.kind == 'if' or stmt.kind in _LOOPS:
            leaving = ('return',) if stmt.kind in _LOOPS else ('return', 'break')
            if any(node.kind in leaving for node in _descendants([stmt])):
                return out, False
            continue
        out.append(stmt)
    return out, True


def _library_name(callee):
    """'name' for a global name callee, 'table.name' for a literal field of a
    global table name, else None (locals and other expressions)."""
    if callee.kind == 'name' and callee.binding is None:
        return callee.value
    if callee.kind == 'index' and callee.obj.kind == 'name' and callee.obj.binding is None \
            and callee.key.kind == 'string' and callee.key.value is not None:
        return callee.obj.value + '.' + callee.key.value
    return None


def _static_string(node, depth=0):
    """The string an expression always evaluates to, else None: a literal,
    a concatenation of such strings, or an unassigned local declared with
    one, through parentheses."""
    while node.kind == 'paren':
        node = node.expr
    if depth > 16:
        return None
    if node.kind == 'string':
        return node.value
    if node.kind == 'operation' and node.ops and all(op == '..' for op in node.ops):
        parts = [_static_string(operand, depth + 1) for operand in node.operands]
        return None if None in parts else ''.join(parts)
    binding = node.binding if node.kind == 'name' else None
    if binding is not None and binding.kind == 'local' and binding.value is not None \
            and not binding.assigned:
        return _static_string(binding.value, depth + 1)
    return None


def _global_ref(node, depth=0):
    """The global a node names: a global name, or a field _G[key] with a
    static key (_static_string, as _G.name or _G["na" .. "me"]) of a global
    name it names, through parentheses, else None."""
    while node.kind == 'paren':
        node = node.expr
    if node.kind == 'name':
        return node.value if node.binding is None else None
    if node.kind == 'index' and depth < 16 and _global_ref(node.obj, depth + 1) == _ENV:
        return _static_string(node.key)
    return None


# The globals whose identity a proof may depend on (STD-8849-2): a computed
# _G[k] read whose key may be one of them is an unknown global that may be
# the environment, the string library, Nexus, a trusted function or an
# environment opener (debug's functions included).
_ENV_TRACKED = frozenset((
    _ENV, _STRING, 'Nexus', 'pairs', 'ipairs', 'next', 'setmetatable', 'getmetatable', 'rawset',
    'rawget', 'rawequal', 'tostring', 'print', 'type', 'pcall', 'xpcall', 'select', 'unpack',
    'CreateFrame', 'UIParent', 'GameTooltip', 'DEFAULT_CHAT_FRAME', 'gethook', 'getinfo',
    'getlocal', 'getregistry', 'getupvalue', 'sethook', 'setlocal', 'setupvalue',
    'traceback')) | _ENV_OPENERS


def _parameterless(value):
    """True when a written field value is a function literal taking no
    argument at all: no parameter, no implicit self and no ...."""
    return value is not _OPAQUE and value.kind == 'function' and not value.params \
        and not value.method and not value.vararg


class _EnvContext:
    """Parent links and for-in headers of one function body (closures
    included), built only for a computed _G[k] read that needs them."""

    def __init__(self, body):
        self.parent, self.forin = {}, {}
        stack = list(body)
        while stack:
            node = stack.pop()
            if node.kind == 'forin':
                for position, name in enumerate(node.names):
                    self.forin[name.binding] = (node, position)
            for child in _children(node):
                self.parent[id(child)] = node
                stack.append(child)

    def read_only_table(self, binding, truth_only):
        """The constructor of an unassigned local table that is only read
        (indexed, or only tested or measured), else None."""
        if binding is None or binding.kind != 'local' or binding.assigned \
                or binding.value is None or binding.value.kind != 'table':
            return None
        for use, node in binding.uses:
            if use == 'index' and not self.written(node):
                continue
            if use == 'value' and node in truth_only:
                continue
            return None
        return binding.value

    def written(self, node):
        """True when node is the table of an assignment or definition target."""
        target = self.parent.get(id(node))
        holder = self.parent.get(id(target)) if target is not None else None
        return target is not None and target.kind == 'index' and target.obj is node \
            and holder is not None and (
                (holder.kind == 'assign' and any(t is target for t in holder.targets))
                or (holder.kind == 'funcstat' and holder.target is target))

    def candidates(self, key, truth_only, deps, depth=0):
        """Every string key may be, or None when that is not proved: a
        static string, a field of a read-only local literal table whose
        values are all static, or a for-in variable over such a table."""
        while key.kind == 'paren':
            key = key.expr
        text = _static_string(key)
        if text is not None:
            return frozenset((text,))
        if depth > 8:
            return None
        if key.kind == 'index' and key.obj.kind == 'name':
            return self.table_values(self.read_only_table(key.obj.binding, truth_only), 1)
        binding = key.binding if key.kind == 'name' else None
        if binding is not None and binding.kind == 'for' and binding in self.forin:
            stmt, position = self.forin[binding]
            call = stmt.exprs[0] if len(stmt.exprs) == 1 else None
            if call is None or call.kind != 'call' or call.func.kind != 'name' \
                    or call.func.binding is not None \
                    or call.func.value not in ('pairs', 'ipairs') \
                    or len(call.args) != 1 or position > 1:
                return None
            table = call.args[0]
            if table.kind == 'name':
                table = self.read_only_table(table.binding, truth_only)
            if table is None or table.kind != 'table':
                return None
            deps.add(call.func.value)
            return self.table_values(table, position)
        return None

    @staticmethod
    def table_values(table, position):
        """The static string keys (position 0) or values (position 1) of a
        constructor, or None when one is not static."""
        if table is None:
            return None
        out = set()
        for field in table.fields:
            part = field.value if position == 1 else field.key
            text = _static_string(part) if part is not None else None
            if text is None:
                return None
            out.add(text)
        return frozenset(out)

    def excluded(self, key, truth_only, deps):
        """True when key is proved to name no tracked global (_ENV_TRACKED):
        all its candidates are untracked, or it is a concatenation with a
        piece whose every candidate is in no tracked name."""
        found = self.candidates(key, truth_only, deps)
        if found is not None:
            return not (found & _ENV_TRACKED)
        if key.kind == 'operation' and key.ops and all(op == '..' for op in key.ops):
            for piece in key.operands:
                local = set()
                found = self.candidates(piece, truth_only, local)
                if found and all(text and not any(text in name for name in _ENV_TRACKED)
                                 for text in found):
                    deps.update(local)
                    return True
        return False


# What C strtod (Lua 5.1 lua_str2number) may accept after its whitespace:
# a string that matches none of these is never a number for %d and the
# other numeric conversions, so that format call always raises.
_MAYBE_NUMBER = re.compile(
    r'[+-]?(?:(?:[0-9]+[.]?[0-9]*|[.][0-9]+)(?:[eE][+-]?[0-9]+)?'
    r'|0[xX](?:[0-9a-fA-F]+[.]?[0-9a-fA-F]*|[.][0-9a-fA-F]+)(?:[pP][+-]?[0-9]+)?'
    r'|(?i:inf(?:inity)?|nan(?:[(][0-9A-Za-z_]*[)])?))')
_FORMAT_NUMERIC = frozenset('cdiouxXeEfgG')


def _format_argument_fails(arg, option):
    """True when a format argument (through parentheses, which keep its one
    value) is statically refused for its conversion: nil, a boolean, a table
    or a function for any conversion, and a static string that strtod can
    never read for a numeric one. For a numeric conversion each of these
    raises (luaL_checknumber) in Lua 5.1 and in LuaJIT alike. For s and q
    the rule follows the Lua 5.1 target (lstrlib.c str_format:
    luaL_checklstring raises for anything but a string or number); the
    commissioned LuaJIT runtime instead shows an explicitly given nil or
    boolean ("nil", "false") and may convert other values the same way, so
    there the refusal is conservative: it proves no output and is not a
    claim that LuaJIT raises. Any other argument is not known to fail (a
    data-dependent failure is outside this static check)."""
    while arg.kind == 'paren':
        arg = arg.expr
    if arg.kind == 'constant' and arg.value in ('nil', 'true', 'false'):
        return True
    if arg.kind in ('table', 'function'):
        return True
    text = _static_string(arg)
    if text is None or option not in _FORMAT_NUMERIC:
        return False
    return _MAYBE_NUMBER.fullmatch(text.strip(' \t\n\v\f\r')) is None


# Descriptors of a value (_call_values, _adjusted), besides an expression
# node: one that may be nil (refused for every conversion, see
# _format_argument_fails); one of the seam's source names ("base",
# "candidate", "unavailable": a string that is never a number, so it fails
# every numeric conversion); and the one value Lua makes of a call whose
# results are not proved (an unresolved callee, ... or a call deeper than
# _CALL_DEPTH): it may be the nil of a call that gave none, so it is refused
# for a numeric conversion; for s and q it is a value of unknown type, not
# checked (a documented limit).
_MAY_BE_NIL = object()
_SOURCE_NAME = object()
_UNPROVED = object()
_CALL_DEPTH = 8
_ALIAS_STEPS = 16


def _call_values(call, depth=0):
    """(values, exact, first) for the results of a call (review fixes of
    7594 and bcf7): values is a tuple with one entry per value the call is
    proved to give, each a tuple of descriptors of what that value may be
    (adjusted expression nodes, _MAY_BE_NIL, _SOURCE_NAME or _UNPROVED; ()
    when nothing is known of it); exact is True when the call gives exactly
    that many values on every path; first describes the one value Lua makes
    of the call where it is cut to one (an argument that is not the last, a
    return expression that is not the last, or a parenthesized call): its
    first result, or nil on a path that gives none. Proved only for two kinds
    of callee:

    - Nexus.Localization.Text, Resolve or Format (a seam key method): by the
      contract of core/Localization.lua each returns exactly text, source,
      reason; text is a string, source one of the source names and reason a
      string or nil.
    - an unassigned local function (_local_function): the meet of its
      return statements (outside nested functions), and of a path giving no
      value at all unless its body ends with a return, since a path may run
      off its end. A path that gives fewer values keeps its nil in first.

    Any other call (a global, a module or method function, a reassigned
    local, a call deeper than _CALL_DEPTH) gives no proved value, no exact
    count and an _UNPROVED first value."""
    unknown = ((), False, (_UNPROVED,))
    if depth > _CALL_DEPTH or call.kind != 'call':
        return unknown
    if _seam_method(_path(call.func)) in _KEY_METHODS:
        return ((), (_SOURCE_NAME,), (_MAY_BE_NIL,)), True, ()
    target = _local_function(call.func)
    if target is None:
        return unknown
    shapes = [_return_values(stmt, depth + 1) for stmt in _descendants(target.body)
              if stmt.kind == 'return']
    if not target.body or target.body[-1].kind != 'return':
        shapes.append(((), True, (_MAY_BE_NIL,)))
    length = min(len(values) for values, _, _ in shapes)
    values = tuple(tuple(part for found, _, _ in shapes for part in found[index])
                   for index in range(length))
    exact = all(whole and len(found) == length for found, whole, _ in shapes)
    first = tuple(part for _, _, one in shapes for part in one)
    return values, exact, first


def _return_values(stmt, depth):
    """(values, exact, first) of one return statement (see _call_values):
    each expression but the last is cut to one value (_adjusted); a last call
    gives its own results, a last ... an unknown number, and anything else,
    parenthesized calls included, one adjusted value. An empty return gives
    no value, so its first value is nil."""
    if not stmt.exprs:
        return (), True, (_MAY_BE_NIL,)
    head = tuple(_adjusted(expr, depth) for expr in stmt.exprs[:-1])
    last = stmt.exprs[-1]
    if last.kind in ('call', 'method'):
        values, exact, first = _call_values(last, depth)
        return head + values, exact, head[0] if head else first
    if last.kind == 'constant' and last.value == '...':
        return head, False, head[0] if head else (_UNPROVED,)
    values = head + (_adjusted(last, depth),)
    return values, True, values[0]


def _immutable_value(expr):
    """The declared expression of a name of an immutable local (see
    _adjusted), else None."""
    binding = expr.binding if expr.kind == 'name' else None
    if binding is None or binding.kind not in ('local', 'localfunction') \
            or binding.assigned or binding.value is None:
        return None
    return binding.value


def _adjusted(expr, depth=0):
    """The descriptors of the one value Lua makes of an expression where it
    is cut to one value: an argument that is not the last, a return
    expression that is not the last, or any parenthesized expression.
    Parentheses keep the value of what they hold (a nil, boolean, table or
    static string stays known); a call or method gives its first result, or
    nil when a path gives none (_call_values first); ... gives an unknown
    value that may be nil (_UNPROVED).

    A name of an immutable local (SPEC-EFD7-1) holds the one value of its
    declaration, so it is followed to that expression, through chains of
    such locals, upvalues of a returning function included: a local
    statement name declared with an expression (local v = e: the value Lua
    makes of e for that name, the first result of a call), or a local
    function. Lexical resolution already picked the binding, so shadowing is
    respected. A local assigned anywhere (closures included), declared
    without its own expression (local v, or a later name of local a, b =
    f()), a parameter, a for variable or a global is not followed: its value
    stays of unknown type. At most _ALIAS_STEPS links are followed; a chain
    of immutable locals still longer than that is not promoted to an
    unknown-type value: it gives an unproved value (_UNPROVED), refused for
    a numeric conversion (review fix of cf01), since what it holds was not
    established within the bound."""
    for _ in range(_ALIAS_STEPS):
        while expr.kind == 'paren':
            expr = expr.expr
        value = _immutable_value(expr)
        if value is None:
            break
        expr = value
    while expr.kind == 'paren':
        expr = expr.expr
    if _immutable_value(expr) is not None:
        return (_UNPROVED,)     # the bounded walk ended inside the chain
    if expr.kind in ('call', 'method'):
        return _call_values(expr, depth)[2]
    if expr.kind == 'constant' and expr.value == '...':
        return (_UNPROVED,)
    return (expr,)


def _value_fails(descriptors, option):
    """True when a value described so is refused for its conversion: it may
    be nil (_MAY_BE_NIL), or, for a numeric conversion, it may be a source
    name or an unproved value (an unresolved call, or an immutable alias
    chain longer than the walk bound), or one of its expressions is refused
    (_format_argument_fails)."""
    for part in descriptors:
        if part is _MAY_BE_NIL:
            return True
        if part is _SOURCE_NAME or part is _UNPROVED:
            if option in _FORMAT_NUMERIC:
                return True
        elif _format_argument_fails(part, option):
            return True
    return False


def _format_consumed(fmt, args):
    """The 1-based positions of the arguments after the format that a
    static (_static_string) Lua 5.1 format string shows as text (a %s
    conversion, with no precision or a precision of at least 1), or None
    when that call is not proved to return (STD-V15-1, STD-8849-1 and the
    review fix of 7594): the format is not static, Lua 5.1 refuses it
    (lstrlib.c str_format: an unknown option, more than five flags, a width
    or precision above two digits), a value may be statically known to fail
    its conversion (_value_fails), or a conversion has no value proved
    present. Each argument but the last gives one adjusted value
    (_adjusted); the last one, when it is a call or method, gives exactly
    the values _call_values proves (none at all for a callee it cannot
    resolve, never an assumed one), ... gives none for certain, and any
    other last argument, a parenthesized call included, one adjusted value.
    A position after the last argument is a further result of that last
    call: it is checked and counted, but it is not an argument, so it never
    flows."""
    text = _static_string(fmt)
    if text is None:
        return None
    values = [_adjusted(arg) for arg in args[:-1]]
    if args:
        last = args[-1]
        if last.kind in ('call', 'method'):
            values.extend(_call_values(last)[0])
        elif not (last.kind == 'constant' and last.value == '...'):
            values.append(_adjusted(last))
    present = len(values)
    index, position, consumed = 0, 0, set()
    while True:
        index = text.find('%', index)
        if index < 0:
            break
        if text.startswith('%%', index):
            index += 2
            continue
        match = _FORMAT_CONVERSION.match(text, index)
        if match is None or match.group(4) not in _FORMAT_OPTIONS:
            return None
        flags, width, precision, option = match.groups()
        if len(flags) > 5:          # sizeof(FLAGS) - 1: "invalid format (repeated flags)"
            return None
        position += 1
        if position > present or _value_fails(values[position - 1], option):
            return None
        if option == 's' and (precision is None or (precision != '' and int(precision) > 0)):
            consumed.add(position)
        index = match.end()
    return consumed


def _metatable_hook(call):
    """The name node of M in a statement setmetatable(M, {__index = function
    (t, ...) ... end}) whose metatable is an inline constructor holding only
    __index, a function that never uses its table parameter t, else None.
    Lua consults __index only for a field the table does not hold, so every
    field the module defines resolves to that definition alone; nothing here
    stores M or writes through the hook, and the statement discards the
    result. The linker additionally requires the global setmetatable to stay
    unassigned (module_function)."""
    if call.kind != 'call' or call.func.kind != 'name' or call.func.binding is not None \
            or call.func.value != 'setmetatable' or len(call.args) != 2:
        return None
    target, meta = call.args
    if target.kind != 'name' or target.binding is None or meta.kind != 'table' \
            or len(meta.fields) != 1:
        return None
    field = meta.fields[0]
    if field.key is None or field.key.kind != 'string' or field.key.value != '__index' \
            or field.value.kind != 'function' or not field.value.params:
        return None
    first = field.value.params[0].binding
    if first is None or first.uses:
        return None
    return target


def _module_root(binding):
    """The binding a chain of unassigned local aliases (local a = b) names."""
    for _ in range(16):
        value = binding.value
        if binding.kind != 'local' or binding.assigned or value is None \
                or value.kind != 'name' or value.binding is None:
            return binding
        binding = value.binding
    return binding


def _local_function(callee):
    """The function node a callee names when it is an unassigned local
    function (local function f or local f = function), else None."""
    binding = callee.binding if callee.kind == 'name' else None
    if binding is not None and not binding.assigned and binding.value is not None \
            and binding.value.kind == 'function' and binding.kind in ('local', 'localfunction'):
        return binding.value
    return None


_STACK_LIMIT = 8
# Function results are followed position by position (Lua 5.1 manual 2.4.3
# and 2.5): result 0 is the first value, the value of the call expression
# itself, as before; results 1 to _RESULT_LIMIT - 1 are followed only where
# _UnitFlow.later_result and _Linker.result_states say. A position at or
# beyond the limit is not followed (it also ends a recursive tail return).
_RESULT_LIMIT = 8
# Output receivers are client objects, proved from evidenced roots (review
# fix 3): the client globals below while the loaded source never assigns
# them, widgets made by the global CreateFrame, and widgets made by a
# CreateFontString method called on a proved client object, while the
# loaded source never redefines CreateFontString.
_CLIENT_GLOBALS = frozenset(('UIParent', 'GameTooltip', 'DEFAULT_CHAT_FRAME'))
_WIDGET_FUNCTIONS = frozenset(('CreateFrame',))
_WIDGET_METHODS = frozenset(('CreateFontString',))
# A receiver field is proved on the object its base may hold. A local that
# holds the result of a local helper is that object only for one proved
# shape, the singleton cache (_UnitFlow.cached_singleton): every value the
# helper ever returns is then the one object it made, and every use of the
# helper is a local declared with its direct call, so every such local and
# the helper's own local hold the same object (_Linker.widened). A helper
# with any other use, or whose object is handed on by any name holding it
# (stored, returned, passed, aliased), is refused as a whole. Any other
# helper result stays
# a separate object per local: two calls of an uncached factory never
# share a field.


class _UnitFlow:
    """The may-flow graph of one parsed file, built once with its parse.

    A value flows from an expression into a paren, into an operation for the
    operands _flowing_operands names, into the binding a local statement or
    assignment gives it, into a literal table field (constructor or field
    assignment), into the return of its function (each expression of a
    return statement into its own position: ('ret', function) for the first,
    ('ret', function, n) for a later one, never into another position), into
    the parameter of a local function it is passed to (directly or through
    pcall), and into argument 1 of a _SINK_METHODS call or any argument of a
    _SINK_FUNCTIONS call, the candidate outputs. A binding passes a value on
    to its reads only when every definition (its declared value and every
    assignment, closures included) carries a value of the same proof; a
    value-less definition such as a for variable never does, and a later
    multiple-value position does only for a flow-sensitive local, through
    the result node of its call (later_result); in defs that position stays
    value-less, so every other rule sees it as before. Review fix 2 (SPEC-147-S8-RF1-1..3): a field value
    reaches only a read whose table shares an object origin with the
    written table (objects); a parameter value returns only to the call
    that passed it (call_args, direct_calls, kept by the linker's call
    stack); and a candidate output counts only on a client output receiver
    (the linker's client_object). Function results reach the calls the
    receipt can resolve: local functions here, module functions and their
    Nexus exports when the units are linked."""

    def __init__(self, body, owners=None, functions=None):
        self.owners, self.functions = owners, functions
        self.edges, self.defs, self.def_of = {}, {}, {}
        self.field_writes, self.field_reads, self.field_def_of = {}, {}, {}
        self.field_bases = {}
        self.call_args, self.param_args, self.direct_calls = {}, {}, {}
        self.pcall_calls, self.function_binding = {}, {}
        self.global_writes, self.sinks = set(), {}
        self.path_calls, self.module_calls = {}, []
        self.module_defs, self.dynamic_modules = {}, set()
        self.alias_of, self.export_values, self.exports = {}, set(), []
        self.chunk_returns = set()
        # Later result positions (see _RESULT_LIMIT). results: {(call node,
        # n): the node standing for result n of that call}, made only for a
        # name that a multiple assignment gives that position (later_result).
        # tail_calls: {call node: (function, index)} for a call that is the
        # last expression of a return statement of function, at index: its
        # result n is that function's return position index + n.
        self.results, self.tail_calls = {}, {}
        # Name nodes passed as the table of a lazy-field metatable statement
        # (metatable_hook); the linker also requires the global setmetatable
        # to stay unassigned in the loaded source.
        self.metatable_args = set()
        # (implementation, source, transform) of each transform edge: a
        # _TEXT_CALLS name ('tostring', 'string.upper', ...) or ':' and the
        # string method name for a method transform (STD-V15-2).
        self.library_edges = []
        # The global environment and the string library (V15 review fix):
        # global names written through _G as well as by name (global_writes),
        # string library fields written ('string.upper', or '*' for any
        # field: a computed key or a reference to the table that escapes),
        # every reference that may write any global (env_escapes), and every
        # getmetatable call whose result may leave a truth test or comparison
        # (metatable_escapes: it may be the shared string metatable).
        self.library_writes, self.env_escapes, self.metatable_escapes = set(), [], []
        self.truth_only, self.getmetatable_calls = set(), []
        self.type_args, self.type_escapes = set(), []
        # Computed _G[k] reads (STD-8849-2): (read, function) while walking;
        # then, for each read proved harmless only on conditions the linker
        # checks, (read, globals that must stay unassigned, method names it
        # is the receiver of, method names it is an argument of). The
        # environment argument of a rawget(_G, "name") read of an ordinary
        # global is recorded the same way while walking, on the one condition
        # that rawget stays unassigned (raw_global_read).
        self.env_reads, self.env_read_conditions = [], []
        # Load-time establishment (V15 review fix SPEC-V15-2, unused initializer;
        # STD-8849-3 ordering, see load_points): the statement of each
        # defining value and assignment target (build only).
        self.def_statement = {}
        self.target_statement = {}
        self.declared = set()   # values given by local declarations (not later assignments)
        # Write-once memos (objects, module_ok): an entry, once final, is
        # never changed or dropped. object_memo holds a provisional entry
        # only while objects computes it, seen only by that computation; no
        # linker search may run inside one. _Linker.prove relies on both for
        # object_memo when it uses one single-root search for several keys.
        self.object_memo, self.module_ok_memo = {}, {}
        self.made_in = {}       # table constructors and locals: the function made in (None: chunk)
        self.block(body, None)
        self.flow_sensitive(body)
        # {function node: (the local holding its one object, the creator
        # global)} for each singleton cache helper (cached_singleton).
        self.singletons = self.cached_singletons(body)
        established, load_calls = self.load_points(body)
        self.metatable_contained()
        self.check_env_reads(body)
        self.module_funcs = {}
        for module, fields in self.module_defs.items():
            for name, values in fields.items():
                value = values[0] if len(values) == 1 else None
                stmt = self.def_statement.get(value) if value is not None else None
                self.module_funcs[(module, name)] = (
                    value if value is not None and value.kind == 'function' else None,
                    len(values), established.get(stmt))
        # Only what linking reads is kept with the memoized flow: the load
        # point (or None) of each Nexus path assignment target, and the load
        # point of each module or path call made while the file loads.
        self.path_points = {target: established.get(stmt)
                            for target, stmt in self.target_statement.items()
                            if _path(target, env=True) is not None}
        calls = {call for _, _, call in self.module_calls}
        calls.update(call for rows in self.path_calls.values() for call in rows)
        self.chunk_calls = {call: point for call, point in load_calls.items() if call in calls}
        del self.truth_only, self.type_args, self.getmetatable_calls, self.def_statement
        del self.env_reads, self.env_contexts, self.env_chunk
        del self.target_statement

    def load_points(self, body):
        """({statement: load point}, {call: load point}) of the file chunk
        (STD-8849-3). A load point is a tuple of statement indexes, ordered
        as the file loads: (i,) for the chunk's statement i, (i, k) for
        statement k of a do block in it or of the body of an initializer
        that statement i calls, and so on for nested blocks and nested
        initializer calls. An initializer is an unassigned local function
        that an established statement calls as a statement; its body runs
        right there, at the first such call. A statement is established when
        it runs whenever the chunk loads to its end (_straight's rule: up to
        the first statement that can return, or, an if, break; a compound
        statement's own body is conditional). Every call in chunk code or in
        an invoked initializer body, established or not (but not inside a
        nested function, which may run later), gets the point of the
        statement it is in, so a call earlier than a definition is never
        taken to see it."""
        established, calls, invoked = {}, {}, set()

        def mark(stmt, point):
            for node in _descendants([stmt]):
                if node.kind == 'call':
                    calls.setdefault(node, point)

        def run(statements, prefix, live):
            for index, stmt in enumerate(statements):
                point = prefix + (index,)
                if stmt.kind == 'do':
                    live = run(stmt.body, point, live)
                    continue
                mark(stmt, point)
                if not live:
                    continue
                if stmt.kind in ('return', 'break'):
                    live = False
                    continue
                if stmt.kind == 'if' or stmt.kind in _LOOPS:
                    leaving = ('return',) if stmt.kind in _LOOPS else ('return', 'break')
                    if any(node.kind in leaving for node in _descendants([stmt])):
                        live = False
                    continue
                established[stmt] = point
                if stmt.kind == 'callstat' and stmt.call.kind == 'call':
                    target = _local_function(stmt.call.func)
                    if target is not None and target not in invoked:
                        invoked.add(target)
                        run(target.body, point, True)
            return live
        run(body, (), True)
        return established, calls

    def edge(self, source, target):
        self.edges.setdefault(source, []).append(target)

    def flow_sensitive(self, body):
        """Replace the binding hop of each local that only its own function
        body assigns and reads (_ReachingDefinitions) by direct edges from
        each definition to the reads it reaches; such a local is then never
        gated, because an overwritten definition no longer reaches the read.
        Every other binding keeps the every-definition rule."""
        owners = self.owners if self.owners is not None else _owner_functions(body)
        missing = object()
        eligible = set()
        for binding, func in self.made_in.items():
            if type(binding) is not _Binding or binding.kind != 'local':
                continue
            nodes = [node for _, node in binding.uses] + list(binding.assigned)
            if all(owners.get(id(node), missing) is func for node in nodes):
                eligible.add(binding)
        if not eligible:
            return
        passes = _ReachingDefinitions(eligible, self.later_result)
        passes.run(body)
        functions = self.functions
        if functions is None:   # the resolver's list, else one walk of the file
            functions = [node for node in _descendants(body, True) if node.kind == 'function']
        for func in functions:  # each pass only adds to its own reads, in any order
            passes.run(func.body)
        for binding in eligible:
            for value in self.defs.get(binding, ()):
                if value is not _OPAQUE and value in self.edges:
                    self.edges[value] = [target for target in self.edges[value]
                                         if target is not binding]
            for use in self.edges.pop(binding, ()):
                for value in passes.reach.get(use, ()):
                    if value is not _OPAQUE and value is not _NIL_DEF:
                        self.edge(value, use)
        self.flow_sensitive_locals = frozenset(eligible)

    def define(self, binding, value):
        self.defs.setdefault(binding, []).append(value)
        if value is not _OPAQUE:
            self.edge(value, binding)
            self.def_of.setdefault(value, []).append(binding)

    def later_result(self, exprs, index):
        """The node standing for the value that the name or target at index
        gets from an expression list with no expression of its own for it,
        or None. By Lua 5.1 (manual 2.4.3, 2.5) only a function call that is
        the last expression gives more than one value; the name at index
        then holds result index - len(exprs) + 1 of that call (its first
        result is 0 and is the call expression itself). A call that is not
        last, a parenthesized call, a method call, ... and every other last
        expression give no node: the position stays value-less, as does one
        at or beyond _RESULT_LIMIT. The node is one per (call, position); it
        carries no value of its own and is reached only when the linker
        proves that position of a function the call resolves to
        (_Linker.result_states), so the first result, a consumer method's
        later status values and an unresolved callee never reach it."""
        if not exprs or index < len(exprs) or exprs[-1].kind != 'call':
            return None
        position = index - len(exprs) + 1
        if position >= _RESULT_LIMIT:
            return None
        key = (exprs[-1], position)
        if key not in self.results:
            self.results[key] = _Node('result', exprs[-1], call=exprs[-1], value=position)
        return self.results[key]

    def write_field(self, name, value, base):
        """value written to field name of base (a local binding, a table
        constructor node, or None for any other table expression)."""
        self.field_writes.setdefault(name, []).append(value)
        if value is not _OPAQUE:
            self.edge(value, ('fwrite', value))
            self.field_def_of.setdefault(value, []).append(name)
            self.field_bases[value] = (name, base)

    def alias_root(self, base):
        """The binding a chain of locals declared once as an alias (local a
        = b, never assigned again) names, else base itself."""
        for _ in range(16):
            if type(base) is not _Binding or base.kind != 'local':
                return base
            defs = self.defs.get(base, ())
            if len(defs) != 1 or defs[0] is _OPAQUE or defs[0].kind != 'name' \
                    or defs[0].binding is None:
                return base
            base = defs[0].binding
        return base

    def objects(self, base, depth=0):
        """The object origins a table reference may hold, or None when its
        identity is not tracked: a table constructor is its own origin; a
        local declared once (never assigned again) holds itself plus the
        origins of a local alias or constructor it is declared with; a
        parameter never assigned holds itself plus the origins of every
        local alias or constructor a resolved call passes to it."""
        if base is None or depth > 16:
            return None
        if type(base) is not _Binding:
            return frozenset((base,))
        if base in self.object_memo:
            return self.object_memo[base]
        self.object_memo[base] = frozenset((base,))
        defs = self.defs.get(base, ())
        if base.kind == 'local' and len(defs) == 1 and defs[0] is not _OPAQUE:
            sources = [defs[0]]
        elif base.kind == 'param' and not defs:
            sources = self.param_args.get(base, ())
        else:
            self.object_memo[base] = None
            return None
        origins = {base}
        for source in sources:
            if source.kind == 'table':
                origins.add(source)
            elif source.kind == 'name' and source.binding is not None:
                origins |= self.objects(source.binding, depth + 1) or frozenset()
        self.object_memo[base] = frozenset(origins)
        return self.object_memo[base]

    def cached_singletons(self, body):
        """{function node: (the local holding the object, the creator global
        name)} for the functions of this file that have the singleton cache
        shape (cached_singleton) and whose object never leaves the names
        that hold it (review F1): the cache, the helper's own local and
        every holder are each used only in ways that keep the object in
        place (confined). The use places are collected once, and only for a
        file that has such a helper at all."""
        functions = self.functions
        if functions is None:   # the resolver's list, else one walk of the file
            functions = [node for node in _descendants(body, True) if node.kind == 'function']
        found, places = {}, None
        for func in functions:
            shape = self.cached_singleton(func)
            if shape is None:
                continue
            if places is None:
                places = self.singleton_places(body)
            receivers, creator_args, tested = places
            owned, creator, cache, store, holders, cache_values, owned_values = shape
            names = frozenset([cache, owned] + holders)
            # A write with a computed key through one of these names is not
            # recorded as a field write, so it could overwrite the receiver
            # field or store a method unseen (review S5): refuse the helper.
            if names & self.dynamic_modules:
                continue
            if self.confined(cache, cache_values, receivers, names, tested, store) \
                    and self.confined(owned, owned_values | creator_args, receivers, names,
                                      tested) \
                    and all(self.confined(holder, frozenset(), receivers, names, tested)
                            for holder in holders):
                found[func] = (owned, creator)
        return found

    @staticmethod
    def singleton_places(body):
        """({id(name node): method name} for each name that is the receiver
        of a method call, {id(name node)} for each name that is an argument
        of a call of a _WIDGET_FUNCTIONS global by its plain name, {id(name
        node)} for each name whose value is only tested or compared), over
        the whole file, nested functions included.

        The third set is built here for this purpose alone (review S6); the
        flow's truth_only answers another question (whether text flows on)
        and also holds arithmetic and concatenation operands, which hand the
        value to the other operand's metamethod. A name is in the set only
        when its value ends in one of these places, through parentheses:

        - the condition of an if, elseif, while or repeat;
        - the operand of not;
        - an operand of ==, ~=, <, <=, > or >= (a comparison calls a
          metamethod only when both operands share it);
        - an operand of and/or whose whole expression is itself in one of
          these places. An and/or expression used as a value can be the
          operand itself (a or {}, true and a), so it is not admitted.

        An operand next to any other operator (arithmetic, .., ^) is not in
        the set, nor is the operand of unary minus or #. The parser keeps a
        chain of binary operators flat and does not model precedence, so the
        places are decided here by Lua 5.1 precedence: arithmetic, .. and ^
        bind tighter than a comparison, a comparison tighter than and/or, a
        unary operator tighter than every binary one except ^ (not a ^ b is
        not (a ^ b): the operand of that not is refused)."""
        receivers, creator_args, tested = {}, set(), set()
        for node in _descendants(body, True):
            if node.kind == 'method' and node.obj.kind == 'name':
                receivers[id(node.obj)] = node.name
            elif node.kind == 'call' and node.func.kind == 'name' \
                    and node.func.binding is None and node.func.value in _WIDGET_FUNCTIONS:
                creator_args.update(id(arg) for arg in node.args if arg.kind == 'name')
        testing = _COMPARISON | frozenset(('and', 'or'))
        # (node, state): True when the node's value is only tested or
        # compared, False when it is not, None when it is the left operand
        # of ^ (a unary operator before it then applies to the power).
        stack = [(stmt, False) for stmt in body]
        while stack:
            node, state = stack.pop()
            kind = node.kind
            if kind == 'name':
                if state is True:
                    tested.add(id(node))
            elif kind == 'paren':
                stack.append((node.expr, state))
            elif kind == 'operation':
                operands, ops = node.operands, node.ops
                if len(operands) == 1:
                    stack.append((operands[0], None if state is None else ops[0] == 'not'))
                    continue
                for index, operand in enumerate(operands):
                    near = ops[max(index - 1, 0):index + 1]
                    if index < len(ops) and ops[index] == '^':
                        inner = None
                    elif any(op not in testing for op in near):
                        inner = False
                    elif any(op in _COMPARISON for op in near):
                        inner = True
                    else:
                        inner = state is True
                    stack.append((operand, inner))
            elif kind == 'if':
                for cond, block in node.clauses:
                    stack.append((cond, True))
                    stack.extend((stmt, False) for stmt in block)
                stack.extend((stmt, False) for stmt in node.orelse or ())
            elif kind in ('while', 'repeat'):
                stack.append((node.cond, True))
                stack.extend((stmt, False) for stmt in node.body)
            else:
                stack.extend((child, False) for child in _children(node))
        return receivers, creator_args, tested

    def confined(self, binding, values, receivers, names, tested, store=None):
        """True when no use of binding, a name that holds a singleton
        helper's object, can hand that object on (reviews F1, S5, S6).
        Allowed, and nothing else:

        - the base of an index read (X.f, X[k]) or of a field write with a
          literal key (X.f = v), which client_field examines; a write with a
          computed key through any of these names refuses the helper before
          this test (cached_singletons);
        - a value that is only tested or compared, in the exact places of
          singleton_places (tested): a condition, under not, a comparison
          operand, an and/or operand of an expression that is itself only
          tested or compared, through parentheses. An arithmetic or
          concatenation operand is refused: it hands the object to the other
          operand's metamethod;
        - the receiver of a method call X:name(...), unless this file gives
          one of the names holding the object a function for that field
          that can take an argument (loaded_method): the call would hand the
          object to loaded code as its first argument. That the method is
          otherwise the client's own is an assumption about the client, not
          proved (see loaded_method);
        - a use in values: for the cache its returns in the helper; for the
          helper's own local the store, its returns in the helper and an
          argument of a creator global (the client's function);
        - as an assignment target, only the store itself.

        Every other use is refused: the name as a plain value (stored in a
        field, a table or a global, returned by another function, passed to
        any function, aliased by a local, an operand that flows on) or as a
        callee. A name so used could give the object to a local that the
        object model takes for a separate object, and a conflicting write
        through that local would go unseen."""
        for use, node in binding.uses:
            if use in ('index', 'field-target'):
                continue
            if use == 'target':
                if node is store:
                    continue
                return False
            if use != 'value':
                return False
            if id(node) in values or id(node) in tested:
                continue
            method = receivers.get(id(node))
            if method is None or self.loaded_method(method, names):
                return False
        return True

    def loaded_method(self, name, names):
        """True when this file writes a field called name on one of names
        (the names holding a singleton helper's object) with anything but a
        function literal that takes no argument at all (_parameterless), or
        writes that field with an unknown value: X:name(...) could then run
        a function of the loaded source with the object as its argument.
        This looks only at this file's own writes on these names. Without
        such a write the method is ASSUMED to be the client's own; that is
        not proved (review S7). A function that loaded code or another addon
        adds to, or hooks on, the method table shared by the widgets of a
        type (reached for example through getmetatable of any widget) would
        be found by X:name(...) and would receive the object; nothing here
        sees that."""
        for value in self.field_writes.get(name, ()):
            if value is _OPAQUE:
                return True
            if _parameterless(value):
                continue
            base = self.field_bases[value][1]
            if type(base) is _Binding and self.alias_root(base) in names:
                return True
        return False

    def cached_singleton(self, func):
        """(the local holding the object, the creator global name, the cache
        binding, the store target, the holder bindings, and the ids of the
        value uses of the cache and of the object that belong to the shape)
        when func has the singleton cache shape, else None; cached_singletons
        then applies the use rule (confined). The shape is exact:

            if CACHE then return CACHE end
            local OBJECT = Creator(arguments)
            CACHE = OBJECT
            ...
            return OBJECT

        - func takes no parameter and no ...; its first three statements are
          exactly these, and its body ends with a return.
        - CACHE is a local of the file chunk (not of a function), declared
          without a value and assigned nowhere else, nested functions
          included: its one and only definition is this store. A declaration
          with a value is refused, nil included (review S4): with 'local
          CACHE = nil' the name has two definitions, so the object model
          does not track it, and an alias of it (local g = CACHE) would be a
          separate object although it is the same frame, hiding a
          conflicting write. With the store as its single definition CACHE
          and every alias of it hold OBJECT's origins.
        - OBJECT is a local of func declared with a call of a _WIDGET_FUNCTIONS
          global by its plain name, and it is never assigned again. Every
          argument of that call is a literal (string, number, nil, true,
          false) or a plain name. An index, an operator, a parenthesized
          expression, a constructor, ..., a call or a function is refused: a
          field read, a concatenation or an arithmetic operand can run a
          metamethod of the loaded source between the guard and the store,
          which could call the helper again and make a second object
          (review S1). A plain name runs no code: a local is a slot, and a
          global read meets a metatable only when the environment table was
          given one, which needs the environment as a value and so opens it
          (the linker then refuses the creator global).
        - Every return statement of func itself returns exactly one value,
          the name CACHE or the name OBJECT: no other object, no scalar, no
          nil, no missing value.
        - Every use of the helper's own name, anywhere in the file, is the
          callee of a call that is the one declared value of a local declared
          once and never assigned again (local HOLDER = Helper()), and that
          name is never assigned. Any other use refuses the helper as a
          whole: an alias, a parenthesized call, a call returned, passed on,
          assigned or discarded, pcall (review S2). A result held any other
          way would be a separate object in the object model although it is
          the same frame, so a conflicting write through it would go unseen;
          with this rule every result of the helper is held by a local that
          _Linker.widened merges.
        - No name that holds the object hands it on (review F1; checked by
          cached_singletons with confined): CACHE, OBJECT and every HOLDER
          are used only as the base of an index read or of a field write
          with a literal key, as the receiver of a method the file does not
          itself define on them, as a value that is only tested or compared
          (the exact places are in singleton_places), and in the shape
          itself (the guard, the store, the helper's returns; OBJECT also as
          an argument of the creator). A write with a computed key through
          one of these names (review S5), an arithmetic or concatenation
          operand or an and/or expression used as a value (review S6), a
          holder returned by another function, stored in a field, a table
          or a global, passed to a function or aliased refuse the helper as
          a whole, and so does the cache returned or aliased anywhere else.

        Then an invocation that finds CACHE set returns it, the one that
        finds it unset makes the object and stores it before any code of the
        loaded source runs, and nothing unsets or replaces it: every value
        func returns is that one object, and within the loaded source only
        CACHE, OBJECT and the holders can name it. Three things are assumed
        about the client and are not proved (the routes named are examples,
        not a complete list): that the creator, the client's own function,
        runs no loaded code (for example a frame template with load scripts
        or a hook on the creator); that the client does not hand the object
        back to loaded code by another route (for example a script
        handler's self, the global name of a named frame, GetParent); and
        that the methods called on these names are the client's own, neither
        added to nor hooked on the method table shared by the widgets of a
        type, by loaded code or by another addon (review S7). The linker
        requires that no loaded source assigns the
        creator global (_Linker.widened). OBJECT may be read by nested
        functions (a script handler) within these uses; that changes no
        identity. Any other helper proves nothing here."""
        if func.params or func.vararg or func.method or len(func.body) < 4:
            return None
        guard, made, stored = func.body[:3]
        if guard.kind != 'if' or len(guard.clauses) != 1 or guard.orelse is not None:
            return None
        cond, inner = guard.clauses[0]
        if cond.kind != 'name' or cond.binding is None or len(inner) != 1 \
                or inner[0].kind != 'return' or len(inner[0].exprs) != 1:
            return None
        cache, back = cond.binding, inner[0].exprs[0]
        if back.kind != 'name' or back.binding is not cache:
            return None
        if made.kind != 'local' or len(made.names) != 1 or len(made.exprs) != 1:
            return None
        owned, creator = made.names[0].binding, made.exprs[0]
        if creator.kind != 'call' or creator.func.kind != 'name' \
                or creator.func.binding is not None \
                or creator.func.value not in _WIDGET_FUNCTIONS \
                or not all(arg.kind in ('string', 'name')
                           or (arg.kind == 'constant' and arg.value != '...')
                           for arg in creator.args):
            return None
        if stored.kind != 'assign' or len(stored.targets) != 1 or len(stored.exprs) != 1:
            return None
        target, value = stored.targets[0], stored.exprs[0]
        if target.kind != 'name' or target.binding is not cache \
                or value.kind != 'name' or value.binding is not owned:
            return None
        if cache.kind != 'local' or cache not in self.made_in or self.made_in[cache] is not None:
            return None
        # The store is the cache's single definition: a valueless declaration
        # records none, any initializer (nil included) is a second one (S4).
        if self.defs.get(cache) != [value]:
            return None
        if owned.assigned or self.defs.get(owned) != [creator]:
            return None
        if func.body[-1].kind != 'return':
            return None
        for stmt in _descendants(func.body):
            if stmt.kind == 'return' and (
                    len(stmt.exprs) != 1 or stmt.exprs[0].kind != 'name'
                    or (stmt.exprs[0].binding is not cache
                        and stmt.exprs[0].binding is not owned)):
                return None
        # Every use of the helper's name is the callee of a direct call that
        # is the one declared value of a once-declared local (review S2).
        helper = self.function_binding.get(func)
        calls = self.direct_calls.get(func, ())
        if helper is None or helper.value is not func or helper.assigned \
                or len(helper.uses) != len(calls):
            return None
        holders = []
        for call in calls:
            defined = self.def_of.get(call, ())
            if len(defined) != 1 or call not in self.declared:
                return None
            holder = defined[0]
            if type(holder) is not _Binding or holder.kind != 'local' or holder.assigned \
                    or self.defs.get(holder) != [call]:
                return None
            holders.append(holder)
        # The value uses that belong to the shape itself (see confined).
        returned = [stmt.exprs[0] for stmt in _descendants(func.body) if stmt.kind == 'return']
        cache_values = frozenset(id(node) for node in returned if node.binding is cache)
        owned_values = frozenset([id(value)] + [id(node) for node in returned
                                                if node.binding is owned])
        return owned, creator.func.value, cache, target, holders, cache_values, owned_values

    def module_ok(self, binding, depth=0):
        """A local module table (or alias of one) whose identity stays here:
        never assigned again, never written through a computed key, and used
        only through literal fields, by its Nexus export, as a value the
        file chunk returns (discarded by the TOC loader), as the table of a
        lazy-field metatable statement (metatable_hook) or by a local alias
        with the same properties. A function of this flow alone, so each
        top-level answer is kept with it (module_ok_memo)."""
        if depth == 0:
            if binding not in self.module_ok_memo:
                self.module_ok_memo[binding] = self.module_ok_at(binding, 0)
            return self.module_ok_memo[binding]
        return self.module_ok_at(binding, depth)

    def module_ok_at(self, binding, depth):
        """module_ok at one alias depth, without its memo."""
        if depth > 16 or binding.kind != 'local' or binding.assigned \
                or binding in self.dynamic_modules:
            return False
        for use, node in binding.uses:
            if use in ('index', 'field-target'):
                continue
            alias = self.alias_of.get(node) if use == 'value' else None
            if use == 'value' and (node in self.export_values or node in self.chunk_returns
                                   or node in self.metatable_args or (
                    alias is not None and self.module_ok(alias, depth + 1))):
                continue
            return False
        return True

    def metatable_hooked(self, binding, depth=0):
        """True when this module table (or a local alias of it) is the table
        of a lazy-field metatable statement here."""
        if depth > 16:
            return False
        for use, node in binding.uses:
            if use == 'value' and node in self.metatable_args:
                return True
            alias = self.alias_of.get(node) if use == 'value' else None
            if alias is not None and self.metatable_hooked(alias, depth + 1):
                return True
        return False

    def block(self, body, func):
        for stmt in body:
            self.statement(stmt, func)

    def statement(self, stmt, func):
        kind = stmt.kind
        if kind == 'local':
            for expr in stmt.exprs:
                self.expr(expr, func)
            for index, name in enumerate(stmt.names):
                self.made_in[name.binding] = func
                if index < len(stmt.exprs):
                    value = stmt.exprs[index]
                    self.define(name.binding, value)
                    self.declared.add(value)
                    if value.kind == 'name' and value.binding is not None:
                        self.alias_of[value] = name.binding
                elif stmt.exprs:
                    self.define(name.binding, _OPAQUE)
        elif kind == 'localfunction':
            self.function(stmt.func)
        elif kind == 'funcstat' and stmt.method is not None:
            # function base:name() writes the field name of base.
            self.function(stmt.func)
            self.library_write(stmt.target, stmt.method)
            self.base(stmt.target, func)
            self.def_statement[stmt.func] = stmt
            base = stmt.target.binding if stmt.target.kind == 'name' else None
            self.write_field(stmt.method, stmt.func, base)
            if base is not None:
                fields = self.module_defs.setdefault(_module_root(base), {})
                fields.setdefault(stmt.method, []).append(stmt.func)
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
                if value is not _OPAQUE:
                    self.def_statement[value] = stmt
                self.target_statement[target] = stmt
                self.target(target, value, func)
        elif kind == 'callstat':
            self.truth_only.add(stmt.call)      # its results are discarded
            self.expr(stmt.call, func)
            hooked = _metatable_hook(stmt.call)
            if hooked is not None:
                self.metatable_args.add(hooked)
        elif kind == 'return':
            for expr in stmt.exprs:
                self.expr(expr, func)
            if func is not None and stmt.exprs:
                self.edge(stmt.exprs[0], ('ret', func))
                # Each later expression into its own return position, never
                # into another: an expression gives one value there (a call
                # its first result). Only a call in the last position gives
                # more; its later results are followed on demand, position
                # by position (tail_calls, _Linker.result_states).
                for index in range(1, min(len(stmt.exprs), _RESULT_LIMIT)):
                    self.edge(stmt.exprs[index], ('ret', func, index))
                if stmt.exprs[-1].kind == 'call':
                    self.tail_calls[stmt.exprs[-1]] = (func, len(stmt.exprs) - 1)
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
            # A condition is only tested: its value never leaves.
            if kind == 'if':
                self.truth_only.update(cond for cond, _ in stmt.clauses)
            elif kind != 'do':
                self.truth_only.add(stmt.cond)
            for child in _children(stmt):
                if child.kind not in _STATEMENTS:
                    self.expr(child, func)
            for body in _bodies(stmt):
                self.block(body, func)

    # -- the global environment and the string library (V15 review fix) -----

    def global_value(self, node, name):
        """A global (by name or as _G.name) read as a value: the environment
        table or an environment opener opens the environment, and the string
        library table itself escapes (any field may be written through it).
        Only tested or compared (truth_only, as in _G and _G.X), it never
        leaves; given only to type() (as in type(debug)), it leaves only to
        type, so it escapes only when the loaded source assigns type
        (type_escapes, decided by the linker)."""
        if node in self.truth_only:
            return
        if node in self.type_args:
            if name == _ENV or name in _ENV_OPENERS or name == _STRING:
                self.type_escapes.append(node)
            return
        if name == _ENV or name in _ENV_OPENERS:
            self.env_escapes.append(node)
        elif name == _STRING:
            self.library_writes.add('*')

    def base(self, node, func, target=False):
        """The table expression of a field read or write: a field of the
        environment or the string library is no escape of that table. A
        write target's local name is no read (as before)."""
        ref = _global_ref(node)
        if ref == _ENV or ref == _STRING:
            return
        if target and node.kind == 'name':
            if node.binding is None:
                self.global_value(node, node.value)
            return
        self.expr(node, func)

    def library_write(self, table, key):
        """A write of field key (None: a computed key) of table: through _G
        it writes that global (a computed key may write any global), on the
        string library that library field."""
        ref = _global_ref(table)
        if ref == _ENV:
            if key is None:
                self.env_escapes.append(table)
            else:
                self.global_writes.add(key)
        elif ref == _STRING:
            self.library_writes.add('*' if key is None else key)

    def check_env_reads(self, body):
        """Each computed _G[k] read whose key is not static (STD-8849-2) is
        harmless only when its key is proved to name no tracked global
        (_EnvContext.excluded), or when the unknown global it reads is
        contained: only tested, compared or given to type(); a field read
        of it whose value is itself only tested, compared or given to
        type(); or the receiver of a method call, V:m(...) or pcall(V.m, V,
        ...), with an untracked m, or an argument of a method call on any
        object, X:m(..., V) or pcall(X.m, X, ..., V). A local holding it must
        be used only those ways. Anything else (a write through it, passing
        it to a function, storing or returning it, calling it) opens the
        environment (env_escapes). The globals the proof relies on (type,
        pairs, ipairs, pcall) and both kinds of method name are left for the
        linker to check (_Linker.env_read_refuted)."""
        self.env_contexts, self.env_chunk = {}, body
        for read, func in self.env_reads:
            context = self.env_context(func)
            deps, methods = set(), (set(), set())
            if context.excluded(read.key, self.truth_only, deps) \
                    or self.env_contained(read, context, deps, methods, set(), 0):
                if deps or methods[0] or methods[1]:
                    self.env_read_conditions.append((read, frozenset(deps),
                                                     frozenset(methods[0]),
                                                     frozenset(methods[1])))
                continue
            self.env_escapes.append(read)

    def env_context(self, func):
        """The _EnvContext of a function body (None: the file chunk)."""
        if func not in self.env_contexts:
            self.env_contexts[func] = _EnvContext(func.body if func is not None
                                                  else self.env_chunk)
        return self.env_contexts[func]

    def env_tested(self, node, context, deps):
        """True when a value is only tested, compared or given to type()."""
        if node in self.truth_only:
            return True
        if node in self.type_args:
            deps.add('type')
            return True
        parent = context.parent.get(id(node))
        return parent is not None and parent.kind == 'paren' and self.env_tested(parent, context,
                                                                                 deps)

    def env_contained(self, node, context, deps, methods, seen, depth):
        """The containment rule of check_env_reads for one occurrence."""
        if depth > 16:
            return False
        if self.env_tested(node, context, deps):
            return True
        parent = context.parent.get(id(node))
        if parent is None:
            return False
        kind = parent.kind
        if kind == 'paren':
            return self.env_contained(parent, context, deps, methods, seen, depth + 1)
        if kind == 'operation':
            if any(operand is node for operand in _flowing_operands(parent)):
                return self.env_contained(parent, context, deps, methods, seen, depth + 1)
            return True     # an operand whose value is not the result
        if kind == 'index' and parent.obj is node:
            name = _static_string(parent.key)
            return not context.written(node) and name is not None \
                and name not in _ENV_TRACKED and self.env_tested(parent, context, deps)
        if kind == 'method' and parent.name not in _ENV_TRACKED:
            if parent.obj is node:
                methods[0].add(parent.name)
                return True
            if any(arg is node for arg in parent.args):
                methods[1].add(parent.name)
                return True
            return False
        if kind == 'call' and parent.func.kind == 'name' and parent.func.binding is None \
                and parent.func.value == 'pcall' and len(parent.args) >= 2 \
                and any(arg is node for arg in parent.args[1:]):
            # pcall(X.m, X, ...): a method call of X, V its receiver or argument.
            method, receiver = parent.args[0], parent.args[1]
            name = _static_string(method.key) if method.kind == 'index' else None
            if method.kind != 'index' or method.obj.kind != 'name' or receiver.kind != 'name' \
                    or method.obj.binding is None or method.obj.binding is not receiver.binding \
                    or name is None or name in _ENV_TRACKED:
                return False
            deps.add('pcall')
            methods[0 if receiver is node else 1].add(name)
            return True
        target = _local_function(parent.func) if kind == 'call' else None
        if target is not None:
            # An argument of a resolved local function: contained when the
            # parameter it fills is (a value no parameter takes is dropped).
            index = next((i for i, arg in enumerate(parent.args) if arg is node), None)
            if index is None:
                return False
            if index >= len(target.params):
                return not target.vararg
            return self.env_holder_contained(target.params[index].binding,
                                             self.env_context(target), deps, methods, seen,
                                             depth + 1)
        if kind in ('local', 'assign'):
            values = parent.exprs
            index = next((i for i, value in enumerate(values) if value is node), None)
            names = parent.names if kind == 'local' else parent.targets
            if index is None:
                return False
            if index >= len(names):
                return True     # a value no name receives
            target = names[index]
            binding = target.binding if target.kind == 'name' else None
            if binding is None or binding.kind != 'local':
                return False    # stored in a global or a field
            return self.env_holder_contained(binding, context, deps, methods, seen, depth)
        return False

    def env_holder_contained(self, binding, context, deps, methods, seen, depth):
        """Every use of a local holding the unknown global is contained."""
        if binding is None:
            return False
        if binding in seen:
            return True
        seen.add(binding)
        for use, node in binding.uses:
            if use == 'target':
                continue        # another definition of the local
            if use == 'index' and not context.written(node):
                parent = context.parent.get(id(node))
                if parent is not None and parent.kind == 'index' and parent.obj is node:
                    holder = context.parent.get(id(parent))
                    # pcall(V.m, V): the method read is its first argument.
                    if holder is not None and holder.kind == 'call' and holder.args \
                            and holder.args[0] is parent and len(holder.args) >= 2 \
                            and holder.args[1].kind == 'name' \
                            and holder.args[1].binding is binding:
                        if self.env_contained(holder.args[1], context, deps, methods, seen,
                                              depth + 1):
                            continue
                        return False
                if self.env_contained(node, context, deps, methods, seen, depth + 1):
                    continue
                return False
            if use == 'value' and self.env_contained(node, context, deps, methods, seen,
                                                     depth + 1):
                continue
            return False
        return True

    def metatable_contained(self):
        """Record each getmetatable call whose result may leave: neither
        only tested or compared (truth_only) nor held by an unassigned local
        that is itself only tested or compared."""
        for call in self.getmetatable_calls:
            if call in self.truth_only:
                continue
            holders = self.def_of.get(call, ())
            if len(holders) == 1 and type(holders[0]) is _Binding \
                    and holders[0].kind == 'local' and not holders[0].assigned \
                    and len(self.defs.get(holders[0], ())) == 1 \
                    and all(use == 'value' and node in self.truth_only
                            for use, node in holders[0].uses):
                continue
            self.metatable_escapes.append(call)

    def target(self, target, value, func):
        if target.kind == 'name':
            if target.binding is not None:
                self.define(target.binding, value)
            else:
                self.global_writes.add(target.value)
                if _path(target) is not None and value is not _OPAQUE and value.kind == 'name':
                    self.export_values.add(value)
            return
        self.library_write(target.obj, _static_string(target.key))
        self.base(target.obj, func, target=True)
        self.expr(target.key, func)
        base = target.obj.binding if target.obj.kind == 'name' else None
        if target.key.kind != 'string' or target.key.value is None:
            if base is not None:
                self.dynamic_modules.add(_module_root(base))
            return
        self.write_field(target.key.value, value, base)
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
            else:
                self.global_value(node, node.value)
        elif kind == 'index':
            # A read of debug.traceback leaves the debug library unopened. A
            # computed _G[k] read whose key is not static is checked after the
            # walk (check_env_reads, STD-8849-2).
            if not (_global_ref(node.obj) == 'debug'
                    and _static_string(node.key) in _DEBUG_READS):
                self.base(node.obj, func)
            self.expr(node.key, func)
            ref = _global_ref(node)
            if ref is not None:
                self.global_value(node, ref)
            elif _global_ref(node.obj) == _ENV:
                self.env_reads.append((node, func))
            if node.key.kind == 'string' and node.key.value is not None:
                base = node.obj.binding if node.obj.kind == 'name' else None
                self.field_reads.setdefault(node.key.value, []).append((node, base))
        elif kind == 'paren':
            if node in self.truth_only:
                self.truth_only.add(node.expr)
            self.expr(node.expr, func)
            self.edge(node.expr, node)
        elif kind == 'operation':
            flowing = _flowing_operands(node)
            tested = node in self.truth_only
            kept = {id(operand) for operand in flowing}
            self.truth_only.update(operand for operand in node.operands
                                   if tested or id(operand) not in kept)
            for operand in node.operands:
                self.expr(operand, func)
            for operand in flowing:
                self.edge(operand, node)
        elif kind == 'call':
            self.call(node, func)
        elif kind == 'method':
            self.expr(node.obj, func)
            for arg in node.args:
                self.expr(arg, func)
            if node.name in _SINK_METHODS and node.args:
                self.edge(node.args[0], ('sink', node))
                self.sinks[node] = node.obj
            if node.name in _TEXT_METHODS:
                self.transform(':' + node.name, node.obj, node)
                if node.name == 'format':
                    self.format_arguments(':format', node.obj, node.args, node)
        elif kind == 'function':
            self.function(node)
        elif kind == 'table':
            self.made_in[node] = func
            for field in node.fields:
                if field.key is not None:
                    self.expr(field.key, func)
                self.expr(field.value, func)
                if field.key is not None and field.key.kind == 'string' \
                        and field.key.value is not None:
                    self.write_field(field.key.value, field.value, node)

    def transform(self, implementation, source, node):
        self.edge(source, node)
        self.library_edges.append((implementation, source, node))

    def format_arguments(self, implementation, fmt, args, node):
        """The edges of the arguments after a format that it shows as text
        (_format_consumed); none when that is not proved (STD-V15-1,
        STD-8849-1)."""
        consumed = _format_consumed(fmt, args)
        for position, arg in enumerate(args, 1):
            if consumed is not None and position in consumed:
                self.transform(implementation, arg, node)

    def pass_args(self, target, args, call):
        """Arguments of one call of a local function, by parameter position;
        the linker returns a value that entered here only to this call."""
        for param, arg in zip(target.params, args):
            self.call_args.setdefault(arg, []).append((param.binding, call))
            self.param_args.setdefault(param.binding, []).append(arg)

    def raw_global_read(self, callee, args):
        """True for rawget(_G, key) when it is the read of one ordinary global
        and nothing more, so its environment argument is no escape of the
        environment: the callee is the global name rawget itself (a local of
        that name, a parameter or an alias has a binding and is never this
        form), there are exactly two arguments, the first is the global name
        _G itself (not a local holding it, a field or a parenthesized form)
        and the second is a static string (_static_string) that names no
        tracked global (_ENV_TRACKED: the environment, the string library,
        Nexus, the trusted functions and client roots, the environment
        openers and the debug functions). The read then equals the static
        field read _G.key, which is no escape either (global_value), without
        its metamethods; its result is an opaque call result here, so no text
        and no field value flows through it.
        The proof holds only while rawget stays the builtin in every loaded
        unit. That is a linker condition, recorded like those of a computed
        _G[k] read (env_read_conditions, read by _Linker.env_read_refuted):
        once any loaded source assigns the global rawget, by name or through
        _G, the environment argument is an escape again and is reported at
        its own position. Every other form is left to the ordinary walk, so
        its _G argument opens the environment as before."""
        if not (callee.kind == 'name' and callee.binding is None and callee.value == 'rawget'
                and len(args) == 2 and args[0].kind == 'name' and args[0].binding is None
                and args[0].value == _ENV):
            return False
        key = _static_string(args[1])
        if key is None or key in _ENV_TRACKED:
            return False
        if not any(row[0] is args[0] for row in self.env_read_conditions):
            self.env_read_conditions.append((args[0], frozenset(('rawget',)), frozenset(),
                                             frozenset()))
        return True

    def call(self, node, func):
        callee, args = node.func, node.args
        self.expr(callee, func)
        if callee.kind == 'name' and callee.binding is None and callee.value == 'type' \
                and len(args) == 1:
            self.type_args.add(args[0])
        # rawget(_G, "name"): the environment argument is not walked as a
        # value (raw_global_read); the key and every other call are as before.
        raw_read = self.raw_global_read(callee, args)
        for position, arg in enumerate(args):
            if raw_read and position == 0:
                continue
            self.expr(arg, func)
        if callee.kind == 'name' and callee.binding is None and callee.value == 'getmetatable':
            self.getmetatable_calls.append(node)
        if callee.kind == 'name' and callee.binding is None and callee.value in _SINK_FUNCTIONS:
            for arg in args:
                self.edge(arg, ('sink', node))
            self.sinks[node] = None
        library = _library_name(callee)
        if library in _TEXT_CALLS:
            for position in _TEXT_CALLS[library]:
                if position < len(args):
                    self.transform(library, args[position], node)
            if library == 'string.format' and args:
                self.format_arguments(library, args[0], args[1:], node)
        target = _local_function(callee)
        if target is not None:
            self.edge(('ret', target), node)
            self.direct_calls.setdefault(target, set()).add(node)
            self.function_binding[target] = callee.binding
            self.pass_args(target, args, node)
        elif callee.kind == 'name' and callee.binding is None and callee.value == 'pcall' \
                and args and _local_function(args[0]) is not None:
            # pcall(f, ...) passes its remaining arguments to f; its own
            # first result is a status, so f's result does not come back here.
            target = _local_function(args[0])
            self.pcall_calls.setdefault(target, set()).add(node)
            self.function_binding[target] = args[0].binding
            self.pass_args(target, args[1:], node)
        if callee.kind == 'index' and callee.obj.kind == 'name' and callee.obj.binding \
                is not None and callee.key.kind == 'string':
            self.module_calls.append((_module_root(callee.obj.binding), callee.key.value,
                                      node))
        path = _path(callee)
        if path is not None:
            self.path_calls.setdefault(path, []).append(node)

    def call_arguments(self, func, call):
        """The arguments a resolved call or pcall passes to func's
        parameters, or None when call is no such call of func."""
        if call in self.direct_calls.get(func, ()):
            return call.args
        if call in self.pcall_calls.get(func, ()):
            return call.args[1:]
        return None

    def calls_resolved(self, func):
        """Every call of func when each use of its local name is one of its
        resolved direct calls or pcall arguments, else None (it escapes)."""
        binding = self.function_binding.get(func)
        calls = list(self.direct_calls.get(func, ())) + list(self.pcall_calls.get(func, ()))
        if binding is None or binding.assigned or len(binding.uses) != len(calls):
            return None
        return calls


_NIL_DEF = object()     # the value a local holds before any definition reaches it


class _ReachingDefinitions:
    """Flow-sensitive reaching definitions (Source25 continuation) for the
    locals that only their own function body assigns and reads: for each read
    of such a local, the definitions (local declaration values and later
    assignment values) that may still hold when the read runs. Lua 5.1 has
    only structured control flow: the branches of an if join; a while, for
    or repeat body may run again (iterated to a fixpoint) or not at all (a
    repeat body runs at least once); return ends its path, break leaves its
    loop; an assignment replaces the local's definitions on its path. A
    definition killed on every path to a read does not reach it, so an
    overwritten result is never followed there. Locals that a nested
    function assigns or reads keep the flow-insensitive every-definition
    rule of _UnitFlow. A for variable and a value-less declaration hold no
    followed value. A multiple-value position without its own expression
    holds the result node of the call that is the last expression of its
    list (_UnitFlow.later_result, given as later), which the linker reaches
    only for that position of a resolved function; without such a call it
    holds no followed value."""

    def __init__(self, eligible, later=None):
        self.eligible = eligible
        self.later_result = later
        self.reach = {}

    def later(self, exprs, index, binding):
        """The definition a name without its own expression gets at index
        of a non-empty expression list: the result node of a last call for
        an eligible local, else no followed value."""
        if self.later_result is None or binding not in self.eligible:
            return _OPAQUE
        node = self.later_result(exprs, index)
        return _OPAQUE if node is None else node

    def run(self, func_body):
        self.block(func_body, {})

    def uses(self, expr, env):
        stack = [expr]
        while stack:
            node = stack.pop()
            if node.kind == 'function':
                continue        # a nested function is its own pass
            if node.kind == 'name' and node.binding in self.eligible:
                self.reach.setdefault(node, set()).update(env.get(node.binding, ()))
            stack.extend(_children(node))

    @staticmethod
    def join(envs):
        envs = [env for env in envs if env is not None]
        if not envs:
            return None
        out = {}
        for env in envs:
            for binding, values in env.items():
                out[binding] = out.get(binding, frozenset()) | values
        return out

    def block(self, body, env):
        """(env after the block, or None when every path leaves it; [env at
        each break])."""
        breaks = []
        for stmt in body:
            if env is None:
                break
            env, more = self.statement(stmt, env)
            breaks.extend(more)
        return env, breaks

    def assign(self, env, binding, value):
        # env is owned by the current straight-line path: branches and loop
        # bodies receive their own copies (statement, loop).
        if binding in self.eligible:
            env[binding] = frozenset((value,))
        return env

    def loop(self, env, body, cond=None, at_least_once=False):
        """The env after a loop and its body's breaks: the body is iterated
        from the union of the entry and every iteration's end."""
        entry, breaks, end = env, [], None
        while True:
            if cond is not None and not at_least_once:
                self.uses(cond, entry)
            end, more = self.block(body, dict(entry))
            breaks = more
            if cond is not None and at_least_once and end is not None:
                self.uses(cond, end)
            grown = self.join([entry, end])
            if grown == entry:
                break
            entry = grown
        exits = [end] if at_least_once else [entry]
        return self.join(exits + breaks), []

    def statement(self, stmt, env):
        kind = stmt.kind
        if kind == 'local':
            for expr in stmt.exprs:
                self.uses(expr, env)
            for index, name in enumerate(stmt.names):
                value = stmt.exprs[index] if index < len(stmt.exprs) else (
                    self.later(stmt.exprs, index, name.binding) if stmt.exprs else _NIL_DEF)
                env = self.assign(env, name.binding, value)
            return env, []
        if kind in ('localfunction', 'funcstat'):
            if kind == 'funcstat' and stmt.target.kind == 'name' and stmt.method is None:
                env = self.assign(env, stmt.target.binding, stmt.func)
            elif kind == 'funcstat':
                self.uses(stmt.target, env)
            return env, []
        if kind == 'assign':
            for expr in stmt.exprs:
                self.uses(expr, env)
            for target in stmt.targets:
                if target.kind != 'name':
                    self.uses(target, env)
            for index, target in enumerate(stmt.targets):
                if target.kind == 'name':
                    value = stmt.exprs[index] if index < len(stmt.exprs) \
                        else self.later(stmt.exprs, index, target.binding)
                    env = self.assign(env, target.binding, value)
            return env, []
        if kind == 'callstat':
            self.uses(stmt.call, env)
            return env, []
        if kind == 'return':
            for expr in stmt.exprs:
                self.uses(expr, env)
            return None, []
        if kind == 'break':
            return None, [dict(env)]
        if kind == 'do':
            return self.block(stmt.body, env)
        if kind == 'if':
            outs, breaks = [], []
            for cond, body in stmt.clauses:
                self.uses(cond, env)
                out, more = self.block(body, dict(env))
                outs.append(out)
                breaks.extend(more)
            if stmt.orelse is not None:
                out, more = self.block(stmt.orelse, dict(env))
                outs.append(out)
                breaks.extend(more)
            else:
                outs.append(env)
            return self.join(outs), breaks
        if kind == 'while':
            return self.loop(env, stmt.body, stmt.cond)
        if kind == 'repeat':
            return self.loop(env, stmt.body, stmt.cond, at_least_once=True)
        if kind == 'fornum':
            for expr in (stmt.start, stmt.stop, stmt.step):
                if expr is not None:
                    self.uses(expr, env)
            return self.loop(env, stmt.body)
        if kind == 'forin':
            for expr in stmt.exprs:
                self.uses(expr, env)
            return self.loop(env, stmt.body)
        return env, []


def _owner_functions(body):
    """{id(name node): the function node whose own body holds it (None: the
    file chunk)} for every name node of the file."""
    owners, stack = {}, [(node, None) for node in body]
    while stack:
        node, func = stack.pop()
        if node.kind == 'name':
            owners[id(node)] = func
        inner = node if node.kind == 'function' else func
        if node.kind == 'localfunction':
            stack.append((node.func, func))
            continue
        if node.kind == 'funcstat':
            stack.append((node.target, func))
            stack.append((node.func, func))
            continue
        if node.kind == 'function':
            for param in node.params:
                owners[id(param)] = node
        stack.extend((child, inner) for child in _children(node))
    return owners


class _Unit:
    """One loaded Lua source and its memoized parse, scan and flow graph."""

    def __init__(self, path, data, order, fresh):
        self.path, self.data, self.order = path, data, order
        self.body, self.error, self.leads, self.scan, self.flow = _parsed(data, fresh)


# Parsed files memoized by the SHA-256 of their exact bytes, the least
# recently used dropped first, at most _PARSE_MEMO_LIMIT files and
# _PARSE_MEMO_BYTES source bytes (a parse holds about one tracked object per
# two source bytes, so the bound keeps the hot files of a repository while a
# one-off edited copy leaves). A parse, its scan and its flow graph depend only on those bytes,
# and linking changes none of them (it only fills the flow's object-origin
# and module_ok memos, themselves functions of the same bytes), so a
# memoized parse is the same parse; nothing is read or written. Two equal
# files of one call get separate parses (fresh), so their local names stay
# distinct.
import gc

_PARSE_MEMO = {}
_PARSE_MEMO_SIZES = {}
_PARSE_MEMO_LIMIT = 256
_PARSE_MEMO_BYTES = 16 * 1024 * 1024


def _parse_bytes(data):
    """The uncached _parsed result of the exact bytes of one Lua file."""
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        return None, {'code': 'not-utf8'}, {}, None, None
    try:
        tokens = _lua_tokens(text)
        body = _LuaParser(tokens).chunk()
        resolver = _Resolver()
        resolver.block(body, [])
        scan = _UnitScan(body, resolver.localfunctions, resolver.forins)
        flow = _UnitFlow(body, resolver.owners, resolver.functions)
    except CatalogSyntaxError as error:
        return None, {'code': error.code, 'line': error.line, 'column': error.column}, {}, \
            None, None
    except RecursionError:
        return None, {'code': 'nesting-too-deep'}, {}, None, None
    # {string value: [(line, column) of each literal with it, in order]}
    leads = {}
    for token in tokens:
        if token.kind == 'string':
            leads.setdefault(token.value, []).append((token.line, token.column))
    return body, None, leads, scan, flow


def _parsed(data, fresh=False):
    """(syntax tree or None, error or None, string literals as (value, line,
    column), scan, flow) of the exact bytes of one Lua file."""
    digest = _digest(data)
    if digest in _PARSE_MEMO and not fresh:
        _PARSE_MEMO[digest] = _PARSE_MEMO.pop(digest)     # most recently used last
        return _PARSE_MEMO[digest]
    # Building one tree allocates hundreds of thousands of acyclic objects;
    # the cyclic collector would rescan every memoized tree meanwhile. It is
    # paused only for this build and always restored as it was. No result
    # depends on it, and reference counting still frees memory.
    collecting = gc.isenabled()
    gc.disable()
    try:
        result = _parse_bytes(data)
    finally:
        if collecting:
            gc.enable()
    if digest in _PARSE_MEMO:     # a fresh parse of the same bytes replaces it
        del _PARSE_MEMO[digest], _PARSE_MEMO_SIZES[digest]
    if len(data) > _PARSE_MEMO_BYTES:
        return result               # larger than the whole bound: never kept (STD-V15-3)
    while _PARSE_MEMO and (len(_PARSE_MEMO) >= _PARSE_MEMO_LIMIT
                           or sum(_PARSE_MEMO_SIZES.values()) + len(data) > _PARSE_MEMO_BYTES):
        oldest = next(iter(_PARSE_MEMO))
        del _PARSE_MEMO[oldest], _PARSE_MEMO_SIZES[oldest]
    _PARSE_MEMO[digest] = result
    _PARSE_MEMO_SIZES[digest] = len(data)
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
        # field_cache, receiver_memo and output_memo must stay write-once:
        # an entry, once final, is never changed or dropped (receiver_memo
        # holds a provisional False only while that entry is computed), and
        # search must never run inside such a computation. prove relies on
        # both when it uses one single-root search for several keys; C36
        # compares its receipt with a forced single_root_replay. ret_links
        # is written in this constructor only.
        self.field_cache, self.ret_links, self.receiver_memo = {}, {}, {}
        self.output_memo = {}
        # {Nexus path assignment target: its load point (unit order,
        # top-level statement index)} for the targets established at load.
        self.path_points = {target: (unit.order,) + point for unit in self.units
                            for target, point in unit.flow.path_points.items()
                            if point is not None}
        # Diagnostic switch for an external equivalence control only (no seam
        # sets it): replay a single root's search as for several roots.
        self.single_root_replay = False
        # The global environment (V15 review fix): once a loaded source may
        # write any global (env_escapes), every global name counts as
        # assigned, so no trusted global, sink, client root or library stays
        # established.
        writes, self.library_writes = set(), set()
        self.env_open = self.string_meta_open = False
        typed = False
        conditions = []
        for unit in self.units:
            conditions.extend((unit, condition) for condition in unit.flow.env_read_conditions)
            writes |= unit.flow.global_writes
            self.library_writes |= unit.flow.library_writes
            self.env_open = self.env_open or bool(unit.flow.env_escapes)
            self.string_meta_open = self.string_meta_open or bool(unit.flow.metatable_escapes)
            typed = typed or bool(unit.flow.type_escapes)
        self.type_open = typed and 'type' in writes
        # A computed _G[k] read proved harmless only while these globals stay
        # unassigned and no loaded source defines its method names
        # (STD-8849-2); a refuted one opens the environment like any other.
        self.env_read_escapes = [(unit, condition[0]) for unit, condition in conditions
                                 if self.env_read_refuted(writes, *condition[1:])]
        self.env_open = self.env_open or self.type_open or bool(self.env_read_escapes)
        self.global_writes = _ANY_NAME if self.env_open else writes
        # Transform edges whose implementation the loaded source may replace
        # are not followed (the memoized flow itself is never changed).
        self.blocked = {}
        for unit in self.units:
            dropped = {(arg, call) for name, arg, call in unit.flow.library_edges
                       if not self.trusted(name)}
            if dropped:
                self.blocked[id(unit.flow)] = dropped
        # {('pret', path): the load point after which that exported function
        # is defined}: a call in chunk code that runs before it never reaches
        # its result.
        self.pret_points = {}
        for unit in self.units:
            flow = unit.flow
            exports = {}
            for path, module in flow.exports:
                exports.setdefault(module, []).append(path)
            for module, name, call in flow.module_calls:
                func, _, point = self.module_function(flow, module, name,
                                                      exports.get(module, ()))
                if func is not None and not self.runs_before(unit, call, point):
                    self.ret_links.setdefault(func, []).append((call, flow))
            for module, paths in exports.items():
                for (owner, name), _ in flow.module_funcs.items():
                    if owner is not module:
                        continue
                    func, _, point = self.module_function(flow, module, name, paths)
                    if func is not None:
                        for path in paths:
                            key = ('pret', path + '.' + name)
                            self.pret_points[key] = max(point, self.export_point(path))
                            self.ret_links.setdefault(func, []).append((key, None))

    def env_read_refuted(self, writes, deps, receivers, arguments):
        """True when a computed _G[k] read proved harmless on conditions
        (check_env_reads) loses that proof: a global it relies on, or one of
        its method names, is assigned as a global; a method it is the
        receiver of is written on a table that may be a global's (anything
        but a local module table whose identity stays in its file, module_ok);
        or a method it is an argument of is written at all (on whatever
        table, that method could receive it). A definition that is a
        function without parameters (no self, no ...) can never receive the
        value and refutes nothing."""
        if (deps | receivers | arguments) & writes:
            return True
        for unit in self.units:
            flow = unit.flow
            for name in arguments:
                if any(not _parameterless(value) for value in flow.field_writes.get(name, ())):
                    return True
            for name in receivers:
                for value in flow.field_writes.get(name, ()):
                    if _parameterless(value):
                        continue
                    base = flow.field_bases[value][1] if value is not _OPAQUE else None
                    root = flow.alias_root(base) if type(base) is _Binding else None
                    if root is None or root.kind != 'local' or root.value is None \
                            or root.value.kind != 'table' or not flow.module_ok(root):
                        return True
        return False

    def trusted(self, implementation):
        """True while the loaded source leaves a transform's implementation
        established (STD-V15-2): the global it names is never assigned (by
        name, through _G or by an open environment), no field of the string
        library that it uses is written (a computed key or an escaping
        reference to the table may write any), and for a string method or
        tostring (which first consults __tostring) the shared string
        metatable is never reached by a getmetatable result that leaves a
        test or comparison."""
        method = implementation.startswith(':')
        name = _STRING + '.' + implementation[1:] if method else implementation
        root, _, field = name.partition('.')
        if root in self.global_writes:
            return False
        if field and ('*' in self.library_writes or field in self.library_writes):
            return False
        return not ((method or name == 'tostring') and self.string_meta_open)

    def runs_before(self, unit, call, point):
        """True when call is made while its file loads (load_points: chunk
        code or an invoked initializer, outside nested functions) no later
        than the load point (unit order, statement indexes...)."""
        at = unit.flow.chunk_calls.get(call)
        return at is not None and (unit.order,) + at <= point

    def export_point(self, path):
        """The load point of the one established assignment of a Nexus
        export path (export_established)."""
        return self.path_points[self.assignments[path][0][0]]

    def export_ok(self, path, module, name):
        rows = self.assignments.get(path, ())
        return (len(rows) == 1 and rows[0][1] is not None and rows[0][1].kind == 'name'
                and rows[0][1].binding is module and not self.assignments.get(path + '.' + name))

    def export_established(self, path):
        """True when the one assignment of an export path (export_ok) runs
        when its file loads (load_established, V15 review fix)."""
        return self.assignments[path][0][0] in self.path_points

    def module_function(self, flow, module, name, exports):
        """(function node or None, reason, load point) for module.name: one
        definition, on a module table whose identity stays in its file,
        established when that file loads (load_established: a definition in
        an initializer nothing calls at load defines nothing, V15 review
        fix), with every Nexus export of it assigned once, established too,
        and its field never assigned by path. The load point is (unit order,
        top-level statement index) of the definition."""
        if module.value is None or module.value.kind != 'table' or not flow.module_ok(module):
            return None, ('the module table %s is assigned again, written through a computed '
                          'key or escapes its file' % module.node.value), None
        if 'setmetatable' in self.global_writes and flow.metatable_hooked(module):
            return None, ('the module table %s has a metatable statement and the loaded source '
                          'assigns setmetatable' % module.node.value), None
        func, count, top = flow.module_funcs.get((module, name), (None, 0, None))
        if count != 1 or func is None:
            return None, ('%s.%s has %d definitions, directly or through a local alias'
                          % (module.node.value, name, count)), None
        if top is None:
            return None, ('%s.%s is not defined when its file loads: its definition is not run '
                          'by the file chunk or an initializer it calls'
                          % (module.node.value, name)), None
        for path in exports:
            if not self.export_ok(path, module, name):
                return None, '%s or %s.%s is assigned elsewhere' % (path, path, name), None
            if not self.export_established(path):
                return None, ('%s is not assigned when its file loads: its assignment is not run '
                              'by the file chunk or an initializer it calls' % path), None
        return func, None, (self.owner[id(flow)].order,) + top

    # -- the may-flow search -----------------------------------------------

    def field_defs(self, name):
        """Every value written to a field of this name in any unit, with its
        unit flow."""
        if name not in self.field_cache:
            self.field_cache[name] = [(value, unit.flow) for unit in self.units
                                      for value in unit.flow.field_writes.get(name, ())]
        return self.field_cache[name]

    def gate(self, key, flow):
        """The definitions a binding or field write needs, else None. Every
        write of a field name anywhere must carry the proof, a conservative
        rule on top of object identity."""
        if type(key) is tuple:
            if key[0] == 'fwrite':
                return [value for value, _ in self.field_defs(flow.field_bases[key[1]][0])]
            return None
        if type(key) is _Binding:
            return flow.defs.get(key, ())
        return None

    def objects_at(self, base, flow, stack, depth=0):
        """The object origins base holds when the value being followed was
        passed in under stack (review fixes 3 and 4): through a chain of
        local aliases, a parameter of a function whose call is on the stack
        holds only the table that call passed (recursively below it);
        otherwise flow.objects, every call's origins, applies, which is right
        for a value made inside that function, since every call then holds
        it."""
        base = flow.alias_root(base)
        if type(base) is _Binding and base.kind == 'param' and base.index is not None \
                and depth <= 16:
            for position in range(len(stack) - 1, -1, -1):
                args = flow.call_arguments(base.owner, stack[position])
                if args is None:
                    continue
                if base.index >= len(args):
                    return None
                arg = args[base.index]
                if arg.kind == 'table':
                    return frozenset((arg,))
                if arg.kind == 'name' and arg.binding is not None:
                    return self.objects_at(arg.binding, flow, stack[:position], depth + 1)
                return None
        return flow.objects(base)

    def field_reads(self, value, flow, stack):
        """(read, stack) for each read of the field a write sets whose table
        shares an object origin with the table written under this call
        stack, in the same unit (review fixes 2 to 4). A read through a
        parameter of a local function (directly or through local aliases)
        matches per call: it continues only under each call whose argument
        holds the written table, so its function returns the value only to
        that call. When that argument is itself a parameter of the calling
        function, the call continues under every enclosing call whose own
        argument holds the table (argument_contexts, review fix 5), so each
        enclosing function returns the value only to its own call. A table
        made inside a function is a fresh object per invocation, so a read
        on it continues under the invocation that wrote it (carrier_contexts,
        review fix 6)."""
        name, base = flow.field_bases[value]
        written = self.objects_at(base, flow, stack)
        if not written:
            return []
        out = []
        for read, read_base in flow.field_reads.get(name, ()):
            root = flow.alias_root(read_base)
            if type(root) is _Binding and root.kind == 'param' and root.index is not None \
                    and not flow.defs.get(root):
                if root in written:
                    # Written through the same parameter: the same invocation.
                    out.append((read, stack))
                for context in self.param_contexts(root, flow, written, stack):
                    out.append((read, context))
            else:
                held = (flow.objects(read_base) or frozenset()) & written
                for context in self.carrier_contexts(held, flow, stack):
                    out.append((read, context))
        return out

    def carrier_contexts(self, objects, flow, stack):
        """The call stacks under which a read of one of these written
        objects meets the very object written under stack (review fix 6,
        SPEC-147-S8-RF5-1). A table constructor or local of the file chunk
        is one object: (). One made inside a function is fresh in each of
        its invocations: the write's stack up to that function's innermost
        call on it, or () when the stack holds no call at all (the value is
        made in every invocation). A stack that holds other calls but none
        of that function leaves its invocation unknown, so that object
        proves nothing (unproven)."""
        out = []
        for obj in objects:
            func = flow.made_in.get(obj)
            context = () if func is None or not stack else None
            if func is not None:
                for position in range(len(stack) - 1, -1, -1):
                    if flow.call_arguments(func, stack[position]) is not None:
                        context = stack[:position + 1]
                        break
            if context is not None and context not in out:
                out.append(context)
        return sorted(out, key=len)

    def param_contexts(self, param, flow, written, stack, depth=1):
        """The call stacks (outermost call first, ending with a resolved call
        of param's function) under which an unassigned parameter holds the
        object written under stack, each at most _STACK_LIMIT calls deep."""
        func = param.owner
        out = []
        for call in list(flow.direct_calls.get(func, ())) + list(flow.pcall_calls.get(func, ())):
            args = flow.call_arguments(func, call)
            if param.index < len(args):
                out.extend(context + (call,) for context
                           in self.argument_contexts(args[param.index], flow, written, stack,
                                                     depth)
                           if len(context) < _STACK_LIMIT)
        return out

    def argument_contexts(self, arg, flow, written, stack, depth):
        """The enclosing call stacks under which an argument expression holds
        the object written under stack (review fixes 5 and 6,
        SPEC-147-S8-RF4-1 and RF5-1): for a table constructor or a tracked
        local, carrier_contexts of the written objects it holds; one stack
        per enclosing call whose own argument holds it when it names
        (directly or through local aliases) a parameter of the calling
        function, so a wrapper never merges its separate calls. Beyond
        _STACK_LIMIT enclosing calls the path stays unproven."""
        if arg.kind == 'table':
            return self.carrier_contexts(frozenset((arg,)) & written, flow, stack)
        if arg.kind != 'name' or arg.binding is None:
            return []
        root = flow.alias_root(arg.binding)
        if type(root) is _Binding and root.kind == 'param' and root.index is not None \
                and not flow.defs.get(root):
            if root in written:
                return [()]
            if depth >= _STACK_LIMIT:
                return []
            return self.param_contexts(root, flow, written, stack, depth + 1)
        return self.carrier_contexts(self.argument_objects(arg, flow) & written, flow, stack)

    def argument_objects(self, arg, flow):
        """The object origins an argument expression passes."""
        if arg.kind == 'table':
            return frozenset((arg,))
        if arg.kind == 'name' and arg.binding is not None:
            return flow.objects(arg.binding) or frozenset()
        return frozenset()

    def successors(self, key, flow, stack):
        """(key, flow, call stack) successors. A value enters a local
        function's parameter with its call pushed and leaves that function's
        return only to that call; without a pushed call it reaches every
        resolved call. Field and module paths start an empty stack."""
        if type(key) is tuple:
            tag = key[0]
            if tag == 'fwrite':
                return [(read, flow, next_stack)
                        for read, next_stack in self.field_reads(key[1], flow, stack)]
            if tag == 'pret' and len(key) == 3:
                # A later return position of an exported function: the same
                # calls as its first value, each at that position only.
                point = self.pret_points[key[:2]]
                return [state for unit in self.units
                        for call in unit.flow.path_calls.get(key[1], ())
                        if not self.runs_before(unit, call, point)
                        for state in self.result_states(call, unit.flow, key[2], ())]
            if tag == 'pret':
                point = self.pret_points[key]
                return [(call, unit.flow, ()) for unit in self.units
                        for call in unit.flow.path_calls.get(key[1], ())
                        if not self.runs_before(unit, call, point)]
            if tag == 'ret' and len(key) == 3:
                # A later return position: the same resolved calls as the
                # first value (the call on the stack, else every direct call,
                # module call and export), each at that position only.
                func, position = key[1], key[2]
                if stack:
                    call = stack[-1]
                    if call in flow.direct_calls.get(func, ()):
                        return self.result_states(call, flow, position, stack[:-1])
                    return []
                out = [state for call in flow.edges.get(('ret', func), ())
                       for state in self.result_states(call, flow, position, ())]
                for nxt, owner in self.ret_links.get(func, ()):
                    if type(nxt) is tuple:
                        out.append((nxt + (position,), None, ()))
                    else:
                        out.extend(self.result_states(nxt, owner, position, ()))
                return out
            if tag == 'ret':
                if stack:
                    call = stack[-1]
                    if call in flow.direct_calls.get(key[1], ()):
                        return [(call, flow, stack[:-1])]
                    return []
                out = [(nxt, flow, ()) for nxt in flow.edges.get(key, ())]
                for nxt, owner in self.ret_links.get(key[1], ()):
                    out.append((nxt, owner, ()))
                return out
            if tag == 'sink':
                return []
        blocked = self.blocked.get(id(flow))
        out = [(nxt, flow, stack) for nxt in flow.edges.get(key, ())
               if blocked is None or (key, nxt) not in blocked]
        if len(stack) < _STACK_LIMIT:
            out.extend((param, flow, stack + (call,))
                       for param, call in flow.call_args.get(key, ()))
        return out

    def result_states(self, call, flow, position, stack):
        """Where result number position (1 or later; the first result is the
        call expression itself and is not handled here) of a resolved call
        goes, as (key, flow, stack) states: to the result node of the name a
        multiple assignment gives that position (_UnitFlow.later_result),
        and, when the call is the last expression of a return statement, on
        to the return position of that function behind the expressions
        before it (tail_calls), within _RESULT_LIMIT. Nothing else takes a
        later result: an argument, an operand, a parenthesized or non-last
        call sees the first value only, so no other position is reached."""
        out = []
        node = flow.results.get((call, position))
        if node is not None:
            out.append((node, flow, stack))
        tail = flow.tail_calls.get(call)
        if tail is not None and tail[1] + position < _RESULT_LIMIT:
            out.append((('ret', tail[0], tail[1] + position), flow, stack))
        return out

    def search(self, roots, allowed=None, stop=None):
        """Every key reached from roots [(key, flow)], with the call stack
        it was reached under. A binding or field write passes a value on
        only when all its definitions are in allowed, or, with allowed None,
        in the reached set itself (a fixpoint). Returns (reached keys, valid
        output keys with their flow).

        With allowed None, a field write can wait on a definition that only
        that write itself would let the search reach, such as a carrier
        copying the same field name (review fix 7, SPEC-147-S8-RF6-1). The
        field writes still waiting are then assumed to pass and the search
        repeated, adding each field write a repeat finds waiting in turn, so
        a chain of carriers bootstraps (review fix 8, SPEC-147-S8-RF7-1). An
        assumption holds only when every definition its write needs was
        reached by that search and no other write of that field may write a
        table it writes (assumption_holds); a refuted one waits again and is
        never assumed again, until every assumed write that passed holds (a
        greatest fixpoint of the same every-definition rule)."""
        reached, sinks, waiting = self.walk(roots, allowed, stop, {})
        assumed = {} if allowed is not None else self.waiting_writes(waiting, {}, ())
        refused = set()
        while assumed:
            trial, trial_sinks, still = self.walk(roots, None, stop, assumed)
            grown = self.waiting_writes(still, assumed, refused)
            if grown:
                assumed.update(grown)
                continue
            refuted = [key for key, flow in assumed.items() if key in trial
                       and not self.assumption_holds(key, flow, trial)]
            if not refuted:
                return trial, trial_sinks
            for key in refuted:
                del assumed[key]
                refused.add(key)
        return reached, sinks

    def waiting_writes(self, waiting, assumed, refused):
        """{field write key: its flow} for the field writes still waiting
        that are neither assumed nor refused."""
        return {key: states[0][0] for key, states in waiting.items()
                if type(key) is tuple and key[0] == 'fwrite'
                and key not in assumed and key not in refused}

    def assumption_holds(self, key, flow, trial):
        """True when an assumed field write may pass (review fixes 7 and 8):
        every definition its write needs was reached by the trial search,
        and it is the only write of that field on the tables it may write.
        Two writes of one field on a table have no known order, so a value
        written back from the table's own copy (a round trip after another
        table overwrote the field) would justify itself; such a write is
        never assumed. A write on an untracked table may write any table."""
        if any(value is _OPAQUE or value not in trial for value in self.gate(key, flow)):
            return False
        name, base = flow.field_bases[key[1]]
        mine = flow.objects(base) if base is not None else None
        if not mine:
            return False
        for value, other in self.field_defs(name):
            if value is key[1]:
                continue
            other_base = other.field_bases[value][1] if value is not _OPAQUE else None
            theirs = other.objects(other_base) if other_base is not None else None
            if theirs is None or (other is flow and theirs & mine):
                return False
        return True

    def walk(self, roots, allowed, stop, assumed):
        """One search pass (see search): a key of assumed passes its gate
        without its definitions. Returns (reached, sinks, still waiting)."""
        reached, visited, waiting, sinks = set(), set(), {}, {}
        queue = [(key, flow, ()) for key, flow in roots]
        while queue:
            key, flow, stack = queue.pop()
            if (key, stack) in visited:
                continue
            needs = self.gate(key, flow)
            if needs is not None and key not in assumed:
                pool = reached if allowed is None else allowed
                if any(value is _OPAQUE or value not in pool for value in needs):
                    waiting.setdefault(key, []).append((flow, stack))
                    continue
            visited.add((key, stack))
            reached.add(key)
            if type(key) is tuple and key[0] == 'sink':
                if self.output_ok(key[1], flow, stack):
                    sinks[key] = flow
                continue
            if allowed is None and flow is not None:
                gated = list(flow.def_of.get(key, ()))
                if key in flow.field_bases:
                    name = flow.field_bases[key][0]
                    gated += [('fwrite', value) for value, _ in self.field_defs(name)]
                for item in gated:
                    for state in waiting.pop(item, ()):
                        queue.append((item,) + state)
            if key == stop:
                continue
            queue.extend(self.successors(key, flow, stack))
        return reached, sinks, waiting

    # -- output receivers --------------------------------------------------

    def output_ok(self, node, flow, stack=()):
        """A candidate output is a real one only on a client receiver: the
        never-assigned global print, or a SetText/AddLine/AddMessage method
        whose receiver client_object proves (review fixes 2 to 4) and whose
        method no loaded source replaces on that receiver (method_overridden).
        A parameter receiver, or a receiver field read through a parameter,
        is checked against the argument of the call on the value's own stack
        when there is one. A local table with its own SetText is never an
        output."""
        memo = (node, id(flow), stack)
        if memo not in self.output_memo:
            self.output_memo[memo] = self.output_proved(node, flow, stack)
        return self.output_memo[memo]

    def output_proved(self, node, flow, stack):
        """output_ok without its per-receipt memo."""
        receiver = flow.sinks[node]
        if receiver is None:
            return node.func.value not in self.global_writes
        while receiver.kind == 'paren':
            receiver = receiver.expr
        if self.method_overridden(node.name, receiver, flow, stack):
            return False
        binding = receiver.binding if receiver.kind == 'name' else None
        if binding is not None and binding.kind == 'param' and binding.index is not None \
                and not flow.defs.get(binding):
            for position in range(len(stack) - 1, -1, -1):
                args = flow.call_arguments(binding.owner, stack[position])
                if args is not None:
                    return binding.index < len(args) \
                        and self.client_value(args[binding.index], flow, 1)
        return self.client_object(receiver, flow, 0, stack)

    # -- output method replacement (review fix 4) ----------------------------

    def identity(self, base, flow, stack):
        """A broad identity of the object a binding may hold, used only to
        refuse outputs: its object origins under stack, plus a token per
        field it is read from (local a = x.F), so that any alias of a widget
        read from a field shares that field's token."""
        tokens = set(self.widened(flow, self.objects_at(base, flow, stack)) or ())
        root = flow.alias_root(base)
        tokens.add(root)
        defs = flow.defs.get(root, ()) if type(root) is _Binding else ()
        for value in defs:
            if value is not _OPAQUE and value.kind == 'index' and value.key.kind == 'string':
                tokens.add(('field-value', value.key.value))
        if type(root) is _Binding and root.kind == 'param':
            for call in list(flow.direct_calls.get(root.owner, ())) \
                    + list(flow.pcall_calls.get(root.owner, ())):
                args = flow.call_arguments(root.owner, call)
                if root.index is not None and root.index < len(args):
                    arg = args[root.index]
                    if arg.kind == 'index' and arg.key.kind == 'string':
                        tokens.add(('field-value', arg.key.value))
        return frozenset(tokens)

    def widened(self, flow, origins):
        """origins (of flow.objects or objects_at) together with the one
        object of each singleton cache helper whose result a local among
        them holds. Such a local is declared once with a call, by its plain
        name, of an unassigned local function that _UnitFlow.cached_singleton
        proves, while no loaded source assigns the creator global (by name,
        through _G or by an open environment): the helper's own local for
        the object is then another name of the very object this local
        holds. A helper is admitted (cached_singletons) only when every use
        of its name is such a local and when neither those locals nor the
        cache nor the helper's own local hand the object on, so within the
        loaded source no other name can hold it. That holds under the three
        assumptions about the client stated in cached_singleton, which are
        not proved. A local declared
        with any other call and an untracked base add nothing, so two
        results of an uncached factory are never merged. Used for receiver
        fields and for the identity that refuses outputs when an output
        method is replaced (method_overridden) only; the flow of values
        through fields is unchanged."""
        if not origins:
            return origins
        extra = set()
        for origin in origins:
            if type(origin) is not _Binding or origin.kind != 'local':
                continue
            defs = flow.defs.get(origin, ())
            if len(defs) != 1 or defs[0] is _OPAQUE or defs[0].kind != 'call':
                continue
            target = _local_function(defs[0].func)
            single = flow.singletons.get(target) if target is not None else None
            if single is not None and single[1] not in self.global_writes:
                extra |= flow.objects(single[0]) or frozenset()
        return origins | extra if extra else origins

    def receiver_identity(self, receiver, flow, stack):
        """The broad identity of an output receiver, or None when unknown."""
        if receiver.kind == 'name' and receiver.binding is None:
            return frozenset((('global', receiver.value),))
        if receiver.kind == 'name':
            return self.identity(receiver.binding, flow, stack)
        if receiver.kind == 'index' and receiver.key.kind == 'string' \
                and receiver.key.value is not None:
            tokens = {('field-value', receiver.key.value)}
            for value in self.field_defs_values(receiver.key.value):
                if value is not _OPAQUE and value.kind == 'name' and value.binding is not None:
                    tokens |= self.identity(value.binding, self.write_flow(value), ())
            return frozenset(tokens)
        return None

    def method_overridden(self, method, receiver, flow, stack):
        """True when the loaded source may replace this output method on this
        receiver: a write of field method on an untracked table, or on a
        tracked object whose broad identity meets the receiver's. A write
        on a table constructor (or a local holding only one) replaces a plain
        Lua table's field, never a client object's, and is ignored."""
        wanted = self.receiver_identity(receiver, flow, stack)
        for value, other in self.field_defs(method):
            base = other.field_bases[value][1] if value is not _OPAQUE else None
            if base is None:
                return True
            if type(base) is not _Binding:
                continue
            root = other.alias_root(base)
            defs = other.defs.get(root, ())
            if root.kind == 'local' and len(defs) == 1 and defs[0] is not _OPAQUE \
                    and defs[0].kind == 'table':
                continue
            if wanted is None or (self.identity(base, other, ()) & wanted):
                return True
        return False

    def field_defs_values(self, name):
        return [value for value, _ in self.field_defs(name)]

    def write_flow(self, value):
        """The unit flow a field-write value belongs to."""
        for unit in self.units:
            if value in unit.flow.field_bases:
                return unit.flow
        return None

    def client_object(self, expr, flow, depth=0, stack=()):
        """True when expr can only hold a client object, proved from an
        evidenced root (review fix 3): a _CLIENT_GLOBALS name the loaded
        source never assigns; a local whose every definition is one (a nil
        given by its own declaration is neutral, a later nil assignment is
        not: review fix 4); a parameter of a local function whose every use
        is a resolved call or pcall, each passing one; a field of a table
        resolved under the value's call stack whose every write on that
        object (and every write of the field on an untracked table) is one;
        or a widget client_value proves. Any other receiver, such as an
        unknown global or an empty local table, proves nothing."""
        if depth > 16:
            return False
        while expr.kind == 'paren':
            expr = expr.expr
        memo = (id(expr), stack)
        if memo in self.receiver_memo:
            return self.receiver_memo[memo]
        self.receiver_memo[memo] = False    # a receiver cycle proves nothing
        result = False
        if expr.kind == 'name' and expr.binding is None:
            result = expr.value in _CLIENT_GLOBALS and expr.value not in self.global_writes
        elif expr.kind == 'name' and expr.binding.kind == 'local':
            defs = [value for value in flow.defs.get(expr.binding, ())
                    if not (value is not _OPAQUE and value.kind == 'constant'
                            and value.value == 'nil' and value in flow.declared)]
            result = bool(defs) and all(value is not _OPAQUE
                                        and self.client_value(value, flow, depth)
                                        for value in defs)
        elif expr.kind == 'name' and expr.binding.kind == 'param':
            result = self.client_param(expr.binding, flow, depth)
        elif expr.kind == 'index' and expr.key.kind == 'string' and expr.key.value is not None:
            result = self.client_field(expr, flow, depth, stack)
        elif expr.kind in ('call', 'method'):
            result = self.client_value(expr, flow, depth)
        self.receiver_memo[memo] = result
        return result

    def client_param(self, param, flow, depth):
        func = param.owner
        if param.index is None or flow.defs.get(param):
            return False
        calls = flow.calls_resolved(func)
        if not calls:
            return False
        for call in calls:
            args = flow.call_arguments(func, call)
            if param.index >= len(args) \
                    or not self.client_value(args[param.index], flow, depth + 1):
                return False
        return True

    def client_field(self, expr, flow, depth, stack=()):
        """A receiver field X.F: X must be a tracked table, resolved under the
        value's call stack (review fix 4), at least one write of F must be on
        an object X may hold, and every such write, every write of F on an
        untracked table here and every write of F in another file on an
        untracked table must be a client object. A local declared with the
        direct call of a singleton cache helper, on either side, also stands
        for that helper's one object (widened), so a write through any such
        local counts for every other one, a client widget and a conflicting
        value alike. A helper is such a helper only when every use of its
        name is one of these locals and none of the names holding the object
        hands it on (cached_singletons, confined): a holder that is stored,
        returned, passed or aliased, used as an arithmetic or concatenation
        operand, or written through with a computed key refuses the helper.
        So within the loaded source a write on the object is a write with a
        literal key through one of the merged names, and those are the
        writes examined here. That rests on three assumptions about the
        client, which are not proved (cached_singleton): the creator runs
        no loaded code, the client does not hand the object back to loaded
        code (for example a script handler's self, a global frame name),
        and the methods called on these names are the client's own. The
        results of
        any other helper stay separate objects."""
        name = expr.key.value
        held = self.widened(flow, self.objects_at(expr.obj.binding, flow, stack)) \
            if expr.obj.kind == 'name' and expr.obj.binding is not None else None
        if not held:
            return False
        matched = False
        for unit in self.units:
            other = unit.flow
            for value in other.field_writes.get(name, ()):
                base = other.field_bases[value][1] if value is not _OPAQUE else None
                written = self.widened(other, other.objects(base)) if base is not None else None
                if other is flow and written and not (written & held):
                    continue        # a write on another tracked object here
                if other is not flow and written:
                    continue        # a tracked object of another file
                if value is _OPAQUE or not self.client_value(value, other, depth + 1):
                    return False
                matched = matched or (other is flow and bool(written))
        return matched

    def client_value(self, value, flow, depth):
        """True when a value is a client object: a CreateFrame widget, a
        CreateFontString widget of a proved client object, or a reference
        client_object proves."""
        if value.kind == 'call':
            if value.func.kind == 'name' and value.func.binding is None:
                return (value.func.value in _WIDGET_FUNCTIONS
                        and value.func.value not in self.global_writes)
            # A local widget helper (Source25 continuation): a call of a
            # resolved local function each of whose return statements gives
            # a client value, and that has at least one.
            target = _local_function(value.func)
            if target is None or depth > 16:
                return False
            statements = [stmt for stmt in _descendants(target.body) if stmt.kind == 'return']
            if not statements or any(not stmt.exprs for stmt in statements):
                return False
            returns = [stmt.exprs[0] for stmt in statements]
            memo = ('helper', id(target))
            if memo in self.receiver_memo:
                return self.receiver_memo[memo]
            self.receiver_memo[memo] = False    # a helper cycle proves nothing
            result = all(self.client_value(expr, flow, depth + 1) for expr in returns)
            self.receiver_memo[memo] = result
            return result
        if value.kind == 'method':
            return (value.name in _WIDGET_METHODS and not self.field_defs(value.name)
                    and self.client_object(value.obj, flow, depth + 1))
        if value.kind in ('name', 'index', 'paren'):
            return self.client_object(value, flow, depth + 1)
        return False

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
        """True when a wrapper's own consumer-method result reaches its return.
        A forwarding wrapper (_UnitScan.find_forwarders) has no consumer
        method call of its own: its result is that of a call handing its key
        to a direct wrapper, so only such calls whose direct wrapper returns
        its own result are searched from, and one of them must reach the
        forwarding wrapper's return. The direct wrapper is never a
        forwarding wrapper, so this goes one level deep."""
        info = unit.scan.wrappers[binding]
        nodes = info['internal']
        if 'forwards' in info:
            nodes = [node for node, target in info['forwards']
                     if self.wrapper_returns(target, unit)]
            if not nodes:
                return False
        stop = ('ret', binding.value)
        reached, _ = self.search([(node, unit.flow) for node in nodes], stop=stop)
        return stop in reached

    def prove(self, roots_by_key):
        """{key: {id(root): outputs}} for the roots of each key whose value
        reaches an output, under the every-definition rule of that key.

        Several keys can have the same single root (the entries of one map
        dispatch share its call node). Their searches are the same query:
        search(roots) with one root, no allowed set and no stop reads only
        its root, the linked units (fixed once the linker is built) and
        memos whose entries are written once and never changed or dropped
        (output_memo, receiver_memo, field_cache and each flow's
        object_memo). An entry is provisional only while it is computed,
        and no search runs inside such a computation, so every entry the
        first search of a query read or wrote is final when the query comes
        again. The key is no input of it. A repeat therefore finds the same
        sinks and writes nothing, so the sinks of such a query are kept for this one
        call, under the root node itself and the identity of its flow, and
        used again for a later key with that same root and flow. Nothing is
        kept between calls, no other search is shared (several roots, the
        per-root searches under allowed, a forced single_root_replay,
        wrapper_returns), and the output rows are built anew for each key."""
        proofs, single = {}, {}
        for key, roots in roots_by_key.items():
            proofs[key] = {}
            if not roots:
                continue        # a search from no root reaches nothing
            if len(roots) == 1 and not self.single_root_replay:
                # One root: its own search under the key's every-definition
                # rule is that one search (allowed is its reached fixpoint),
                # so its sinks are those sinks.
                root, flow = roots[0]
                query = (root, id(flow))
                if query in single:
                    sinks = single[query]
                else:
                    sinks = single[query] = self.search(roots)[1]
                if sinks:
                    proofs[key][id(root)] = self.outputs(sinks)
                continue
            allowed, sinks = self.search(roots)
            for root in roots:
                _, sinks = self.search([root], allowed)
                if sinks:
                    proofs[key][id(root[0])] = self.outputs(sinks)
        return proofs


def _consumer_facts(registry):
    """The parts of the validated registry-bound catalog a consumer receipt
    uses: the declarations, each window family's status and adopted keys,
    and each key-context row's familySurface."""
    validated = validate_registry_catalog_data(*registry)
    context = validated['keyContext']
    return {'declarations': validated['declarations'],
            'windowFamilies': [{'name': family['name'], 'semanticStatus': family['semanticStatus'],
                                'coverageStatus': family['coverageStatus'],
                                'adoptedKeys': list(family['adoptedKeys'])}
                               for family in context['windowFamilies']],
            'surfaces': {row['key']: row.get('familySurface') for row in context['keys']
                         if type(row) is dict}}


@_collector_paused
def consumer_binding_report(english_source: bytes, packs_source: bytes, key_context_json: bytes,
                            release_json: bytes, localization_source: bytes, toc_records,
                            source_records) -> dict:
    """The static consumer binding receipt (see above) for the exact bytes of
    the five registry-bound inputs, the TOC records and the source records.
    A non-bytes registry input is a TypeError, an invalid catalog raises its
    strict error unchanged and a record failure raises CatalogConsumerError.
    No file is read or written, nothing is fetched, executed or modified, and
    only the in-memory memos are kept between calls: the Lua parse memo
    (_PARSE_MEMO) and the input memo of the strict verdicts this receipt
    runs first (_INPUT_MEMO, see _memoized)."""
    registry = (english_source, packs_source, key_context_json, release_json,
                localization_source)
    registry = _snapshots(_FIVE_INPUTS, registry)
    tocs, supplied, listed = _consumer_inputs(
        (registry[0], registry[1], registry[4]), toc_records, source_records)
    # The strict registry-bound verdict first: an invalid catalog gets no
    # receipt (its error raises unchanged, on every call; a valid verdict is
    # kept in the input memo, see _core_checks). Only the declarations and
    # the key-context family facts of the validated catalog are used below.
    _core_checks('consumer-verdict', registry, lambda: registry_catalog_report(*registry))
    facts = _memoized('consumer-facts', registry, lambda sources: _consumer_facts(sources))
    declarations = facts['declarations']
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
        # V15 review fix: a reference that may write any global (the
        # environment table as a value or under a computed key, or an
        # environment opener) may replace Nexus, the seam or any trusted
        # global, so it is a mutation problem, not only a lost proof.
        refuted = [read for owner, read in linker.env_read_escapes if owner is unit]
        for node in unit.flow.env_escapes + refuted \
                + (unit.flow.type_escapes if linker.type_open else []):
            problems.append(located(unit, {
                'code': 'binding-mutation', 'line': node.line, 'column': node.column,
                'construct': 'global-environment',
                'detail': 'the loaded source may write any global here (%s)' % (
                    _global_ref(node) or _ENV)}))
        for arg, method, kind, root, site, wrapper in scan.literals:
            declaration = declarations.get(arg.value)
            where = {'line': arg.line, 'column': arg.column}
            if declaration is None:
                problems.append(located(unit, dict(where, code='binding-orphan', key=arg.value,
                                                   method=method)))
            elif kind is None:
                continue
            elif _METHOD_KIND[declaration['kind']] != kind:
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
            func, reason, _ = (None, 'the dispatcher is not defined on a local module table',
                               None) if module is None \
                else linker.module_function(unit.flow, module, name, exports)
            if reason is None and func is not candidate['func']:
                reason = '%s.%s is not this function' % (module.node.value, name)
            if reason is None and not exports:
                reason = 'the module table %s is not exported as a Nexus path' % module.node.value
            if reason is None and candidate['iterated'] and 'pairs' in linker.global_writes:
                reason = 'a guard table is iterated by pairs, which the loaded source assigns'
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
                elif _METHOD_KIND[declaration['kind']] != info['kind']:
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
    for family in facts['windowFamilies']:
        for key in family['adoptedKeys']:
            families.setdefault(key, []).append({
                'name': family['name'], 'semanticStatus': family['semanticStatus'],
                'coverageStatus': family['coverageStatus']})
    surfaces = facts['surfaces']
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
    taken = {}
    for path, line, column in positions:
        taken.setdefault(path, set()).add((line, column))
    for unit in units:
        sited = taken.get(unit.path)
        for value, spots in unit.leads.items():
            if value in leads:
                count = len(spots) - (sum(1 for spot in spots if spot in sited) if sited else 0)
                if count:
                    leads[value][unit.path] = count
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
        'tocs': [{'path': path, 'sha256': _digest(data).hex(),
                  'byteLength': len(data),
                  'loaded': [entry for entry, (toc, _, _) in listed.items() if toc == path]}
                 for path, data in tocs],
        'sources': [{'path': unit.path, 'toc': listed[unit.path][0],
                     'tocLine': listed[unit.path][1],
                     'sha256': _digest(unit.data).hex(),
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
