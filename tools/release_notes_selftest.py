"""Offline fail-capable release branding controls; no network or publication."""
import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_release_notes
from check_release_notes import BODY_SLOT, DEFAULT_TEMPLATE, main, normalized, validate

TOOLS_DIR = Path(__file__).resolve().parent
UNREADABLE = "Could not read release notes or template"


class ReleaseNotesChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = DEFAULT_TEMPLATE.read_bytes()
        cls.prefix = normalized(cls.template).partition(BODY_SLOT)[0]
        cls.body = b"## Experimental test\n\nUnrelated release notes remain unchanged.\n"
        cls.notes = cls.prefix + cls.body

    def setUp(self):
        # Each test writes its notes file in its own temporary directory outside the checkout.
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.workspace = Path(workspace.name)

    def write_notes(self, data):
        path = self.workspace / "release-notes.md"
        path.write_bytes(data)
        return path

    def run_main(self, path):
        """Call the checker CLI on one path; return its exit code, stdout and stderr."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main([str(path)])
        return code, out.getvalue(), err.getvalue()

    def assert_cli(self, data, expected_code, expected_start):
        """Check a real notes file through main(); the file and template bytes stay unchanged."""
        path = self.write_notes(data)
        code, out, err = self.run_main(path)
        self.assertEqual(code, expected_code)
        self.assertTrue(out.startswith(expected_start), out)
        self.assertNotIn("FAIL: " if expected_code == 0 else "PASS: ", out)
        self.assertEqual(err, "")
        self.assertEqual(path.read_bytes(), data)
        self.assertEqual(DEFAULT_TEMPLATE.read_bytes(), self.template)

    def assert_cli_unreadable(self, path):
        """main() leaves through parser.exit: SystemExit(2), message on stderr, nothing on stdout."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            with self.assertRaises(SystemExit) as caught:
                main([str(path)])
        self.assertEqual(caught.exception.code, 2)
        self.assertIn(UNREADABLE, err.getvalue())
        self.assertEqual(out.getvalue(), "")

    def test_valid_notes_preserve_input(self):
        self.assertEqual(validate(self.notes, self.template), [])
        self.assert_cli(self.notes, 0, "PASS: ")

    def test_crlf_checkout_and_notes(self):
        self.assertEqual(validate(self.notes.replace(b"\n", b"\r\n"),
                                  normalized(self.template).replace(b"\n", b"\r\n")), [])

    def test_lf_template_with_crlf_notes(self):
        lf_template = normalized(self.template)
        crlf_notes = self.notes.replace(b"\n", b"\r\n")
        self.assertNotIn(b"\r", lf_template)
        self.assertIn(b"\r\n", crlf_notes)
        self.assertEqual(validate(crlf_notes, lf_template), [])
        self.assertEqual(validate(self.notes, lf_template.replace(b"\n", b"\r\n")), [])
        self.assertTrue(validate(crlf_notes.replace(b"readme-banner.webp", b"MISSING", 1), lf_template))
        self.assert_cli(crlf_notes, 0, "PASS: ")

    def test_each_branding_element_is_required(self):
        elements = [b"readme-banner.webp", b"Plan your Echoes. Shape your build.",
                    b"Experimental public beta", b"Latest public beta release",
                    b"CI status on main", b"License: Source-Available", b"WoW: 3.3.5a",
                    b"Downloads &amp; release notes", b"Documentation", b"Report a problem",
                    b"Support on Ko-fi", b"Project links and live badges"]
        for element in elements:
            with self.subTest(element=element):
                self.assertIn(element, self.prefix)
                self.assertTrue(validate(self.notes.replace(element, b"MISSING", 1), self.template))

    def test_destinations_and_asset_pin_are_required(self):
        for value in [b"https://github.com/Viscerals/Better-Nexus/releases",
                      b"https://viscerals.github.io/Better-Nexus/",
                      b"https://github.com/Viscerals/Better-Nexus/issues/new/choose",
                      b"https://ko-fi.com/valentineb",
                      b"8eb6a3ae5e96e1a4ded8b75d944fd8147649e139"]:
            with self.subTest(value=value):
                self.assertTrue(validate(self.notes.replace(value, b"WRONG", 1), self.template))

    def test_missing_or_duplicate_prefix(self):
        self.assertTrue(validate(self.body, self.template))
        self.assertTrue(validate(self.prefix + self.notes, self.template))

    def test_placeholder_or_empty_body(self):
        self.assertTrue(validate(self.template, self.template))
        self.assertTrue(validate(self.prefix + b" \n", self.template))

    def test_corrupted_template_is_not_its_own_authority(self):
        altered = self.template.replace(b"readme-banner.webp", b"other.webp")
        self.assertTrue(validate(altered.replace(BODY_SLOT, self.body), altered))
        self.assertTrue(validate(self.notes, self.template.replace(BODY_SLOT, b"")))

    def test_cli_fails_invalid_or_missing_branding(self):
        cases = [("no branding prefix", self.body),
                 ("banner removed", self.notes.replace(b"readme-banner.webp", b"MISSING", 1)),
                 ("disclaimer removed", self.notes.replace(b"Project links and live badges", b"MISSING", 1)),
                 ("placeholder kept", normalized(self.template)),
                 ("no release-specific notes", self.prefix),
                 ("UTF-8 byte-order mark", b"\xef\xbb\xbf" + self.notes)]
        for name, data in cases:
            with self.subTest(case=name):
                self.assertNotEqual(data, self.notes)
                self.assert_cli(data, 1, "FAIL: ")

    def test_cli_unreadable_notes_path_exits_2(self):
        missing = self.workspace / "absent-notes.md"
        for name, path in [("missing file", missing), ("directory", self.workspace)]:
            with self.subTest(case=name):
                self.assert_cli_unreadable(path)
        self.assertFalse(missing.exists())
        self.assertEqual(DEFAULT_TEMPLATE.read_bytes(), self.template)

    def test_cli_unreadable_default_template_exits_2(self):
        path = self.write_notes(self.notes)
        absent = self.workspace / "absent-template.md"
        with mock.patch.object(check_release_notes, "DEFAULT_TEMPLATE", absent):
            self.assert_cli_unreadable(path)
        self.assertEqual(path.read_bytes(), self.notes)
        self.assertFalse(absent.exists())

    def test_default_template_resolves_from_checker_not_cwd(self):
        self.assertEqual(DEFAULT_TEMPLATE, TOOLS_DIR.parent / "docs" / "RELEASE_NOTES_TEMPLATE.md")
        path = self.write_notes(self.notes)
        previous = os.getcwd()
        os.chdir(str(self.workspace))
        try:
            self.assertFalse(Path("docs", "RELEASE_NOTES_TEMPLATE.md").exists())
            code, out, err = self.run_main(path)
        finally:
            os.chdir(previous)
        self.assertEqual((code, err), (0, ""))
        self.assertTrue(out.startswith("PASS: "), out)
        self.assertEqual(path.read_bytes(), self.notes)


if __name__ == "__main__":
    unittest.main()
