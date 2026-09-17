#!/usr/bin/env python3
"""Build and verify source-only release assets; never used by the plugin."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args])


def identity():
    commit = git("rev-parse", "HEAD").decode().strip()
    tree = git("rev-parse", "HEAD^{tree}").decode().strip()
    version = json.loads(git("show", "HEAD:manifest.json"))["version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Release requires a numeric semantic version")
    return version, {"repository": "https://github.com/tcballard/omarchy-markets",
                     "commit": commit, "tree": tree}


def describe(path):
    return {"name": path.name, "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def build(directory):
    version, source = identity()
    directory.mkdir(parents=True, exist_ok=False)
    archive = directory / f"omarchy-markets-{version}.tar.gz"
    archive.write_bytes(gzip.compress(git("archive", "--format=tar",
        f"--prefix=omarchy-markets-{version}/", source["commit"]), mtime=0))
    files = []
    for entry in git("ls-tree", "-r", "-z", "HEAD").split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, sha = metadata.decode().split()
        if kind != "blob" or mode not in ("100644", "100755"):
            raise ValueError("Only regular source files may be released")
        content = git("cat-file", "blob", sha)
        files.append({"path": name.decode(), "mode": mode, "bytes": len(content),
                      "sha256": hashlib.sha256(content).hexdigest()})
    write_json(directory / "SOURCE-MANIFEST.json", {
        "schemaVersion": 1, "version": version, "source": source, "files": files})
    created = datetime.datetime.fromtimestamp(int(git("show", "-s", "--format=%ct", "HEAD")),
        datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    write_json(directory / "SBOM.spdx.json", {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT", "name": f"omarchy-markets-{version}",
        "documentNamespace": f"https://github.com/tcballard/omarchy-markets/sbom/{source['commit']}",
        "creationInfo": {"created": created, "creators": ["Tool: omarchy-markets-release"]},
        "packages": [{"SPDXID": "SPDXRef-Package", "name": "omarchy-markets",
            "versionInfo": version, "downloadLocation": source["repository"] + ".git@" + source["commit"],
            "filesAnalyzed": False, "licenseConcluded": "NOASSERTION", "licenseDeclared": "MIT",
            "copyrightText": "Copyright (c) 2026 Tom Ballard",
            "comment": "Source package only. External runtime requirements: Omarchy Quattro, Python 3.10+ standard library. Yahoo Finance is an external data service."}],
        "relationships": [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES",
                           "relatedSpdxElement": "SPDXRef-Package"}]})
    write_json(directory / "RELEASE-MANIFEST.json", {
        "schemaVersion": 1, "version": version, "source": source,
        "artifacts": [describe(archive)],
        "releaseDocuments": [describe(directory / name) for name in
                             ("SOURCE-MANIFEST.json", "SBOM.spdx.json")]})
    (directory / "SHA256SUMS").write_text("".join(
        f"{describe(path)['sha256']}  {path.name}\n" for path in sorted(directory.iterdir())))
    verify(directory)


def verify(directory):
    version, source = identity()
    release = json.loads((directory / "RELEASE-MANIFEST.json").read_text())
    manifest = json.loads((directory / "SOURCE-MANIFEST.json").read_text())
    for document in (release, manifest):
        if document["schemaVersion"] != 1 or document["source"] != source or document["version"] != version:
            raise ValueError("Release source identity mismatch")
    entries = release["artifacts"] + release["releaseDocuments"]
    names = {entry["name"] for entry in entries}
    if len(names) != len(entries) or any(Path(n).name != n for n in names):
        raise ValueError("Duplicate or unsafe asset name")
    for entry in entries:
        if describe(directory / entry["name"]) != entry:
            raise ValueError("Asset digest or size mismatch")
    names.add("RELEASE-MANIFEST.json")
    expected = "".join(f"{describe(directory / name)['sha256']}  {name}\n" for name in sorted(names))
    if (directory / "SHA256SUMS").read_text() != expected:
        raise ValueError("Checksum coverage mismatch")
    if {p.name for p in directory.iterdir()} != names | {"SHA256SUMS"}:
        raise ValueError("Unexpected release files")
    archive = directory / f"omarchy-markets-{version}.tar.gz"
    expected_tar = git("archive", "--format=tar", f"--prefix=omarchy-markets-{version}/", source["commit"])
    if gzip.decompress(archive.read_bytes()) != expected_tar:
        raise ValueError("Archive does not match the exact source commit")
    print(f"Verified release assets: v{version} at {source['commit']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "verify"))
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    (build if args.action == "build" else verify)(args.directory)
