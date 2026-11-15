#!/usr/bin/env python3
"""Fixture tests for tools/l10n_inventory.py, through its public entry points.

    python tools/tests/test_l10n_inventory.py -v

Each case writes a small self-contained Lua fixture into a fresh temporary
directory, runs the inventory tool with --root set to that directory and reads
its stdout: one ASCII JSON object per line. A literal record carries at least
"record": "literal", "path" (POSIX, relative to --root), "line" and "column"
(1-based, at the opening delimiter, counted in characters) and "text" (the
decoded string value). Records follow the PATH argument order, then source
order within each file. A successful run changes no file, and repeating it
gives byte-identical output.

A string whose value is not valid UTF-8 (only decimal escapes in a UTF-8 file
can make one) is a bytes record instead: "record": "bytes", "path", "line",
"column" and "hex" (its exact bytes, two lowercase hexadecimal digits each),
with no "text". It is listed, not converted to text and not dropped.

An invalid request exits 1 with empty stdout and exactly one ASCII JSON line on
stderr: "record": "error", "error" (a stable code), "path" (the PATH argument
as given) and "message" (1 to 200 characters). An unfinished string or comment
or a decimal escape above 255 also carries "line" and "column" where its token
starts. An OS error while --root or a PATH is resolved, checked or read is
"unreadable"; when --root cannot be resolved, "path" is the first PATH.

Usage errors that argparse finds (no PATH, an unknown option) are not invalid
requests: they keep argparse's usage message on stderr and exit status 2. No
case checks that boundary.

Every case runs the tool's command line except the OS-error cases. No real
filesystem fault is portable, so each of those starts an isolated Python that
loads the tool, makes one pathlib.Path operation raise OSError for one file or
directory name, and calls the tool's public main() with the same arguments.

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


def write_root(base: pathlib.Path, files: dict) -> pathlib.Path:
    """Write files (path relative to the root -> exact text or bytes, no newline
    translation) under a fresh root inside base and return the root. A '../'
    file lands beside the root."""
    root = base / 'root'
    root.mkdir()
    for name, data in files.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(encoded(data))
    return root


def run_inventory(files: dict, *paths: str,
                  command: tuple = (str(TOOL),)) -> types.SimpleNamespace:
    """Write files (path relative to the root -> exact text or bytes, no newline
    translation) under a fresh root inside a fresh directory, and run the tool on
    the given paths relative to that root. A '../' file lands beside the root.
    Returns returncode, stdout, stderr, and every file in the directory before
    and after the run. command is what the Python interpreter is given before
    --root: the tool's script unless a case replaces it (see run_with_fault)."""
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        root = write_root(base, files)
        before = snapshot(base)
        run = subprocess.run([sys.executable, *command, '--root', str(root), *paths],
                             capture_output=True, encoding='utf-8', errors='replace')
        return types.SimpleNamespace(returncode=run.returncode, stdout=run.stdout,
                                     stderr=run.stderr, before=before, after=snapshot(base))


def run_inventory_twice(files: dict, *paths: str) -> types.SimpleNamespace:
    """Write files as run_inventory does and run the tool twice on them. Returns
    each run's exact (returncode, stdout bytes, stderr bytes), and every file in
    the directory before the first run and after the second."""
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        root = write_root(base, files)
        before = snapshot(base)
        command = [sys.executable, str(TOOL), '--root', str(root), *paths]
        runs = [subprocess.run(command, capture_output=True) for _ in range(2)]
        results = [(run.returncode, run.stdout, run.stderr) for run in runs]
        return types.SimpleNamespace(runs=results, before=before, after=snapshot(base))


def json_lines(stdout: str) -> list:
    """Every non-blank stdout line, parsed as JSON, in output order."""
    return [json.loads(line) for line in stdout.splitlines() if line.strip()]


def fields(record: dict) -> tuple:
    """(record, path, line, column, text, hex) of one output record, None for a
    field it lacks. Compared whole, these leave no record kind unseen."""
    return tuple(record.get(key) for key in ('record', 'path', 'line', 'column', 'text', 'hex'))


def literals(stdout: str) -> list:
    """(path, line, column, text) of every record, in output order. Each must be
    a literal record: a bytes or any other record fails the case here instead of
    being left out silently."""
    rows = json_lines(stdout)
    others = [r for r in rows if r.get('record') != 'literal']
    if others:
        raise AssertionError('records that are not literals: ' + json.dumps(others)[:500])
    return [(r['path'], r['line'], r['column'], r['text']) for r in rows]


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


# Columns count characters, not bytes or UTF-16 units: line 1's second literal
# starts at character 26 (byte 32, UTF-16 unit 27) and line 2's literal, after
# a long comment, at character 22 (byte 24).
WIDE_SOURCE = ('local a, b = "caf\u00e9 \u2014 \U0001f600", "next"\n'
               '--[[ \u00fc\u00fc ]] local c = "\u00e9t\u00e9"\n')
WIDE_ROWS = [
    ('literal', 'ui/Wide.lua', 1, 14, 'caf\u00e9 \u2014 \U0001f600', None),
    ('literal', 'ui/Wide.lua', 1, 26, 'next', None),
    ('literal', 'ui/Wide.lua', 2, 22, '\u00e9t\u00e9', None),
]


class Utf8ColumnTests(unittest.TestCase):
    def test_columns_count_characters_after_multibyte_utf8_text(self):
        run = run_inventory({'ui/Wide.lua': WIDE_SOURCE}, 'ui/Wide.lua')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, '')
        self.assertEqual([fields(r) for r in json_lines(run.stdout)], WIDE_ROWS)


# PATHs out of name order; each file's literals out of text order; a bytes
# record ("\200" is the lone byte c8, not UTF-8) between two literal ones.
ORDER_FILES = {
    'core/Alpha.lua': 'local a = [[bravo]] .. "\\200" .. "alpha"\n',
    'ui/Zeta.lua': 'print("zulu", "yankee")\nlocal x = "xray"\n',
    'ui/Wide.lua': WIDE_SOURCE,
}
ORDER_PATHS = ('ui/Zeta.lua', 'core/Alpha.lua', 'ui/Wide.lua')
ORDER_ROWS = [
    ('literal', 'ui/Zeta.lua', 1, 7, 'zulu', None),
    ('literal', 'ui/Zeta.lua', 1, 15, 'yankee', None),
    ('literal', 'ui/Zeta.lua', 2, 11, 'xray', None),
    ('literal', 'core/Alpha.lua', 1, 11, 'bravo', None),
    ('bytes', 'core/Alpha.lua', 1, 24, None, 'c8'),
    ('literal', 'core/Alpha.lua', 1, 34, 'alpha', None),
    *WIDE_ROWS,
]


class SuccessfulRunTests(unittest.TestCase):
    def test_files_follow_path_order_literals_follow_source_order_and_no_file_changes(self):
        run = run_inventory(ORDER_FILES, *ORDER_PATHS)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, '')
        self.assertEqual([fields(r) for r in json_lines(run.stdout)], ORDER_ROWS)
        self.assertEqual(run.after, run.before)

    def test_a_repeated_run_prints_the_same_ascii_json_lines_byte_for_byte(self):
        result = run_inventory_twice(ORDER_FILES, *ORDER_PATHS)
        (code, out, err), (again_code, again_out, again_err) = result.runs
        self.assertEqual((code, err), (0, b''), err)
        self.assertEqual((again_code, again_err), (0, b''), again_err)
        self.assertEqual(again_out, out)
        self.assertTrue(out.isascii(), out[:500])
        records = [json.loads(line) for line in out.decode('ascii').splitlines()]
        self.assertTrue(all(isinstance(r, dict) for r in records), out[:500])
        self.assertEqual([fields(r) for r in records], ORDER_ROWS)
        self.assertEqual(result.after, result.before)


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
    ('unfinished long string', {'ui/Long.lua': 'local a = "fine"\nlocal b = [==[ open ]] ]=]\n'},
     'ui/Long.lua', {'error': 'unfinished-string', 'line': 2, 'column': 11}),
    # Line 1's "\255" is the largest valid decimal escape; the error is at the
    # opening quote of the string token that holds "\256".
    ('decimal escape above 255', {'ui/Escape.lua': 'local a = "\\255"\nlocal b = "ok \\256"\n'},
     'ui/Escape.lua', {'error': 'invalid-escape', 'line': 2, 'column': 11}),
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


# The OS-error cases run this in a separate isolated Python (-I -B). It loads
# the tool from its file, makes pathlib.Path.<operation> raise OSError for
# every path whose final component is <name> and calls the tool's main() with
# the remaining arguments. Nothing else is replaced; no file permission is
# changed and no bytecode is written.
FAULT_DRIVER = '''\
import errno, importlib.util, pathlib, sys
tool, operation, name, argv = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
spec = importlib.util.spec_from_file_location('l10n_inventory_under_test', tool)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
real = getattr(pathlib.Path, operation)
def failing(self, *args, **kwargs):
    if self.name == name:
        raise OSError(errno.EACCES, 'injected filesystem fault', str(self))
    return real(self, *args, **kwargs)
setattr(pathlib.Path, operation, failing)
raise SystemExit(module.main(argv))
'''


def run_with_fault(operation: str, name: str, files: dict, *paths: str) -> types.SimpleNamespace:
    """run_inventory through FAULT_DRIVER, with pathlib.Path.<operation> failing
    for every path whose final component is name."""
    return run_inventory(files, *paths,
                         command=('-I', '-B', '-c', FAULT_DRIVER, str(TOOL), operation, name))


# A valid file comes first, so any record on stdout would be a partial inventory.
# The failing PATH is given in a non-normal form, which the error must keep.
# Reading the file is the fault the tool already handled; the others hit the
# operations around it. (case, failing operation, final name, PATH named)
FAULT = 'ui/../ui/Fault.lua'
FAULT_FILES = {'ui/Good.lua': GOOD, 'ui/Fault.lua': 'local fault = "Fault"\n'}
FAULT_CASES = (
    ('reading PATH', 'read_bytes', 'Fault.lua', FAULT),
    ('resolving PATH', 'resolve', 'Fault.lua', FAULT),
    ('checking that PATH exists', 'exists', 'Fault.lua', FAULT),
    ('checking that PATH is a file', 'is_file', 'Fault.lua', FAULT),
    ('resolving --root', 'resolve', 'root', 'ui/Good.lua'),
)


class FileSystemErrorTests(unittest.TestCase):
    def test_an_os_error_on_root_or_path_is_one_unreadable_error_and_no_inventory(self):
        # Failing only for a name no request uses, the harness is a plain run.
        control = run_with_fault('read_bytes', 'Unused.lua', FAULT_FILES, 'ui/Good.lua', FAULT)
        self.assertEqual(control.returncode, 0, control.stderr)
        self.assertEqual(control.stderr, '')
        self.assertEqual(literals(control.stdout), [
            ('ui/Good.lua', 1, 18, 'Hello'),
            ('ui/Fault.lua', 1, 15, 'Fault'),
        ])
        for case, operation, name, path in FAULT_CASES:
            with self.subTest(case):
                run = run_with_fault(operation, name, FAULT_FILES, 'ui/Good.lua', FAULT)
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
                wanted = {'record': 'error', 'error': 'unreadable', 'path': path}
                self.assertEqual({key: record.get(key) for key in wanted}, wanted)
                self.assertNotIn('line', record)
                self.assertNotIn('column', record)
                message = record.get('message')
                self.assertIsInstance(message, str)
                self.assertTrue(0 < len(message) <= 200, message)
                self.assertEqual(run.after, run.before)


if __name__ == '__main__':
    unittest.main()
