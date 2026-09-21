#!/usr/bin/env python3
"""Build the installable Nexus addon ZIP from committed files. It never publishes anything.

Python 3.9+ and git. Run from a clean checkout:

    python tools/build_package.py --label test.9999-abcdef0      # writes dist/Nexus-<label>.zip
    python tools/build_package.py --check                        # content checks only; writes nothing

The archive is reproducible: it is built from the blobs of HEAD (not from working files, so
the checkout's line-ending setting does not matter), in sorted order, with one fixed timestamp.
Content rule, the same one the published test.9027 package used:
  * the six top-level files in TOP_LEVEL;
  * everything under core/, data/, logic/, third_party/, ui/;
  * nothing else: no tests, tools, docs, .github, SavedVariables, logs or archives.
The only substitution is the display build label in data/Release.lua.
A public release is a separate, human-authorized step (see RELEASE_SECURITY.md).
"""
from __future__ import annotations
import argparse, hashlib, pathlib, re, subprocess, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOP_LEVEL = ['AI_POLICY.md', 'LICENSE.md', 'Nexus.toc', 'README-PROTOTYPE.md', 'THIRD_PARTY.md', 'UPSTREAM.md']
RUNTIME_DIRS = ['core', 'data', 'logic', 'third_party', 'ui']
ALLOWED_SUFFIXES = {'.lua', '.toc', '.md'}
LABEL = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$')
SOURCE_LABEL = b'buildLabel = "source"'


def git(*args: str) -> bytes:
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=ROOT)


def committed_files() -> dict[str, bytes]:
    names = [n for n in git('ls-tree', '-r', '-z', '--name-only', 'HEAD').decode().split('\0') if n]
    wanted = [n for n in names if n in TOP_LEVEL or n.split('/', 1)[0] in RUNTIME_DIRS]
    return {n: git('cat-file', 'blob', 'HEAD:' + n) for n in sorted(wanted)}


def check(files: dict[str, bytes]) -> list[str]:
    problems = [f'missing top-level file: {n}' for n in TOP_LEVEL if n not in files]
    for name in files:
        if pathlib.PurePosixPath(name).suffix.lower() not in ALLOWED_SUFFIXES:
            problems.append(f'unexpected file type in package: {name}')
    toc = files.get('Nexus.toc', b'').decode('utf-8', 'replace')
    listed = [l.strip().replace('\\', '/') for l in toc.splitlines() if l.strip() and not l.lstrip().startswith('#')]
    for entry in listed:
        if entry not in files:
            problems.append(f'Nexus.toc loads a file that is not packaged: {entry}')
    unloaded = [n for n in files if n.endswith('.lua') and n not in listed]
    for name in unloaded:
        problems.append(f'packaged Lua file is not loaded by Nexus.toc: {name}')
    if files.get('data/Release.lua', b'').count(SOURCE_LABEL) != 1:
        problems.append('data/Release.lua must contain exactly one buildLabel = "source"')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--label', help='display build label, for example test.9999-abcdef0')
    ap.add_argument('--check', action='store_true', help='content checks only; no archive is written')
    ap.add_argument('--allow-dirty', action='store_true', help='package HEAD although the working tree has changes')
    ns = ap.parse_args()
    if not ns.check and not ns.label:
        ap.error('give --label, or --check')
    if ns.label and not LABEL.match(ns.label):
        ap.error('label: letters, digits, dot, underscore and hyphen; at most 48 characters')

    files = committed_files()
    problems = check(files)
    for p in problems:
        print('PACKAGE PROBLEM:', p)
    print(f'package content: {len(files)} files from commit {git("rev-parse", "HEAD").decode().strip()}')
    if problems:
        return 1
    if ns.check:
        print('content checks passed; no archive was written')
        return 0
    if git('status', '--porcelain').strip() and not ns.allow_dirty:
        print('The working tree has uncommitted changes. The archive is built from HEAD; commit first or pass --allow-dirty.')
        return 1

    out = ROOT / 'dist' / f'Nexus-{ns.label}.zip'
    if out.exists():
        print(f'Refusing to overwrite {out}')
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in files.items():
            if name == 'data/Release.lua':
                data = data.replace(SOURCE_LABEL, f'buildLabel = "{ns.label}"'.encode())
            info = zipfile.ZipInfo('Nexus/' + name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    print(f'{out.relative_to(ROOT)}  {out.stat().st_size} bytes  sha256 {hashlib.sha256(out.read_bytes()).hexdigest()}')
    print('Install path: Interface/AddOns/Nexus/Nexus.toc. This tool did not publish or install anything.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
