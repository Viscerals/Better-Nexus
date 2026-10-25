"""Offline fail-capable release branding controls; no network or publication."""
import unittest

from check_release_notes import BODY_SLOT, DEFAULT_TEMPLATE, normalized, validate


class ReleaseNotesChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = DEFAULT_TEMPLATE.read_bytes()
        cls.prefix = normalized(cls.template).partition(BODY_SLOT)[0]
        cls.body = b"## Experimental test\n\nUnrelated release notes remain unchanged.\n"
        cls.notes = cls.prefix + cls.body

    def test_valid_notes_preserve_input(self):
        before = self.notes
        self.assertEqual(validate(self.notes, self.template), [])
        self.assertEqual(self.notes, before)

    def test_crlf_checkout_and_notes(self):
        self.assertEqual(validate(self.notes.replace(b"\n", b"\r\n"),
                                  normalized(self.template).replace(b"\n", b"\r\n")), [])

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


if __name__ == "__main__":
    unittest.main()
