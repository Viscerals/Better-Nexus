#!/usr/bin/env python3
"""Fail-capable self-test of the package and release identity tools. It publishes nothing.

    python tools/release_selftest.py

It builds one public and one internal package of HEAD into dist/, runs tools/release_check.py on
consistent input (must pass) and on inconsistent inputs (each must fail), then deletes dist/.
It compares exit codes. It does not exercise --require-newer, because a CI checkout has no tags.
"""
from __future__ import annotations
import pathlib, re, shutil, subprocess, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PY = sys.executable


def run(*args: str) -> int:
    return subprocess.run([PY, *args], cwd=ROOT, capture_output=True, text=True).returncode


def main() -> int:
    dist = ROOT / 'dist'
    if dist.exists():
        print('dist/ exists; remove it first'); return 1
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    label, other = f'test.12-{commit[:7]}', f'test.13-{commit[:7]}'
    failures: list[str] = []

    def expect(name: str, code: int, want_ok: bool) -> None:
        ok = code == 0
        print(('ok   ' if ok == want_ok else 'WRONG') + f' {name}: exit {code}, expected {"0" if want_ok else "non-zero"}')
        if ok != want_ok:
            failures.append(name)

    try:
        expect('build public package', run('tools/build_package.py', '--label', label, '--public', '--allow-dirty'), True)
        public = dist / f'Better-Nexus-{label}.zip'
        expect('build internal package', run('tools/build_package.py', '--label', other, '--allow-dirty'), True)
        internal = dist / f'Nexus-{other}.zip'
        if not (public.is_file() and internal.is_file()):
            print('RESULT: FAILED: the packages were not built; run tools/build_package.py --check'); return 1
        import hashlib
        sums = dist / 'SHA256SUMS.txt'
        sums.write_text(f'{hashlib.sha256(public.read_bytes()).hexdigest()}  {public.name}\n', encoding='utf-8')
        version = re.search(r'^\s*version\s*=\s*"([^"]+)"', (ROOT / 'data/Release.lua').read_text(encoding='utf-8'), flags=re.M).group(1)
        tag = f'v{version}-test.12'

        expect('consistent public release', run('tools/release_check.py', '--label', label, '--zip', str(public), '--tag', tag, '--sums', str(sums)), True)
        expect('consistent internal package', run('tools/release_check.py', '--label', other, '--zip', str(internal), '--internal'), True)
        expect('tag for another test number', run('tools/release_check.py', '--label', label, '--zip', str(public), '--tag', f'v{version}-test.13'), False)
        expect('label that differs from the packaged label', run('tools/release_check.py', '--label', other, '--zip', str(public), '--asset', f'Better-Nexus-{other}.zip'), False)
        expect('internal package offered as public', run('tools/release_check.py', '--label', other, '--zip', str(internal), '--asset', f'Better-Nexus-{other}.zip'), False)
        expect('public package declared internal', run('tools/release_check.py', '--label', label, '--zip', str(public), '--internal'), False)
        expect('asset name without the label', run('tools/release_check.py', '--label', label, '--zip', str(public), '--asset', 'Better-Nexus-latest.zip'), False)
        expect('commit suffix of another commit', run('tools/release_check.py', '--label', 'test.12-0000000'), False)
        expect('malformed label', run('tools/release_check.py', '--label', 'test.012-' + commit[:7]), False)
        sums.write_text('0' * 64 + f'  {public.name}\n', encoding='utf-8')
        expect('checksum file that does not match', run('tools/release_check.py', '--label', label, '--zip', str(public), '--sums', str(sums)), False)
        expect('--sums without --zip', run('tools/release_check.py', '--label', label, '--sums', str(sums)), False)

        # Crafted archives: a wrong packaged version, and an entry outside Nexus/.
        def rewrite(target, change, extra=False):
            target.parent.mkdir()
            with zipfile.ZipFile(public) as z, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as out:
                for item in z.infolist():
                    out.writestr(item, change(item.filename, z.read(item.filename)))
                if extra:
                    out.writestr('README-outside.txt', b'outside')

        wrong_version = dist / 'wrong-version' / public.name
        rewrite(wrong_version, lambda n, d: d.replace(f'version = "{version}"'.encode(), b'version = "9.9.9"')
                if n.endswith('data/Release.lua') else d)
        expect('packaged version that differs from the repository', run('tools/release_check.py', '--label', label, '--zip', str(wrong_version)), False)
        outside = dist / 'outside' / public.name
        rewrite(outside, lambda n, d: d, extra=True)
        expect('entry outside Nexus/', run('tools/release_check.py', '--label', label, '--zip', str(outside)), False)
        expect('--public without a displayable label', run('tools/build_package.py', '--label', 'nightly', '--public', '--allow-dirty'), False)

        # The storage-only support component: every rule the packager applies
        # must also fail here, because this check inspects artefacts it did not
        # build. Each case rewrites only the companion TOC.
        CRLF = chr(13) + chr(10)

        def companion(target_name, change_toc, extra_name=None, extra_data=b''):
            target = dist / target_name / public.name
            target.parent.mkdir()
            with zipfile.ZipFile(public) as z, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as out:
                for item in z.infolist():
                    data = z.read(item.filename)
                    if item.filename == 'NexusSupport/NexusSupport.toc':
                        data = change_toc(data.decode('utf-8')).encode('utf-8')
                        if data == b'':
                            continue
                    out.writestr(item, data)
                if extra_name:
                    out.writestr(extra_name, extra_data)
            return target

        dep = companion('companion-dep', lambda t: t.replace(
            '## LoadOnDemand: 1', '## Dependencies: Nexus' + CRLF + '## LoadOnDemand: 1'))
        expect('a support component that depends on another addon',
               run('tools/release_check.py', '--label', label, '--zip', str(dep)), False)
        prose = companion('companion-prose', lambda t: t.replace(
            '## SavedVariables: NexusSupportDB',
            '## X-Note: SavedVariables: NexusSupportDB is declared elsewhere'))
        expect('a support component that declares no saved variables',
               run('tools/release_check.py', '--label', label, '--zip', str(prose)), False)
        nolod = companion('companion-nolod',
                          lambda t: re.sub(r'(?im)^[ \t]*##[ \t]*LoadOnDemand.*\r?\n?', '', t))
        expect('a support component that is not load-on-demand',
               run('tools/release_check.py', '--label', label, '--zip', str(nolod)), False)
        stray = companion('companion-stray', lambda t: t,
                          extra_name='NexusSupport/probe.py', extra_data=b'print(1)')
        expect('an unexpected file type inside the support component',
               run('tools/release_check.py', '--label', label, '--zip', str(stray)), False)
        missing = companion('companion-missing', lambda t: '')
        expect('a package with no support component TOC',
               run('tools/release_check.py', '--label', label, '--zip', str(missing)), False)

        with zipfile.ZipFile(public) as z:
            packaged = z.read('Nexus/data/Release.lua').decode()
        for needle in (f'buildLabel = "{label}"', 'channel = "public-test"'):
            if needle not in packaged:
                failures.append('packaged Release.lua lacks ' + needle)
        with zipfile.ZipFile(internal) as z:
            if 'channel = "internal"' not in z.read('Nexus/data/Release.lua').decode():
                failures.append('internal package is not marked internal')
    finally:
        shutil.rmtree(dist, ignore_errors=True)
    if failures:
        print('RESULT: FAILED:', '; '.join(failures)); return 1
    print('RESULT: release identity checks pass and fail where they must; dist/ removed; nothing published')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
