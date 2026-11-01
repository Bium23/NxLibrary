#!/usr/bin/env python3
"""Check tracked publication inputs; never print matching secret values."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


PRIVATE_ROOTS = {"output", "reports", "research_notes", ".superpowers", ".aws"}
PRIVATE_EXTENSIONS = {
    ".keys", ".nsp", ".xci", ".nsz", ".xcz", ".nca", ".nso", ".tik", ".cert",
    ".app", ".dmg", ".ipa", ".log", ".p12", ".pfx",
}
SECRET_PATTERNS = [
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})\b"),
    re.compile(rb"(?im)^\s*(?:header_key|master_key_[0-9a-f]{2}|key_area_key_application_[0-9a-f]{2})\s*=\s*[0-9a-f]{32,128}\s*$"),
]


def check_files(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    issues = []
    for name in filter(None, names):
        relative = Path(name)
        if (relative.parts[0] in PRIVATE_ROOTS or relative.parts[:2] == ("docs", "audits")
                or any(Path(part).suffix.lower() in PRIVATE_EXTENSIONS for part in relative.parts)
                or (relative.name.startswith(".env") and relative.name != ".env.example")
                or relative.name == "env.txt"):
            issues.append("Private or game content path: " + name)
            continue
        file = root / relative
        if not file.is_file() or file.is_symlink():
            continue
        data = file.read_bytes()
        if b"\0" not in data[:8192] and any(pattern.search(data) for pattern in SECRET_PATTERNS):
            issues.append("Possible secret material: " + name)
    return issues


def check_runtime(root, runtime):
    try:
        lock_bytes = (root / "runtime.lock").read_bytes()
        lock = json.loads(lock_bytes)
        versions = json.loads((runtime / "versions.json").read_text())
        expected = {"python": lock["python"]["version"],
                    "lock": hashlib.sha256(lock_bytes).hexdigest()}
        expected.update((item["name"].lower(), item["version"]) for item in lock["wheels"])
        expected.update((item["formula"], item["version"]) for item in lock["brew"])
        if any(versions.get(name) != value for name, value in expected.items()):
            return ["Runtime does not match runtime.lock; run scripts/bundle_runtime.sh."]
        required = ["python/bin/python3", "bin/zstd", "bin/glslangValidator"]
        if not all((runtime / name).is_file() and os.access(runtime / name, os.X_OK) for name in required):
            return ["Runtime is missing an executable."]
        if not (runtime / "licenses").is_dir():
            return ["Runtime is missing its licenses."]
    except (OSError, ValueError, KeyError, TypeError):
        return ["Runtime metadata could not be verified."]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, help="Also verify a bundled runtime against runtime.lock.")
    args = parser.parse_args()
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).decode().strip())
    issues = check_files(root)
    if args.runtime:
        issues += check_runtime(root, args.runtime)
    for issue in issues:
        print(issue)
    if not issues:
        print("Publication checks passed.")
    return bool(issues)


if __name__ == "__main__":
    raise SystemExit(main())
