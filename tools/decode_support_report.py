#!/usr/bin/env python3
"""Read a NexusSupport report file as DATA and print the report it contains.

    python tools/decode_support_report.py "<WoW>/WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua"
    python tools/decode_support_report.py NexusSupport.lua --out report.txt

The file is a WoW SavedVariables file: one assignment of a Lua table literal.
This tool NEVER executes it. It parses the literal with a restricted reader that
accepts only tables, strings, numbers, booleans and nil, rejects anything else
(function calls, operators, identifiers, metatables, long strings with embedded
code, setmetatable, loadstring), and then:

  * checks the report format and header fields;
  * checks chunk order and lengths against the header;
  * recomputes the checksum the addon wrote and compares it.

A checksum match means the text was not truncated or reordered on the way here.
It is NOT authenticity, NOT proof of who produced it, and NOT server evidence.
"""
from __future__ import annotations
import argparse, pathlib, re, sys

MAX_BYTES = 8 * 1024 * 1024
MAX_DEPTH = 64          # a report is three levels deep; anything deeper is not one
ASSIGNMENT = re.compile(r'^[ \t]*(?:local[ \t]+)?NexusSupportDB[ \t]*=', re.M)


class Reader:
    """A tiny reader for the subset of Lua a SavedVariables literal uses."""

    def __init__(self, text: str) -> None:
        self.text, self.pos, self.depth = text, 0, 0

    def error(self, message: str):
        line = self.text.count('\n', 0, self.pos) + 1
        raise ValueError(f'line {line}: {message}')

    def skip(self) -> None:
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in ' \t\r\n':
                self.pos += 1
            elif self.text.startswith('--', self.pos):
                # Block comments are comments, not data. Lua reads
                # --[[ ... ]] and --[==[ ... ]==] as one comment; reading them
                # as values would return text Lua itself would never assign.
                block = re.compile(r'--\[(=*)\[').match(self.text, self.pos)
                if block:
                    closer = ']' + block.group(1) + ']'
                    end = self.text.find(closer, block.end())
                    self.pos = len(self.text) if end < 0 else end + len(closer)
                else:
                    end = self.text.find('\n', self.pos)
                    self.pos = len(self.text) if end < 0 else end + 1
            else:
                return

    def expect(self, ch: str) -> None:
        self.skip()
        if self.pos >= len(self.text) or self.text[self.pos] != ch:
            self.error(f'expected {ch!r}')
        self.pos += 1

    def value(self):
        self.skip()
        if self.pos >= len(self.text):
            self.error('unexpected end of file')
        ch = self.text[self.pos]
        if ch == '{':
            return self.table()
        if ch in '"\'':
            return self.string()
        if ch == '[':
            # A long-bracket string is not produced by this report format.
            self.error('long-bracket strings are not accepted')
        if self.text.startswith('true', self.pos):
            self.pos += 4
            return True
        if self.text.startswith('false', self.pos):
            self.pos += 5
            return False
        if self.text.startswith('nil', self.pos):
            self.pos += 3
            return None
        return self.number()

    def number(self):
        start = self.pos
        while self.pos < len(self.text) and self.text[self.pos] in '+-0123456789.eExXaAbBcCdDfF':
            self.pos += 1
        raw = self.text[start:self.pos]
        if not raw:
            self.error('a value was expected')
        try:
            return int(raw, 0) if raw.lower().startswith(('0x', '-0x')) else (
                int(raw) if raw.lstrip('+-').isdigit() else float(raw))
        except ValueError:
            self.error(f'not a number: {raw!r}')

    def string(self):
        quote = self.text[self.pos]
        self.pos += 1
        out = []
        while True:
            if self.pos >= len(self.text):
                self.error('unterminated string')
            ch = self.text[self.pos]
            if ch == '\\':
                self.pos += 1
                if self.pos >= len(self.text):
                    self.error('unterminated escape')
                esc = self.text[self.pos]
                mapping = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\',
                           '"': '"', "'": "'", 'a': '\a', 'b': '\b',
                           'f': '\f', 'v': '\v', '\n': '\n'}
                if esc in mapping:
                    out.append(mapping[esc])
                    self.pos += 1
                elif esc in '0123456789':
                    # Only ASCII digits: str.isdigit() is true for characters
                    # int() cannot read, and \ddd in a WoW saved file is a
                    # BYTE, so it is decoded as one.
                    digits = ''
                    while len(digits) < 3 and self.pos < len(self.text) \
                            and self.text[self.pos] in '0123456789':
                        digits += self.text[self.pos]
                        self.pos += 1
                    value = int(digits)
                    if value > 255:
                        self.error(f'escape out of range: \\{digits}')
                    # A \ddd escape in a saved file is a BYTE. A byte above 127
                    # is carried as a surrogate escape so that encoding the text
                    # back with 'surrogateescape' reproduces exactly that byte -
                    # which is what the addon's checksum was computed over.
                    out.append(chr(value) if value < 128 else chr(0xDC00 + value))
                else:
                    self.error(f'unsupported escape: \\{esc}')
            elif ch == quote:
                self.pos += 1
                return ''.join(out)
            else:
                out.append(ch)
                self.pos += 1

    def key(self):
        self.skip()
        if self.text[self.pos] == '[':
            self.pos += 1
            key = self.value()
            self.expect(']')
            self.expect('=')
            return key
        start = self.pos
        while self.pos < len(self.text) and (self.text[self.pos].isalnum() or self.text[self.pos] == '_'):
            self.pos += 1
        name = self.text[start:self.pos]
        if not name:
            return None
        self.skip()
        if self.pos < len(self.text) and self.text[self.pos] == '=':
            self.pos += 1
            return name
        self.pos = start
        return None

    def table(self):
        self.depth += 1
        if self.depth > MAX_DEPTH:
            self.error(f'tables nested deeper than {MAX_DEPTH} levels')
        self.expect('{')
        out, index = {}, 1
        while True:
            self.skip()
            if self.pos >= len(self.text):
                self.error('unterminated table')
            if self.text[self.pos] == '}':
                self.pos += 1
                self.depth -= 1
                return out
            key = self.key()
            value = self.value()
            if key is None:
                out[index] = value
                index += 1
            else:
                out[key] = value
            self.skip()
            if self.pos < len(self.text) and self.text[self.pos] in ',;':
                self.pos += 1


def load(path: pathlib.Path) -> dict:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise SystemExit(f'{path}: cannot be read: {error}')
    if len(raw) > MAX_BYTES:
        raise SystemExit(f'{path}: larger than the {MAX_BYTES} byte bound this reader accepts')
    # 'surrogateescape', not 'replace': a byte the file carries literally is
    # kept as the byte it is, exactly as a \ddd escape is, so the checksum
    # counts what WoW wrote instead of accusing the copy of tampering.
    text = raw.decode('utf-8', 'surrogateescape')
    # The assignment must be a statement, not a mention. A copy of the text
    # inside a comment or inside another variable's string is not what Lua
    # would assign, so it is not what this tool reads either.
    matches = list(ASSIGNMENT.finditer(text))
    if not matches:
        raise SystemExit(f'{path}: no NexusSupportDB assignment found. '
                         'This tool reads the file WoW writes, not the addon source file.')
    if len(matches) > 1:
        print(f'PROBLEM: {len(matches)} NexusSupportDB assignments found; '
              'reading the last one, which is the value Lua would end with')
    reader = Reader(text[matches[-1].end():])
    return reader.value()


def checksum(chunks: list[str]) -> str:
    """The same bounded checksum core/SupportReport.lua computes."""
    a, b = 1, 0
    for index, chunk in enumerate(chunks, start=1):
        for byte in chunk.encode('utf-8', 'surrogateescape'):
            a = (a + byte) % 65521
            b = (b + a) % 65521
        a = (a + index) % 65521
        b = (b + a) % 65521
    return f'{b:04x}{a:04x}'


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('path', help='the NexusSupport.lua file WoW wrote under WTF/Account/<ACCOUNT>/SavedVariables')
    ap.add_argument('--out', help='write the decoded report text here instead of standard output')
    ns = ap.parse_args()
    path = pathlib.Path(ns.path)
    data = load(path)
    if not isinstance(data, dict):
        raise SystemExit('NexusSupportDB is not a table')
    report = data.get('report')
    if not isinstance(report, dict):
        raise SystemExit('this file has no prepared report')
    meta = report.get('meta') if isinstance(report.get('meta'), dict) else {}
    chunk_map = report.get('chunks')
    if not isinstance(chunk_map, dict):
        raise SystemExit('this report has no chunks')
    indexes = sorted(k for k in chunk_map if isinstance(k, int))
    if indexes != list(range(1, len(indexes) + 1)):
        raise SystemExit(f'chunk order is broken: {indexes[:8]}...')
    chunks = [chunk_map[i] for i in indexes]
    for index, chunk in enumerate(chunks, start=1):
        if not isinstance(chunk, str):
            raise SystemExit(f'chunk {index} is not text')

    declared_count = meta.get('chunkCount')
    declared_bytes = meta.get('bytes')
    declared_sum = meta.get('checksum')
    missing = [name for name, value in (('chunkCount', declared_count),
                                        ('bytes', declared_bytes),
                                        ('checksum', declared_sum))
               if value is None]
    body = ''.join(chunks)
    actual_bytes = sum(len(c.encode('utf-8', 'surrogateescape')) for c in chunks)
    recomputed = checksum(chunks)

    print(f'file          : {path}')
    print(f'report id     : {meta.get("id")}')
    print(f'format        : {meta.get("format")}')
    print(f'build         : {meta.get("build")}')
    print(f'topic         : {meta.get("topic")}')
    print(f'extended      : {meta.get("extended")}  partial: {meta.get("partial")}')
    print(f'omissions     : {meta.get("omissions")}')
    print(f'captured      : {meta.get("captureStart")} -> {meta.get("captureEnd")}')
    print(f'chunks        : {len(chunks)} (header says {declared_count})')
    print(f'bytes         : {actual_bytes} (header says {declared_bytes})')
    print(f'checksum      : {recomputed} (header says {declared_sum})')
    problems = []
    if missing:
        # Nothing to verify against is not the same as verified.
        problems.append('the header does not declare ' + ', '.join(missing)
                        + ', so this copy cannot be checked')
    if declared_count is not None and declared_count != len(chunks):
        problems.append('the chunk count does not match the header')
    if declared_bytes is not None and declared_bytes != actual_bytes:
        problems.append('the byte count does not match the header')
    if declared_sum is not None and declared_sum != recomputed:
        problems.append('the checksum does not match: this copy is truncated, reordered or edited')
    for problem in problems:
        print('PROBLEM:', problem)
    print('integrity     :', 'consistent' if not problems else 'NOT consistent')
    print('note          : a checksum match shows the text arrived whole. It is not')
    print('                authenticity, not proof of the producer, and not server evidence.')
    if ns.out:
        try:
            # The report is written back as the bytes it was stored as.
            pathlib.Path(ns.out).write_bytes(body.encode('utf-8', 'surrogateescape'))
        except OSError as error:
            raise SystemExit(f'{ns.out}: cannot be written: {error}')
        print(f'written       : {ns.out}')
    else:
        print('-' * 70)
        # A report from any realm can contain text the console encoding cannot
        # represent. Write the bytes and replace what the console cannot show,
        # instead of failing after the verification has already printed.
        encoding = getattr(sys.stdout, 'encoding', None) or 'utf-8'
        # Back to the original bytes first, then to whatever the console can
        # show, so a surrogate escape never reaches an encoder that rejects it.
        raw_body = body.encode('utf-8', 'surrogateescape')
        shown = raw_body.decode('utf-8', 'replace')
        sys.stdout.flush()
        buffer = getattr(sys.stdout, 'buffer', None)
        if buffer is not None:
            buffer.write(shown.encode(encoding, 'replace'))
            buffer.write(b'\n')
            buffer.flush()
        else:
            print(shown.encode(encoding, 'replace').decode(encoding, 'replace'))
    return 1 if problems else 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except ValueError as error:
        # Every refusal is a message, not a traceback.
        print(f'PROBLEM: this file is not a readable report: {error}')
        raise SystemExit(1)
