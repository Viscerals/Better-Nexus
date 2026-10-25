#!/usr/bin/env python3
"""Parser-only syntax foundation for the Nexus localization data (#147, B1).

Status: PARSER_ONLY_FULL_VALIDATION_PENDING. This module is a parser only.
Full catalog validation is NOT_IMPLEMENTED. It checks no key pattern, length,
product ID, placeholder, markup, field-type schema, metadata, review record,
coverage, file path or completeness. A successful parse does not claim that a
catalog is valid, reviewed or complete. The validator and its --root command
line are later tasks, and they are to build on these same two functions.

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

STATUS = 'PARSER_ONLY_FULL_VALIDATION_PENDING'
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
    'message': 'parser only; full catalog validation is not implemented',
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


def main() -> int:
    """Direct execution: write the pending notice on stderr and return exit
    status 2. This is not the validator's command line, and any arguments are
    ignored."""
    sys.stderr.write(json.dumps(NOTICE, sort_keys=True) + '\n')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
