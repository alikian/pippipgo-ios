"""Offline checks for complete UI language coverage and safe format arguments."""
import collections
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
LANGUAGES = {'en', 'fa', 'ja', 'es', 'fr', 'it', 'zh-Hans', 'ko', 'vi', 'fil', 'fil-PH', 'tr', 'ar', 'ru'}
TOKEN = re.compile(r'%(?:\d+\$)?(lld|ld|@|d|f|u)')


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.strings = json.loads((ROOT / 'pippipgo/Resources/Localizable.xcstrings').read_text())['strings']

    def test_every_entry_has_all_interface_languages(self):
        for key, entry in self.strings.items():
            if entry.get('shouldTranslate') is False:
                continue
            with self.subTest(key=key):
                self.assertTrue(LANGUAGES <= entry.get('localizations', {}).keys())
                for language in LANGUAGES:
                    unit = entry['localizations'][language]['stringUnit']
                    self.assertTrue(unit['value'].strip() or not key.strip())

    def test_translations_preserve_format_arguments(self):
        for key, entry in self.strings.items():
            expected = collections.Counter(TOKEN.findall(key))
            for language, localization in entry.get('localizations', {}).items():
                with self.subTest(key=key, language=language):
                    self.assertEqual(expected, collections.Counter(TOKEN.findall(localization['stringUnit']['value'])))

    def test_core_menus_are_not_english_fallbacks(self):
        keys = ['Trips', 'Translate', 'Profile', 'Settings', 'Save & Done',
                'Pip’s voice', 'My travel style', 'Delete account', 'Preview',
                'Start translation', 'Stop translating', 'Companions']
        for key in keys:
            for language in LANGUAGES - {'en'}:
                with self.subTest(key=key, language=language):
                    # These are explicit translations using the common borrowed UI term.
                    if (key, language) in {('Profile', 'fil'), ('Profile', 'fil-PH')}:
                        self.assertEqual('Profile', self.strings[key]['localizations'][language]['stringUnit']['value'])
                    else:
                        self.assertNotEqual(key, self.strings[key]['localizations'][language]['stringUnit']['value'])


if __name__ == '__main__':
    unittest.main()
