#!/usr/bin/env python3
"""Fixture tests for tools/l10n_inventory.py, through its command line only.

    python tools/tests/test_l10n_inventory.py -v

Each case writes a small self-contained Lua fixture into a fresh temporary
directory, runs the inventory tool with --root set to that directory and reads
its stdout: one ASCII JSON object per line. A literal record carries at least
"record": "literal", "path" (POSIX, relative to --root), "line" and "column"
(1-based, at the opening delimiter) and "text" (the decoded string value).

A string whose value is not valid UTF-8 (only decimal escapes in a UTF-8 file
can make one) is a bytes record instead: "record": "bytes", "path", "line",
"column" and "hex" (its exact bytes, two lowercase hexadecimal digits each),
with no "text". It is listed, not converted to text and not dropped.

An invalid request exits 1 with empty stdout and exactly one ASCII JSON line on
stderr: "record": "error", "error" (a stable code), "path" (the PATH argument
as given) and "message" (1 to 200 characters). An unfinished string or comment
also carries "line" and "column" where it starts.

No case reads or changes the addon source. Python 3.9+, standard library only.
"""
from __future__ import annotations
import json, pathlib, subprocess, sys, tempfile, types, unittest

TOOL = pathlib.Path(__file__).resolve().parents[1] / 'l10n_inventory.py'


def encoded(data) -> bytes:
    """Fixture content as bytes: text as UTF-8, bytes as they are."""
    return data if isinstance(data, bytes) else data.encode('utf-8')


def snapshot(base: pathlib.Path) -> dict:
    """Every file under base (POSIX path relative to base -> bytes)."""
    return {p.relative_to(base).as_posix(): p.read_bytes()
            for p in sorted(base.rglob('*')) if p.is_file()}


def run_inventory(files: dict, *paths: str) -> types.SimpleNamespace:
    """Write files (path relative to the root -> exact text or bytes, no newline
    translation) under a fresh root inside a fresh directory, and run the tool on
    the given paths relative to that root. A '../' file lands beside the root.
    Returns returncode, stdout, stderr, and every file in the directory before
    and after the run."""
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        root = base / 'root'
        root.mkdir()
        for name, data in files.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(encoded(data))
        before = snapshot(base)
        run = subprocess.run([sys.executable, str(TOOL), '--root', str(root), *paths],
                             capture_output=True, encoding='utf-8', errors='replace')
        return types.SimpleNamespace(returncode=run.returncode, stdout=run.stdout,
                                     stderr=run.stderr, before=before, after=snapshot(base))


def literals(stdout: str) -> list:
    """(path, line, column, text) of every literal record, in output order."""
    rows = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    return [(r['path'], r['line'], r['column'], r['text'])
            for r in rows if r.get('record') == 'literal']


class ShortStringTests(unittest.TestCase):
    def test_each_short_string_is_listed_with_its_location_and_text(self):
        run = run_inventory({'ui/Sample.lua': 'local title = "Wishlist editor"\n'
                                              "print('Saved')\n"}, 'ui/Sample.lua')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(literals(run.stdout), [('ui/Sample.lua', 1, 15, 'Wishlist editor'),
                                                ('ui/Sample.lua', 2, 7, 'Saved')])


# Valid Lua 5.1 with CRLF line ends, as *.lua files are checked out (.gitattributes).
# Lua 5.1 rules it relies on: comments hold no literals; an escaped line break and
# every line break inside a long string become "\n"; a long string drops a line break
# directly after its opening bracket and keeps backslashes; a decimal escape reads at
# most three digits; only the bracket of the same level closes a long string.
LEXER_LINES = (
    r'''-- Synthetic lexer fixture: "comment" and 'quotes' are not literals''',
    r'''local plain = "a -- b" -- trailing "comment"''',
    r'''--[[ long comment "hidden"''',
    r"""still 'hidden' ]] local after = 'after long comment'""",
    r'''--[==[ level two ]] "hidden" ]==]''',
    r'''local escaped = "say \"hi\"\tand \\ \'ok\'"''',
    r'''local tail = "ends with backslash\\"''',
    r'''local code = "\124cff00ff00ok\124r \0491"''',
    r'''local fmt = "|cffffd200Nexus:|r %d / %d (%s%%)"''',
    'local wrapped = "first\\',
    r'''second"''',
    r'''local help = [[''',
    r'''Line "one"''',
    r'''C:\path\n stays]]''',
    r'''local deep = [==[ has ]] and ]=] inside ]==]''',
    r'''print(t[1], "[[not long]]")''',
)


class LexerStateTests(unittest.TestCase):
    def test_comments_escapes_and_long_brackets_follow_lua_5_1_lexing(self):
        run = run_inventory({'ui/Lexer.lua': '\r\n'.join(LEXER_LINES) + '\r\n'}, 'ui/Lexer.lua')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(literals(run.stdout), [
            ('ui/Lexer.lua', 2, 15, 'a -- b'),
            ('ui/Lexer.lua', 4, 33, 'after long comment'),
            ('ui/Lexer.lua', 6, 17, 'say "hi"\tand \\ \'ok\''),
            ('ui/Lexer.lua', 7, 14, 'ends with backslash\\'),
            ('ui/Lexer.lua', 8, 14, '|cff00ff00ok|r 11'),
            ('ui/Lexer.lua', 9, 13, '|cffffd200Nexus:|r %d / %d (%s%%)'),
            ('ui/Lexer.lua', 10, 17, 'first\nsecond'),
            ('ui/Lexer.lua', 12, 14, 'Line "one"\nC:\\path\\n stays'),
            ('ui/Lexer.lua', 15, 14, ' has ]] and ]=] inside '),
            ('ui/Lexer.lua', 16, 13, '[[not long]]'),
        ])


class ByteStringTests(unittest.TestCase):
    # ASCII source. Line 1 has the form of the UTF-8 continuation-byte pattern at
    # ui/LayoutMetrics.lua:215: "[\128-\191]" is the bytes 5b 80 2d bf 5d, which are
    # not UTF-8. Line 2's escapes are the UTF-8 bytes of U+2014, so it stays text.
    def test_escaped_bytes_that_are_not_utf8_are_a_bytes_record_not_text(self):
        source = ('local w = #(word:gsub("[\\128-\\191]", "")) * char\n'
                  'local dash = "\\226\\128\\148"\n')
        run = run_inventory({'ui/Bytes.lua': source}, 'ui/Bytes.lua')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, '')
        rows = [json.loads(line) for line in run.stdout.splitlines() if line.strip()]
        self.assertEqual([(r.get('record'), r.get('path'), r.get('line'), r.get('column'),
                           r.get('text'), r.get('hex')) for r in rows], [
            ('bytes', 'ui/Bytes.lua', 1, 23, None, '5b802dbf5d'),
            ('literal', 'ui/Bytes.lua', 1, 38, '', None),
            ('literal', 'ui/Bytes.lua', 2, 14, '—', None),
        ])


# Each request lists a valid file first, so any record on stdout would be a
# partial inventory. (case, further fixture files, invalid PATH, expected fields)
GOOD = 'local greeting = "Hello"\n'
INVALID_CASES = (
    ('missing file', {}, 'ui/Missing.lua', {'error': 'missing'}),
    ('outside --root', {'../Outside.lua': 'local a = "outside"\n'}, '../Outside.lua',
     {'error': 'outside-root'}),
    ('not a .lua file', {'ui/Notes.txt': 'local a = "notes"\n'}, 'ui/Notes.txt',
     {'error': 'unsupported'}),
    ('not UTF-8', {'ui/Latin1.lua': b'local a = "caf\xe9"\n'}, 'ui/Latin1.lua',
     {'error': 'not-utf8'}),
    ('unfinished string', {'ui/Open.lua': 'local a = "fine"\nlocal b = "open\nlocal c = 1\n'},
     'ui/Open.lua', {'error': 'unfinished-string', 'line': 2, 'column': 11}),
    ('unfinished long comment', {'ui/Comment.lua': 'local a = "fine"\n--[==[ never closed ]]\n'},
     'ui/Comment.lua', {'error': 'unfinished-comment', 'line': 2, 'column': 1}),
)


class InvalidInputTests(unittest.TestCase):
    def test_invalid_input_gives_one_json_error_no_inventory_and_unchanged_files(self):
        for case, extra, path, expected in INVALID_CASES:
            with self.subTest(case):
                run = run_inventory({'ui/Good.lua': GOOD, **extra}, 'ui/Good.lua', path)
                self.assertEqual(run.returncode, 1, run.stderr)
                self.assertEqual(run.stdout, '')
                lines = run.stderr.splitlines()
                self.assertEqual(len(lines), 1, run.stderr)
                self.assertTrue(lines[0].isascii(), lines[0])
                try:
                    record = json.loads(lines[0])
                except ValueError:
                    self.fail('stderr is not one JSON object: ' + lines[0][:500])
                self.assertIsInstance(record, dict)
                wanted = {'record': 'error', 'path': path, **expected}
                self.assertEqual({key: record.get(key) for key in wanted}, wanted)
                message = record.get('message')
                self.assertIsInstance(message, str)
                self.assertTrue(0 < len(message) <= 200, message)
                self.assertEqual(run.after, run.before)


if __name__ == '__main__':
    unittest.main()
