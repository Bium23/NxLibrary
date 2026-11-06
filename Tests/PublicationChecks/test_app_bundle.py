from pathlib import Path
import re
import unittest


BUILD_APP = Path(__file__).resolve().parents[2] / "scripts/build_app.sh"


class AppBundleInfo(unittest.TestCase):
    def test_launcher_opts_out_of_game_mode(self):
        # NX Library declares the games category, so macOS would put the launcher
        # itself in Game Mode; the engine opts each game out for the same reason.
        script = BUILD_APP.read_text()
        self.assertIn("public.app-category.games", script)
        self.assertRegex(script, re.compile(r"<key>LSSupportsGameMode</key>\s*<false/>"))


if __name__ == "__main__":
    unittest.main()
