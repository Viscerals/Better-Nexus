#!/usr/bin/env python3
"""Read-only string-literal inventory of Nexus Lua source (issue #123, L10N-01).

    python tools/l10n_inventory.py --root DIR PATH [PATH ...]

Each PATH is a .lua file relative to --root (default: the repository root). The
file is read as UTF-8 text and scanned; it is never executed, imported or
written. stdout has one ASCII JSON object per string literal, in source order,
with path (POSIX, relative to --root), line and column (1-based, at the
opening quote or bracket, in characters) and either
  * record "literal" and text (the string's value), or
  * record "bytes" and hex (its exact bytes, lowercase), when the value is not
    valid UTF-8. Only decimal escapes can make such a value; it is listed, not
    converted to text.

Every PATH is checked and scanned before anything is printed. An invalid
request prints nothing on stdout, exits 1 and writes one ASCII JSON line on
stderr: record "error", error (missing, outside-root, unsupported, unreadable,
not-utf8, unfinished-string, unfinished-comment or invalid-escape), path (the
PATH as given), a short message and, for a token in the source, the line and
column where it starts. An OS error while --root or a PATH is resolved,
checked or read is unreadable; when --root cannot be resolved, path is the
first PATH.

A command line that argparse rejects (no PATH, an unknown option or a missing
option value) is a usage error, not an invalid request: argparse writes its
usage and message on stderr and exits 2, as usual. -h or --help prints the
usage and this text on stdout and exits 0.

Scanning follows the Lua 5.1 lexical rules for short strings and their
escapes, long-bracket strings, short and long comments, and line breaks.
LuaJIT and Lua 5.2 escape additions are not recognised, and nested [[ inside a
level-0 long bracket (a build option in Lua 5.1) is not checked.

A listed literal is a lead for review. It is not proof that the text is shown
to a player or that it should be translated.
"""
from __future__ import annotations
import argparse, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
NEWLINE = {'\n', '\r'}
DIGITS = set('0123456789')
ESCAPES = {'a': '\a', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v'}
MESSAGES = {
    'missing': 'no such file',
    'outside-root': 'the path is outside --root',
    'unsupported': 'only .lua files are scanned',
    'unreadable': 'the file could not be read',
    'not-utf8': 'the file is not valid UTF-8',
    'unfinished-string': 'a string is not closed',
    'unfinished-comment': 'a long comment is not closed',
    'invalid-escape': 'a decimal escape is above 255',
}


class SourceError(Exception):
    """An invalid request: a stable code and, for a token, where it starts."""

    def __init__(self, code: str, line: int = None, column: int = None):
        super().__init__(code)
        self.code, self.line, self.column = code, line, column

    def record(self, path: str) -> dict:
        record = {'record': 'error', 'error': self.code, 'path': path, 'message': MESSAGES[self.code]}
        if self.line is not None:
            record.update(line=self.line, column=self.column)
        return record


class Scanner:
    """The Lua 5.1 lexer states that decide where string literals are. Any
    other character is passed over one at a time."""

    def __init__(self, text: str):
        self.text, self.index, self.line, self.line_start = text, 0, 1, 0

    def peek(self, offset: int = 0) -> str:
        index = self.index + offset
        return self.text[index] if index < len(self.text) else ''

    def column(self) -> int:
        return self.index - self.line_start + 1

    def newline(self):
        """One line break: \\n, \\r, \\r\\n or \\n\\r, counted once as in Lua 5.1."""
        first = self.peek()
        self.index += 1
        if self.peek() in NEWLINE and self.peek() != first:
            self.index += 1
        self.line, self.line_start = self.line + 1, self.index

    def level(self) -> int:
        """The level of a long bracket ([==[ or ]==]) starting here, else -1."""
        index = self.index + 1
        while self.peek(index - self.index) == '=':
            index += 1
        return index - self.index - 1 if self.peek(index - self.index) == self.peek() else -1

    def long_bracket(self, level: int, code: str, line: int, column: int) -> str:
        """The body of a long string or comment whose opening bracket is here.
        An unclosed one is the error code at line and column."""
        self.index += level + 2
        if self.peek() in NEWLINE:
            self.newline()
        body = []
        while True:
            char = self.peek()
            if char == '':
                raise SourceError(code, line, column)
            if char in NEWLINE:
                body.append('\n')
                self.newline()
            elif char == ']' and self.level() == level:
                self.index += level + 2
                return ''.join(body)
            else:
                body.append(char)
                self.index += 1

    def short_string(self, quote: str, line: int, column: int) -> bytes:
        """The value of a quoted string whose opening quote is here."""
        self.index += 1
        value = bytearray()
        while True:
            char = self.peek()
            if char == '' or char in NEWLINE:
                raise SourceError('unfinished-string', line, column)
            self.index += 1
            if char == quote:
                return bytes(value)
            if char != '\\':
                value += char.encode('utf-8')
                continue
            char = self.peek()
            if char in ESCAPES:
                value += ESCAPES[char].encode('ascii')
                self.index += 1
            elif char in NEWLINE:
                value += b'\n'
                self.newline()
            elif char in DIGITS:
                digits = ''
                while len(digits) < 3 and self.peek() in DIGITS:
                    digits += self.peek()
                    self.index += 1
                if int(digits) > 255:
                    raise SourceError('invalid-escape', line, column)
                value.append(int(digits))
            elif char == '':
                raise SourceError('unfinished-string', line, column)
            else:
                value += char.encode('utf-8')
                self.index += 1

    def literals(self):
        """Yield (line, column, value) for each string literal, in source order.
        The value is text, or bytes when a short string's value is not UTF-8."""
        while self.index < len(self.text):
            char = self.peek()
            if char in NEWLINE:
                self.newline()
            elif char == '-' and self.peek(1) == '-':
                line, column = self.line, self.column()
                self.index += 2
                level = self.level() if self.peek() == '[' else -1
                if level >= 0:
                    self.long_bracket(level, 'unfinished-comment', line, column)
                else:
                    while self.peek() != '' and self.peek() not in NEWLINE:
                        self.index += 1
            elif char == '[' and self.level() >= 0:
                line, column = self.line, self.column()
                yield line, column, self.long_bracket(self.level(), 'unfinished-string', line, column)
            elif char in '"\'':
                line, column = self.line, self.column()
                value = self.short_string(char, line, column)
                try:
                    value = value.decode('utf-8')
                except UnicodeDecodeError:
                    pass
                yield line, column, value
            else:
                self.index += 1


def inventory(root: pathlib.Path, name: str) -> list:
    """The records of one PATH; SourceError when the request is invalid. An
    OSError while the PATH is resolved, checked or read is unreadable."""
    try:
        path = (root / name).resolve()
    except OSError:
        raise SourceError('unreadable') from None
    try:
        shown = path.relative_to(root).as_posix()
    except ValueError:
        raise SourceError('outside-root') from None
    try:
        if not path.exists():
            raise SourceError('missing')
        if not path.is_file() or path.suffix != '.lua':
            raise SourceError('unsupported')
        data = path.read_bytes()
    except OSError:
        raise SourceError('unreadable') from None
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        raise SourceError('not-utf8') from None
    records = []
    for line, column, value in Scanner(text).literals():
        record = {'path': shown, 'line': line, 'column': column}
        if isinstance(value, bytes):
            record.update(record='bytes', hex=value.hex())
        else:
            record.update(record='literal', text=value)
        records.append(record)
    return records


def report(error: SourceError, name: str) -> int:
    """Write the one error record, for PATH name, on stderr; the exit status is 1."""
    sys.stderr.write(json.dumps(error.record(name), sort_keys=True) + '\n')
    return 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', type=pathlib.Path, default=ROOT)
    ap.add_argument('paths', nargs='+')
    ns = ap.parse_args(argv)
    try:
        root = ns.root.resolve()
    except OSError:
        return report(SourceError('unreadable'), ns.paths[0])
    lines = []
    for name in ns.paths:
        try:
            records = inventory(root, name)
        except SourceError as error:
            return report(error, name)
        lines += [json.dumps(record, sort_keys=True) for record in records]
    for line in lines:
        print(line)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
