#!/usr/bin/env python3
"""Build the installable Nexus addon ZIP from committed files. It never publishes anything.

Python 3.9+ and git. Run from a clean checkout:

    python tools/build_package.py --label test.9999-abcdef0      # internal package: dist/Nexus-<label>.zip
    python tools/build_package.py --label test.9999-abcdef0 --public   # package meant for a public test release
    python tools/build_package.py --check                        # content checks only; writes nothing

The archive is built from the blobs of HEAD (not from working files, so the checkout's
line-ending setting does not matter), in sorted order, with one fixed timestamp and one fixed
host-system field. Two builds in the same environment give the same bytes. The compressed
bytes can differ between zlib builds (for example Linux and Windows Python 3.14), so compare
checksums only between builds from the same environment. File contents are always identical.
Content rule, the same one the published test.9027 package used, plus the
storage-only support component:
  * the six top-level files in TOP_LEVEL;
  * everything under core/, data/, logic/, third_party/, ui/;
  * everything under companion/NexusSupport/, packaged as its own addon folder
    so WoW creates a separate SavedVariables file for support reports;
  * nothing else: no tests, tools, docs, .github, SavedVariables, logs or archives.
The archive therefore contains two addon directories: Nexus/ and NexusSupport/.
The companion is storage only: Nexus runs normally without it.
Two declared substitutions in data/Release.lua, nothing else:
  * buildLabel "source" -> the label;
  * channel "development" -> "public-test" with --public, else "internal".
Only a "public-test" package states its test number to peers (as <version>+test.<N>), so an
internal or review package can never announce itself as a public update. tools/release_check.py
verifies that label, version, tag, asset name and announced identity agree.
A public release is a separate, human-authorized step (see RELEASE_SECURITY.md).
"""
from __future__ import annotations
import argparse, hashlib, pathlib, re, subprocess, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOP_LEVEL = ['AI_POLICY.md', 'LICENSE.md', 'Nexus.toc', 'README-PROTOTYPE.md', 'THIRD_PARTY.md', 'UPSTREAM.md']
RUNTIME_DIRS = ['core', 'data', 'logic', 'third_party', 'ui']
# Packaged as its own addon folder, not inside Nexus/.
COMPANION_DIR = 'companion/NexusSupport'
COMPANION_ADDON = 'NexusSupport'
ALLOWED_SUFFIXES = {'.lua', '.toc', '.md'}
LABEL = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$')
SOURCE_LABEL = b'buildLabel = "source"'
SOURCE_CHANNEL = b'channel = "development"'
RUNTIME_LABEL = re.compile(r'^test\.[1-9]\d{0,9}-[0-9a-f]{7,12}$')


def git(*args: str) -> bytes:
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=ROOT)


def committed_files() -> dict[str, bytes]:
    names = [n for n in git('ls-tree', '-r', '-z', '--name-only', 'HEAD').decode().split('\0') if n]
    wanted = [n for n in names if n in TOP_LEVEL or n.split('/', 1)[0] in RUNTIME_DIRS
              or n.startswith(COMPANION_DIR + '/')]
    return {n: git('cat-file', 'blob', 'HEAD:' + n) for n in sorted(wanted)}


def companion_files(files: dict[str, bytes]) -> dict[str, bytes]:
    prefix = COMPANION_DIR + '/'
    return {n[len(prefix):]: d for n, d in files.items() if n.startswith(prefix)}


def toc_directive(toc: str, name: str) -> str | None:
    """The value of a TOC directive, read as WoW reads it: a line that starts
    with ## and the directive name, not a substring anywhere in the file."""
    for line in toc.splitlines():
        stripped = line.strip()
        if not stripped.startswith('##'):
            continue
        body = stripped[2:].lstrip()
        key, sep, value = body.partition(':')
        if sep and key.strip().lower() == name.lower():
            return value.strip()
    return None


def companion_toc_problems(toc: str, toc_name: str) -> list[str]:
    """Rules the storage-only component must satisfy, each read from its own
    directive so prose in a Notes line cannot satisfy them."""
    problems = []
    saved = toc_directive(toc, 'SavedVariables')
    names = saved.replace(',', ' ').split() if saved else []
    if 'NexusSupportDB' not in names:
        problems.append(f'{toc_name} must declare SavedVariables: NexusSupportDB')
    for name in names:
        if name != 'NexusSupportDB':
            problems.append(f'{toc_name} must not declare other saved variables: {name}')
    for directive in ('Dependencies', 'RequiredDeps'):
        value = toc_directive(toc, directive)
        if value:
            problems.append(f'{toc_name} must not depend on another addon: {directive}: {value}')
    if (toc_directive(toc, 'LoadOnDemand') or '').strip() != '1':
        problems.append(f'{toc_name} must declare LoadOnDemand: 1; it loads only for an explicit report action')
    return problems


def check(files: dict[str, bytes]) -> list[str]:
    problems = [f'missing top-level file: {n}' for n in TOP_LEVEL if n not in files]
    for name in files:
        if pathlib.PurePosixPath(name).suffix.lower() not in ALLOWED_SUFFIXES:
            problems.append(f'unexpected file type in package: {name}')

    # The companion is its own addon: its TOC must load exactly its own files,
    # it must declare its own SavedVariables, and it must not depend on Nexus.
    companion = companion_files(files)
    if not companion:
        problems.append(f'missing the support component under {COMPANION_DIR}/')
    else:
        companion_toc_name = COMPANION_ADDON + '.toc'
        if companion_toc_name not in companion:
            problems.append(f'the support component has no {companion_toc_name}')
        else:
            ctoc = companion[companion_toc_name].decode('utf-8', 'replace')
            clisted = [l.strip().replace('\\', '/') for l in ctoc.splitlines()
                       if l.strip() and not l.lstrip().startswith('#')]
            for entry in clisted:
                if entry not in companion:
                    problems.append(f'{companion_toc_name} loads a file that is not packaged: {entry}')
            for name in companion:
                if name.endswith('.lua') and name not in clisted:
                    problems.append(f'packaged support file is not loaded by {companion_toc_name}: {name}')
            problems.extend(companion_toc_problems(ctoc, companion_toc_name))

    toc = files.get('Nexus.toc', b'').decode('utf-8', 'replace')
    listed = [l.strip().replace('\\', '/') for l in toc.splitlines() if l.strip() and not l.lstrip().startswith('#')]
    for entry in listed:
        if entry not in files:
            problems.append(f'Nexus.toc loads a file that is not packaged: {entry}')
    unloaded = [n for n in files if n.endswith('.lua') and n not in listed
                and not n.startswith(COMPANION_DIR + '/')]
    for name in unloaded:
        problems.append(f'packaged Lua file is not loaded by Nexus.toc: {name}')
    if files.get('data/Release.lua', b'').count(SOURCE_LABEL) != 1:
        problems.append('data/Release.lua must contain exactly one buildLabel = "source"')
    if files.get('data/Release.lua', b'').count(SOURCE_CHANNEL) != 1:
        problems.append('data/Release.lua must contain exactly one channel = "development"')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--label', help='display build label, for example test.9999-abcdef0')
    ap.add_argument('--check', action='store_true', help='content checks only; no archive is written')
    ap.add_argument('--public', action='store_true', help='mark the package as a public test build (it will state its test number to peers)')
    ap.add_argument('--allow-dirty', action='store_true', help='package HEAD although the working tree has changes')
    ns = ap.parse_args()
    if not ns.check and not ns.label:
        ap.error('give --label, or --check')
    if ns.label and not LABEL.match(ns.label):
        ap.error('label: letters, digits, dot, underscore and hyphen; at most 48 characters')
    if ns.public and not (ns.label and RUNTIME_LABEL.match(ns.label)):
        ap.error('--public needs a label of the form test.<number>-<7 to 12 hex digits>')
    if ns.label and not RUNTIME_LABEL.match(ns.label):
        print('NOTE: the addon shows only labels of the form test.<number>-<7 to 12 hex digits>; this label will display as "source".')

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

    out = ROOT / 'dist' / (f'Better-Nexus-{ns.label}.zip' if ns.public else f'Nexus-{ns.label}.zip')
    if out.exists():
        print(f'Refusing to overwrite {out}')
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in files.items():
            if name == 'data/Release.lua':
                data = data.replace(SOURCE_LABEL, f'buildLabel = "{ns.label}"'.encode())
                channel = 'public-test' if ns.public else 'internal'
                data = data.replace(SOURCE_CHANNEL, f'channel = "{channel}"'.encode())
            if name.startswith(COMPANION_DIR + '/'):
                archive_name = COMPANION_ADDON + '/' + name[len(COMPANION_DIR) + 1:]
            else:
                archive_name = 'Nexus/' + name
            info = zipfile.ZipInfo(archive_name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3   # same header on every platform
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    print(f'{out.relative_to(ROOT)}  {out.stat().st_size} bytes  sha256 {hashlib.sha256(out.read_bytes()).hexdigest()}')
    print('Install paths: Interface/AddOns/Nexus/Nexus.toc and '
          'Interface/AddOns/NexusSupport/NexusSupport.toc (storage only for support reports; '
          'Nexus runs without it). This tool did not publish or install anything.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
