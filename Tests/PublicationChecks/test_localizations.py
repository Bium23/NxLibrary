import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/check_localizations.py'


class LocalizationChecks(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('check_localizations', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_missing_translation_and_changed_placeholder_are_rejected(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'Localizable.xcstrings'
            translations = {language: {'stringUnit': {'state': 'translated', 'value': 'Game %@'}}
                            for language in module.LANGUAGES}
            path.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {'Game %@': {'localizations': translations}}, 'version': '1.0'}))
            self.assertEqual(module.check_catalog(path), [])
            del translations['de']
            translations['it']['stringUnit']['value'] = 'Gioco %lld'
            path.write_text(json.dumps({'sourceLanguage': 'en', 'strings': {'Game %@': {'localizations': translations}}, 'version': '1.0'}))
            errors = module.check_catalog(path)
            self.assertTrue(any('de' in error for error in errors))
            self.assertTrue(any('placeholder' in error.lower() for error in errors))

    def test_empty_or_incomplete_bundle_is_rejected(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            errors = module.check_app(Path(root) / 'Missing.app')
            self.assertTrue(errors)
            self.assertTrue(any('bundle' in error.lower() or 'plist' in error.lower() for error in errors))

    def test_utf16_compiled_xml_with_utf8_declaration_is_accepted(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Game.app'
            info = app / 'Contents/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleLocalizations': list(module.LANGUAGES)}))
            for language in module.LANGUAGES:
                folder = app / 'Contents/Resources' / module.BUNDLE / 'Contents/Resources' / (language + '.lproj')
                folder.mkdir(parents=True)
                for name in ('Localizable.strings', 'Localizable.stringsdict'):
                    xml = plistlib.dumps({'test': 'translated'}).decode('utf-8').encode('utf-16')
                    (folder / name).write_bytes(xml)
            self.assertEqual(module.check_app(app), [])
