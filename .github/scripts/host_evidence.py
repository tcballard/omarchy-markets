#!/usr/bin/env python3
"""Validate the operator's host acceptance record for an exact release SHA."""
import datetime
import json
import os
from pathlib import Path
import re
import sys

REQUIRED_CHECKS = [
    "fresh-install-and-consent", "update-preserves-settings", "quote-and-history",
    "panel-scroll-focus-and-dismissal", "light-dark-themes-and-scaling",
    "horizontal-and-vertical-bars", "offline-and-recovery",
    "reload-disable-and-remove",
]


def validate(record, candidate):
    if not isinstance(record, dict) or record.get("schemaVersion") != 1:
        raise ValueError("Missing host acceptance record")
    if not re.fullmatch(r"[0-9a-f]{40}", candidate or ""):
        raise ValueError("Invalid release candidate SHA")
    if record.get("testedCommit") != candidate:
        raise ValueError("Host testing must cover the exact release candidate SHA")
    if not re.fullmatch(r"[0-9a-f]{40}", record.get("omarchyCommit", "")):
        raise ValueError("Record the full tested Omarchy commit")
    if record.get("architecture") != "x86_64":
        raise ValueError("This release targets x86_64; other architectures need separate evidence")
    checks = record.get("checks")
    if (not isinstance(checks, dict) or set(checks) != set(REQUIRED_CHECKS)
            or any(value is not True for value in checks.values())):
        raise ValueError("Every required host check must have passed")
    notes = record.get("notes")
    if not isinstance(notes, str) or not 20 <= len(notes.strip()) <= 8000:
        raise ValueError("Provide host results, display/theme details and remaining limitations")
    return record


def main():
    record = {
        "schemaVersion": 1,
        "testedCommit": os.environ.get("TESTED_COMMIT", "").strip(),
        "omarchyCommit": os.environ.get("OMARCHY_COMMIT", "").strip(),
        "architecture": os.environ.get("TESTED_ARCHITECTURE", ""),
        "checks": {name: os.environ.get("HOST_CHECKS_PASSED") == "true"
                   for name in REQUIRED_CHECKS},
        "notes": os.environ.get("HOST_NOTES", "").strip(),
        "recordedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "workflowRun": os.environ.get("GITHUB_RUN_ID", ""),
    }
    validate(record, os.environ.get("GITHUB_SHA", ""))
    Path(sys.argv[1]).write_text(json.dumps(record, indent=2) + "\n")
    print("Host acceptance is recorded for " + record["testedCommit"])


if __name__ == "__main__":
    main()
