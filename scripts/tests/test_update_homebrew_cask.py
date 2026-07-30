import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "update_homebrew_cask.py"
OLD_SHA256 = "a" * 64
CASK_TEMPLATE = f"""cask "3mf-quicklook" do
  version "0.1.1"
  sha256 "{OLD_SHA256}"

  url "https://example.com/3MFQuickLook-#{{version}}.dmg"
  app "3MF QuickLook.app"
end
"""


class UpdateHomebrewCaskTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.cask = self.directory / "3mf-quicklook.rb"
        self.artifact = self.directory / "3MFQuickLook-0.2.0.dmg"
        self.cask.write_text(CASK_TEMPLATE, encoding="utf-8")
        self.artifact.write_bytes(b"deterministic release artifact")

    def run_updater(self, version: str = "0.2.0") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--cask",
                str(self.cask),
                "--version",
                version,
                "--artifact",
                str(self.artifact),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_updates_version_and_artifact_checksum(self) -> None:
        result = self.run_updater()

        self.assertEqual(result.returncode, 0, result.stderr)
        content = self.cask.read_text(encoding="utf-8")
        checksum = hashlib.sha256(self.artifact.read_bytes()).hexdigest()
        self.assertIn('  version "0.2.0"', content)
        self.assertIn(f'  sha256 "{checksum}"', content)

    def test_is_idempotent(self) -> None:
        first = self.run_updater()
        content_after_first_run = self.cask.read_text(encoding="utf-8")
        second = self.run_updater()

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(
            self.cask.read_text(encoding="utf-8"), content_after_first_run
        )
        self.assertIn("is already current", second.stdout)

    def test_rejects_non_release_version(self) -> None:
        original = self.cask.read_text(encoding="utf-8")
        result = self.run_updater("0.2")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("X.Y.Z", result.stderr)
        self.assertEqual(self.cask.read_text(encoding="utf-8"), original)

    def test_rejects_noncanonical_cask_without_modifying_it(self) -> None:
        self.cask.write_text(CASK_TEMPLATE.replace("  sha256", "sha256"), encoding="utf-8")
        original = self.cask.read_text(encoding="utf-8")
        result = self.run_updater()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("canonical sha256 stanza", result.stderr)
        self.assertEqual(self.cask.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
