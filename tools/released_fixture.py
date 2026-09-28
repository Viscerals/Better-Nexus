#!/usr/bin/env python3
"""Released-peer test fixture (test support only; not packaged).

Builds tests/prototype/fixtures/released_9049/ from the released test.9049
source commit so a paired test can run a peer on exactly the released code:

* every file the released Nexus.toc loads whose bytes differ from the current
  tree is copied verbatim from the commit (with the released Nexus.toc);
* MANIFEST.txt lists EVERY file the released TOC loads with its byte length
  and FNV-1a 32-bit checksum, so the test's loader can prove that each file it
  loads (fixture copy or unchanged current file) is the released byte string.

Usage:
  python tools/released_fixture.py build   # rewrite the fixture from git
  python tools/released_fixture.py check   # verify fixture against git
"""
import pathlib
import subprocess
import sys

COMMIT = "27aaeec33d04b015ffb5ba124be9cf8cc2bae524"  # released test.9049 source
ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tests" / "prototype" / "fixtures" / "released_9049"


def git_bytes(path):
    return subprocess.run(["git", "-C", str(ROOT), "show", f"{COMMIT}:{path}"],
                          check=True, capture_output=True).stdout


def norm(data):
    """Bytes without carriage returns: checkouts may convert line endings."""
    return data.replace(b"\r", b"")


def fnv1a(data):
    data = norm(data)
    h = 0x811C9DC5
    for byte in data:
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def released_files():
    toc = git_bytes("Nexus.toc").decode("utf-8").replace("\r", "")
    files = []
    for line in toc.split("\n"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def expected():
    out = {}
    for path in ["Nexus.toc"] + released_files():
        out[path] = git_bytes(path)
    return out


def build():
    if FIXTURE.exists():
        for item in sorted(FIXTURE.rglob("*"), reverse=True):
            if item.is_file():
                item.unlink()
            else:
                item.rmdir()
    FIXTURE.mkdir(parents=True, exist_ok=True)
    released = expected()
    lines = [f"# Released test.9049 source {COMMIT}.",
             "# path|bytes|fnv1a32 (carriage returns removed) of every file the released Nexus.toc loads;",
             "# 'copy' marks a verbatim fixture copy, 'tree' an unchanged current file.",
             "# Regenerate: python tools/released_fixture.py build"]
    copies = 0
    for path, data in released.items():
        current = ROOT / path
        same = current.is_file() and norm(current.read_bytes()) == norm(data)
        kind = "tree" if same and path != "Nexus.toc" else "copy"
        if kind == "copy":
            target = FIXTURE / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            copies += 1
        lines.append(f"{path}|{len(norm(data))}|{fnv1a(data):08x}|{kind}")
    (FIXTURE / "MANIFEST.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"released fixture: {len(released)} files, {copies} copied")


def check():
    released = expected()
    problems = []
    manifest = (FIXTURE / "MANIFEST.txt").read_text(encoding="utf-8").splitlines()
    listed = {}
    for line in manifest:
        if line.startswith("#") or not line.strip():
            continue
        path, size, digest, kind = line.split("|")
        listed[path] = (int(size), digest, kind)
    for path, data in released.items():
        if path not in listed:
            problems.append(f"missing from manifest: {path}")
            continue
        size, digest, kind = listed[path]
        if size != len(norm(data)) or digest != f"{fnv1a(data):08x}":
            problems.append(f"manifest differs from {COMMIT}: {path}")
        source = FIXTURE / path if kind == "copy" else ROOT / path
        if not source.is_file() or norm(source.read_bytes()) != norm(data):
            problems.append(f"{kind} file is not the released bytes: {path}")
    for problem in problems:
        print(problem)
    print("RESULT", "PASS" if not problems else "FAIL")
    return 0 if not problems else 1


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    if mode == "build":
        build()
        sys.exit(check())
    sys.exit(check())
