"""The Cyrillic fallback must reach players with its original license."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_package as package

FONT = 'Fonts/DejaVuSans.ttf'
NOTICE = 'Fonts/LICENSE_DEJAVU.txt'


class CyrillicFontAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = package.committed_files()

    def test_font_and_permission_notice_are_shipped_together(self):
        self.assertIn(FONT, set(self.files))
        self.assertIn(NOTICE, set(self.files))
        self.assertFalse(package.check(self.files))

    def test_missing_font_or_license_is_refused(self):
        for path in (FONT, NOTICE):
            with self.subTest(path=path):
                files = dict(self.files)
                files.pop(path, None)
                self.assertTrue(any(path in problem for problem in package.check(files)))

    def test_altered_asset_is_refused(self):
        for path in (FONT, NOTICE):
            with self.subTest(path=path):
                files = dict(self.files)
                files[path] = b'not the approved asset'
                self.assertTrue(any(path in problem for problem in package.check(files)))

    def test_other_fonts_and_path_variants_are_not_admitted(self):
        for path in ('Fonts/other.ttf', 'fonts/DejaVuSans.ttf', 'Fonts/DEJAVUSANS.ttf'):
            with self.subTest(path=path):
                files = dict(self.files)
                files[path] = b'unexpected font'
                self.assertTrue(any(path in problem for problem in package.check(files)))

    def test_font_data_cannot_be_loaded_as_lua(self):
        files = dict(self.files)
        files['Nexus.toc'] += b'\nFonts\\DejaVuSans.ttf\n'
        self.assertTrue(any('font asset as code' in problem for problem in package.check(files)))


if __name__ == '__main__':
    unittest.main()
