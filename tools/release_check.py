#!/usr/bin/env python3
"""Release identity consistency check. It reads and compares; it never tags, uploads or publishes.

One declared identity is the source of every other name:

    data/Release.lua  version      1.20.0-beta.1          (release series)
    package label                  test.<N>-<commit>      (N orders builds of one series; the commit does not)
      -> Git tag                   v<version>-test.<N>
      -> release asset             Better-Nexus-test.<N>-<commit>.zip
      -> announced to peers        <version>+test.<N>     (public-test packages only, at most 32 bytes)
      -> shown in game             <version> test.<N>

    python tools/release_check.py --label test.9028-abcdef0
    python tools/release_check.py --label test.9028-abcdef0 --zip dist/Better-Nexus-test.9028-abcdef0.zip \\
        --tag v1.20.0-beta.1-test.9028 --sums SHA256SUMS.txt

Exit 1 on: an invalid label; a commit suffix that is not a prefix of the packaged commit; a tag or asset
name that differs from the derived one; a ZIP whose data/Release.lua states another label, version or
channel; a public ZIP that is not marked public-test (or the reverse); a checksum file that does not
match; an announced identity above 32 bytes; a test number that is not above the newest existing
v<version>-test.<N> tag (with --require-newer).
A plain push, a branch or an archive tag publishes nothing: no workflow in this repository has a tag or
release trigger, and publication stays an explicit human-authorized step (RELEASE_SECURITY.md).
"""
from __future__ import annotations
import argparse, hashlib, pathlib, re, subprocess, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
LABEL = re.compile(r'^test\.([1-9]\d{0,9})-([0-9a-f]{7,12})$')
MAX_TEST = 2147483647
MAX_ANNOUNCE_BYTES = 32


def field(text: str, name: str) -> str | None:
    found = re.findall(r'^\s*' + name + r'\s*=\s*"([^"]*)"', text, flags=re.M)
    return found[0] if len(found) == 1 else None


def derive(version: str, label: str) -> dict:
    m = LABEL.match(label)
    if not m:
        raise ValueError('label must be test.<number>-<7 to 12 lowercase hex digits>')
    number = int(m.group(1))
    if number > MAX_TEST:
        raise ValueError('test number is above 2147483647')
    return {'version': version, 'label': label, 'test': number, 'commit': m.group(2),
            'tag': f'v{version}-test.{number}', 'asset': f'Better-Nexus-{label}.zip',
            'announce': f'{version}+test.{number}', 'display': f'{version} test.{number}'}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--label', required=True)
    ap.add_argument('--zip', type=pathlib.Path, help='package to inspect')
    ap.add_argument('--tag', help='tag that the release will use')
    ap.add_argument('--asset', help='asset file name that the release will use (default: the name of --zip)')
    ap.add_argument('--sums', type=pathlib.Path, help='SHA256SUMS file to verify against --zip')
    ap.add_argument('--commit', help='full commit the package was built from (default: HEAD)')
    ap.add_argument('--internal', action='store_true', help='the package is an internal one and must NOT be public-test')
    ap.add_argument('--require-newer', action='store_true', help='the test number must be above every existing tag of the same series')
    ns = ap.parse_args()

    problems: list[str] = []
    source = (ROOT / 'data' / 'Release.lua').read_text(encoding='utf-8')
    version = field(source, 'version')
    if not version:
        print('RELEASE PROBLEM: data/Release.lua has no single version field'); return 1
    if field(source, 'buildLabel') != 'source' or field(source, 'channel') != 'development':
        problems.append('the repository copy of data/Release.lua must state buildLabel "source" and channel "development"')
    try:
        identity = derive(version, ns.label)
    except ValueError as exc:
        print('RELEASE PROBLEM:', exc); return 1
    if len(identity['announce'].encode()) > MAX_ANNOUNCE_BYTES:
        problems.append(f'announced identity {identity["announce"]} is above {MAX_ANNOUNCE_BYTES} bytes; peers would refuse it')

    commit = ns.commit or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if not commit.startswith(identity['commit']):
        problems.append(f'label commit {identity["commit"]} is not a prefix of the packaged commit {commit}')
    if ns.tag and ns.tag != identity['tag']:
        problems.append(f'tag {ns.tag} differs from the derived tag {identity["tag"]}')
    asset = ns.asset or (ns.zip.name if ns.zip else None)
    if asset and not ns.internal and asset != identity['asset']:
        problems.append(f'asset {asset} differs from the derived asset {identity["asset"]}')

    if ns.sums and not ns.zip:
        problems.append('--sums needs --zip; no checksum was verified')
    if ns.require_newer:
        if not subprocess.check_output(['git', 'tag', '--list'], cwd=ROOT, text=True).split():
            problems.append('--require-newer: this clone has no tags at all; fetch tags first (git fetch --tags)')
        tags = subprocess.check_output(['git', 'tag', '--list', f'v{version}-test.*'], cwd=ROOT, text=True).split()
        numbers = [int(t.rsplit('.', 1)[1]) for t in tags if t.rsplit('.', 1)[1].isdigit()]
        print(f'--require-newer: compared with {len(numbers)} existing tag(s) of series v{version}-test.*'
              + ('' if numbers else ' (none found: nothing was compared; other release lines are not visible to this check)'))
        if numbers and identity['test'] <= max(numbers):
            problems.append(f'test number {identity["test"]} is not above the newest existing tag test.{max(numbers)}; clients would not see it as newer')

    if ns.zip:
        if not ns.zip.is_file():
            problems.append(f'no such package: {ns.zip}')
        else:
            with zipfile.ZipFile(ns.zip) as z:
                names = [n for n in z.namelist() if not n.endswith('/')]
                packaged = z.read('Nexus/data/Release.lua').decode('utf-8') if 'Nexus/data/Release.lua' in names else ''
            if any(not n.startswith('Nexus/') for n in names):
                problems.append('the package has entries outside Nexus/')
            if field(packaged, 'version') != version:
                problems.append(f'packaged version {field(packaged, "version")} differs from {version}')
            if field(packaged, 'buildLabel') != ns.label:
                problems.append(f'packaged buildLabel {field(packaged, "buildLabel")} differs from the label {ns.label}')
            wanted = 'internal' if ns.internal else 'public-test'
            if field(packaged, 'channel') != wanted:
                problems.append(f'packaged channel {field(packaged, "channel")} must be {wanted}')
            if ns.sums:
                digest = hashlib.sha256(ns.zip.read_bytes()).hexdigest()
                rows = [l.split() for l in ns.sums.read_text(encoding='utf-8').splitlines() if l.strip()]
                if [digest, asset] not in [[r[0].lower(), r[-1].lstrip('*')] for r in rows if len(r) >= 2]:
                    problems.append(f'{ns.sums.name} has no line "{digest}  {asset}"')

    for key in ('version', 'label', 'test', 'tag', 'asset', 'announce', 'display'):
        print(f'{key:9} {identity[key]}')
    for p in problems:
        print('RELEASE PROBLEM:', p)
    if problems:
        return 1
    print('release identity is consistent; nothing was tagged, uploaded or published')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
