from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProfileBoundaries(unittest.TestCase):
    def test_launcher_storage_and_default_preferences_are_centralized(self):
        unexpected = []
        for file in (ROOT / 'Sources').rglob('*.swift'):
            if file.name == 'AppDataProfile.swift':
                continue
            source = file.read_text()
            if 'UserDefaults.standard' in source or re.search(r'UserDefaults\s*=\s*\.standard', source):
                unexpected.append(str(file.relative_to(ROOT)) + ': unscoped preferences')
            if re.search(r'\.appendingPathComponent\("Library/Application Support/NXLibrary(?:/|"|\-)', source):
                unexpected.append(str(file.relative_to(ROOT)) + ': unscoped launcher directory')
        self.assertEqual(unexpected, [], '\n'.join(unexpected))
