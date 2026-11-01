import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check_publication.py"


class PublicationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="NXPublication-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def track(self, name, content):
        file = self.root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        subprocess.run(["git", "add", "--", name], cwd=self.root, check=True)

    def scan(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], cwd=self.root,
                              capture_output=True, text=True)

    def test_source_referencing_a_game_file_is_allowed(self):
        self.track("Sources/Example.swift", 'let name = "Game.NSP"\n')
        self.assertEqual(self.scan().returncode, 0)

    def test_game_and_private_output_files_are_rejected_by_path(self):
        for name in ["Games/Game.NSP", "reports/private.md", "docs/audits/local.md",
                     "docs/superpowers/plans/plan.md", "docs/upstream-issues/note.md",
                     "Resources/Selene/Wallpapers/theme/one.jpg"]:
            with self.subTest(name=name):
                self.track(name, "synthetic")
                result = self.scan()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stdout)

    def test_key_material_is_rejected_without_echoing_its_value(self):
        value = "01" * 32
        self.track("notes.txt", "header_key = " + value)
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("notes.txt", result.stdout)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_untracked_personal_files_are_not_read(self):
        (self.root / "prod.keys").write_text("header_key = " + "01" * 32)
        self.track("README.md", "Source code only.")
        self.assertEqual(self.scan().returncode, 0)

    def test_runtime_must_match_the_exact_lock(self):
        lock = {"python": {"version": "3.14.6"}, "wheels": [], "brew": []}
        data = json.dumps(lock).encode()
        (self.root / "runtime.lock").write_bytes(data)
        runtime = self.root / "runtime"
        runtime.mkdir()
        for path in ["python/bin/python3", "bin/zstd", "bin/glslangValidator"]:
            file = runtime / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")
            file.chmod(0o755)
        (runtime / "licenses").mkdir()
        manifest = {"python": "3.14.6", "lock": hashlib.sha256(data).hexdigest()}
        (runtime / "versions.json").write_text(json.dumps(manifest))
        self.assertEqual(self.scan("--runtime", str(runtime)).returncode, 0)
        (self.root / "runtime.lock").write_bytes(data + b"\n")
        result = self.scan("--runtime", str(runtime))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runtime", result.stdout.lower())


if __name__ == "__main__":
    unittest.main()
