"""Release gates fail closed and ship source-bound, checksummed host records."""
import copy
import json
import pathlib
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HOST = runpy.run_path(str(ROOT / ".github/scripts/host_evidence.py"))


def record(commit="a" * 40):
    return {
        "schemaVersion": 1, "testedCommit": commit, "omarchyCommit": "b" * 40,
        "architecture": "x86_64", "checks": {name: True for name in HOST["REQUIRED_CHECKS"]},
        "notes": "Fictional unit-test record, not evidence of live Omarchy testing.",
    }


class ReleaseEvidenceTests(unittest.TestCase):
    def test_missing_stale_or_incomplete_acceptance_is_rejected(self):
        valid = record()
        self.assertEqual(HOST["validate"](valid, "a" * 40), valid)
        invalid = [None, {}, {**valid, "testedCommit": "c" * 40},
                   {**valid, "omarchyCommit": "short"}, {**valid, "architecture": "aarch64"},
                   {**valid, "checks": {}}, {**valid, "notes": ""}]
        for value in (False, "true", 1):
            changed = copy.deepcopy(valid)
            changed["checks"][HOST["REQUIRED_CHECKS"][0]] = value
            invalid.append(changed)
        for candidate in invalid:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                HOST["validate"](candidate, "a" * 40)

    def test_host_record_is_verified_and_included_in_checksum_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "source"
            source.mkdir()
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=source, stderr=subprocess.DEVNULL).decode().strip()
            git("init")
            (source / "manifest.json").write_text('{"version":"0.3.4"}\n')
            git("add", "manifest.json")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "-m", "Fictional release source")
            commit = git("rev-parse", "HEAD")
            evidence = root / "host.json"
            evidence.write_text(json.dumps(record(commit)))
            assets = root / "assets"
            script = ROOT / ".github/scripts/release.py"
            result = subprocess.run([sys.executable, str(script), "build", str(assets),
                "--host-evidence", str(evidence)], cwd=source, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((assets / "RELEASE-MANIFEST.json").read_text())
            self.assertIn("HOST-ACCEPTANCE.json", [d["name"] for d in manifest["releaseDocuments"]])
            self.assertIn("HOST-ACCEPTANCE.json", (assets / "SHA256SUMS").read_text())
            (assets / "HOST-ACCEPTANCE.json").write_text(json.dumps(record("c" * 40)))
            result = subprocess.run([sys.executable, str(script), "verify", str(assets)],
                cwd=source, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exact release candidate", result.stderr)


if __name__ == "__main__":
    unittest.main()
