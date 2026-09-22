"""Regressions for unsafe cache files and aggregate history storage."""
import fcntl
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from test_fetch_quotes import fetch_quotes, ROOT, FakeResponse, yahoo_payload


class CacheHardeningTests(unittest.TestCase):
    def test_previous_release_cache_survives_update_and_offline_fallback(self):
        fixture = json.loads((ROOT / "tests/fixtures/v0.3.3-state.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes-v1.json"
            path.write_text(json.dumps(fixture["cache"]))
            path.chmod(0o600)
            document = fetch_quotes.fetch_quotes(["AAPL"], cache_file=path,
                now_epoch=1_700_000_030, opener=lambda *a, **k: FakeResponse(b"offline"))
            self.assertEqual(document["status"], "partial")
            quote = document["quotes"][0]
            self.assertTrue(quote["cached"])
            self.assertEqual(quote["cacheAgeSec"], 30)
            self.assertEqual(quote["regularMarketPrice"], 102)

    def test_fifo_is_rejected_without_waiting_for_a_writer(self):
        # Run the production read in a subprocess so a regression cannot hang CI.
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            os.mkfifo(path, 0o600)
            code = (
                "import runpy,pathlib; m=runpy.run_path(%r); "
                "assert m['_load_cache_entries'](pathlib.Path(%r)) == {}"
            ) % (str(ROOT / "scripts/fetch_quotes.py"), str(path))
            result = subprocess.run([sys.executable, "-I", "-S", "-c", code],
                                    capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_read_refuses_permissive_file_hardlink_and_nonprivate_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = pathlib.Path(directory)
            path = parent / "quotes.json"
            path.write_bytes(b"{}")
            path.chmod(0o644)
            with self.assertRaises(fetch_quotes.FetchFailure):
                fetch_quotes._read_cache_bytes(path)
            path.chmod(0o600)
            os.link(path, parent / "link.json")
            with self.assertRaises(fetch_quotes.FetchFailure):
                fetch_quotes._read_cache_bytes(path)
            (parent / "link.json").unlink()
            parent.chmod(0o755)
            with self.assertRaises(fetch_quotes.FetchFailure):
                fetch_quotes._read_cache_bytes(path)
            parent.chmod(0o700)
            self.assertEqual(fetch_quotes._read_cache_bytes(path), b"{}")

    def test_read_refuses_file_owned_by_another_uid(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            fetch_quotes._write_cache_bytes(path, b"{}")
            original = os.fstat

            def foreign_file(fd):
                metadata = original(fd)
                if fetch_quotes.stat.S_ISREG(metadata.st_mode):
                    fields = list(metadata)
                    fields[4] = os.getuid() + 1
                    return os.stat_result(fields)
                return metadata

            with patch.object(fetch_quotes.os, "fstat", side_effect=foreign_file):
                with self.assertRaises(fetch_quotes.FetchFailure):
                    fetch_quotes._read_cache_bytes(path)

    def test_busy_cache_does_not_delay_or_fail_fresh_quotes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "quotes.json"
            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                document = fetch_quotes.fetch_quotes(["AAPL"], cache_file=path,
                    opener=lambda *a, **k: FakeResponse(json.dumps(yahoo_payload()).encode()))
                self.assertEqual(document["status"], "ready")
                self.assertFalse(path.exists())
            finally:
                os.close(fd)

    def test_history_count_budget_evicts_oldest_across_watchlists(self):
        with tempfile.TemporaryDirectory() as directory:
            history = pathlib.Path(directory) / "history"
            for index in range(fetch_quotes.MAX_HISTORY_FILES + 9):
                path = history / f"SYM{index}-1y-v1.json"
                fetch_quotes._write_cache_bytes(path, b"{}")
                os.utime(path, (time.time() - 1000 + index, time.time() - 1000 + index))
                self.assertLessEqual(len(list(history.iterdir())), fetch_quotes.MAX_HISTORY_FILES)
            self.assertFalse((history / "SYM0-1y-v1.json").exists())
            self.assertTrue((history / "SYM68-1y-v1.json").exists())

    def test_history_byte_budget_includes_temporary_replacement(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(fetch_quotes, "MAX_HISTORY_BYTES", 12):
            history = pathlib.Path(directory) / "history"
            first = history / "AAPL-1y-v1.json"
            second = history / "MSFT-1y-v1.json"
            fetch_quotes._write_cache_bytes(first, b"123456")
            os.utime(first, (time.time() - 10, time.time() - 10))
            fetch_quotes._write_cache_bytes(second, b"654321")
            fetch_quotes._write_cache_bytes(second, b"abcdef")
            self.assertFalse(first.exists())
            self.assertEqual(second.read_bytes(), b"abcdef")
            self.assertLessEqual(sum(p.stat().st_size for p in history.iterdir()), 12)

    def test_history_expiry_and_abandoned_writes_preserve_unrelated_files(self):
        with tempfile.TemporaryDirectory() as directory:
            history = pathlib.Path(directory) / "history"
            old = history / "AAPL-5d-v1.json"
            fetch_quotes._write_cache_bytes(old, b"{}")
            expired = time.time() - fetch_quotes.CACHE_HISTORY_MAX_AGE_SECONDS - 1
            os.utime(old, (expired, expired))
            abandoned = history / ".AAPL-5d-v1.json.123.0123456789abcdef.tmp"
            abandoned.write_bytes(b"partial")
            abandoned.chmod(0o600)
            unrelated = history / "keep.txt"
            unrelated.write_text("sentinel")
            fetch_quotes._write_cache_bytes(history / "MSFT-1y-v1.json", b"{}")
            self.assertFalse(old.exists())
            self.assertFalse(abandoned.exists())
            self.assertEqual(unrelated.read_text(), "sentinel")

    def test_history_symlink_disables_persistence_without_touching_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target = root / "target"
            target.write_text("sentinel")
            history = root / "history"
            history.mkdir(mode=0o700)
            (history / "AAPL-1y-v1.json").symlink_to(target)
            fetch_quotes._store_cache_entries(history / "MSFT-1y-v1.json", {})
            self.assertFalse((history / "MSFT-1y-v1.json").exists())
            self.assertTrue((history / "AAPL-1y-v1.json").is_symlink())
            self.assertEqual(target.read_text(), "sentinel")

    def test_excessive_directory_scan_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(fetch_quotes, "MAX_HISTORY_SCAN_ENTRIES", 2):
            history = pathlib.Path(directory) / "history"
            history.mkdir(mode=0o700)
            for index in range(3):
                (history / f"unrelated{index}").write_bytes(b"sentinel")
            fetch_quotes._store_cache_entries(history / "MSFT-1y-v1.json", {})
            self.assertEqual(len(list(history.iterdir())), 3)


if __name__ == "__main__":
    unittest.main()
