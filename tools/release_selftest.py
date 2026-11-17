#!/usr/bin/env python3
"""Fail-capable self-test of the package and release identity tools. It publishes nothing.

    python tools/release_selftest.py

It builds one public and one internal package of HEAD into dist/, runs tools/release_check.py on
consistent input (must pass) and on inconsistent inputs (each must fail), then deletes dist/.
It compares exit codes. It does not exercise --require-newer, because a CI checkout has no tags.
"""
from __future__ import annotations
import importlib.util, pathlib, re, shutil, subprocess, sys, tempfile, warnings, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PY = sys.executable


def run(*args: str) -> int:
    return subprocess.run([PY, *args], cwd=ROOT, capture_output=True, text=True).returncode


def decoder_bytes_checks() -> list:
    r"""The support-report decoder counts BYTES, so a byte the saved file
    carries literally must verify exactly like the same byte written as a \ddd
    escape. Reading the file with a lossy error handler turned an intact report
    into an accusation of tampering, and no other check covers this tool."""
    path = ROOT / 'tools' / 'decode_support_report.py'
    spec = importlib.util.spec_from_file_location('decode_support_report', path)
    decoder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(decoder)

    # Multi-byte text, one high byte that is not valid UTF-8 on its own, and a
    # NUL: every class the writer has to carry through unchanged.
    body = 'café €'.encode('utf-8') + bytes([0xE9, 0x00]) + b' end'
    chunk = body.decode('utf-8', 'surrogateescape')
    declared_bytes, declared_sum = len(body), decoder.checksum([chunk])

    def lua_literal(escape_high: bool) -> str:
        out = []
        for byte in body:
            if byte in (0x5C, 0x22):
                out.append('\\' + chr(byte))
            elif byte < 32 or byte == 127:
                out.append('\\%d' % byte)
            elif byte >= 128:
                # The \ddd escape WoW usually writes, or the byte itself,
                # carried as a surrogate escape so that encoding the file with
                # 'surrogateescape' puts exactly that byte on disk.
                out.append('\\%d' % byte if escape_high else chr(0xDC00 + byte))
            else:
                out.append(chr(byte))
        return ''.join(out)

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for name, escape_high in (('escaped', True), ('literal', False)):
            saved = tmp / ('NexusSupport-%s.lua' % name)
            decoded = tmp / ('report-%s.txt' % name)
            saved.write_bytes((
                'NexusSupportDB = {\n\t["report"] = {\n\t\t["meta"] = {\n'
                '\t\t\t["format"] = 1,\n\t\t\t["id"] = "selftest",\n'
                '\t\t\t["chunkCount"] = 1,\n'
                '\t\t\t["bytes"] = %d,\n\t\t\t["checksum"] = "%s",\n\t\t},\n'
                '\t\t["chunks"] = {\n\t\t\t[1] = "%s",\n\t\t},\n\t},\n}\n'
                % (declared_bytes, declared_sum, lua_literal(escape_high))
            ).encode('utf-8', 'surrogateescape'))
            done = subprocess.run([PY, str(path), str(saved), '--out', str(decoded)],
                                  cwd=ROOT, capture_output=True, text=True)
            report = done.stdout + done.stderr
            if done.returncode != 0 or 'integrity     : consistent' not in report:
                problems.append('a %s byte is not read as the byte it is: %s'
                                % (name, report.strip().replace('\n', ' | ')))
            elif not decoded.exists() or decoded.read_bytes() != body:
                problems.append('the %s report does not round-trip byte-exactly' % name)
    return problems


def load_build_package():
    spec = importlib.util.spec_from_file_location('build_package', ROOT / 'tools' / 'build_package.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def toc_line(zip_path: pathlib.Path) -> list[str]:
    """Every Version line WoW would read in the packaged Nexus.toc."""
    with zipfile.ZipFile(zip_path) as z:
        toc = z.read('Nexus/Nexus.toc')
    bp = load_build_package()
    lines = bp.toc_lines(toc)
    return [lines[i].strip() for i in bp.toc_directive_lines(toc, 'Version')]


def toc_version_checks(public, internal, label, other, version, commit, expect, rewrite) -> list:
    """The packaged Nexus.toc names the same build as the packaged Release.lua,
    follows the label without a source edit, and every other byte is HEAD's."""
    problems = []
    if toc_line(public) != [f'## Version: {version} {label}']:
        problems.append(f'public Nexus.toc Version is {toc_line(public)}')
    if toc_line(internal) != [f'## Version: {version} {other} internal']:
        problems.append(f'internal Nexus.toc Version is {toc_line(internal)}')

    # A second public label updates both files; the repository files are untouched.
    before = {n: (ROOT / n).read_bytes() for n in ('Nexus.toc', 'data/Release.lua')}
    third = f'test.14-{commit[:7]}'
    second = ROOT / 'dist' / f'Better-Nexus-{third}.zip'
    expect('build a second public package', run('tools/build_package.py', '--label', third, '--public', '--allow-dirty'), True)
    if second.is_file():
        with zipfile.ZipFile(second) as z:
            if f'buildLabel = "{third}"' not in z.read('Nexus/data/Release.lua').decode():
                problems.append('second package Release.lua does not carry its own label')
        if toc_line(second) != [f'## Version: {version} {third}']:
            problems.append(f'second package Nexus.toc Version is {toc_line(second)}')
        expect('consistent second public release', run('tools/release_check.py', '--label', third, '--zip', str(second)), True)
    if {n: (ROOT / n).read_bytes() for n in before} != before:
        problems.append('packaging changed a repository file')

    # The same label twice gives the same bytes.
    first_bytes = public.read_bytes()
    kept = public.with_name(public.name + '.first')
    public.rename(kept)
    expect('rebuild the public package', run('tools/build_package.py', '--label', label, '--public', '--allow-dirty'), True)
    if not public.is_file() or public.read_bytes() != first_bytes:
        problems.append('two builds of one label differ')
    if not public.is_file():
        kept.rename(public)
    else:
        kept.unlink()

    # Nothing else differs from HEAD: undo the declared substitutions and compare.
    head = load_build_package().committed_files()
    with zipfile.ZipFile(public) as z:
        for name in z.namelist():
            source = ('companion/NexusSupport/' + name[len('NexusSupport/'):]
                      if name.startswith('NexusSupport/') else name[len('Nexus/'):])
            data = z.read(name)
            if source == 'data/Release.lua':
                data = data.replace(f'buildLabel = "{label}"'.encode(), b'buildLabel = "source"')
                data = data.replace(b'channel = "public-test"', b'channel = "development"')
            elif source == 'Nexus.toc':
                data = data.replace(f'## Version: {version} {label}'.encode(), f'## Version: {version}'.encode())
            if head.get(source) != data:
                problems.append(f'packaged {name} differs from HEAD beyond the declared substitutions')
        if len(head) != len(z.namelist()):
            problems.append('the package does not hold exactly the committed runtime files')

    # Missing, duplicate and inconsistent Version metadata in an artefact.
    stamped = f'## Version: {version} {label}'

    def toc_case(dirname, change):
        target = ROOT / 'dist' / dirname / public.name
        rewrite(target, lambda n, d: change(d.decode('utf-8')).encode('utf-8') if n == 'Nexus/Nexus.toc' else d)
        return target

    for dirname, what, change in (
            ('toc-missing', 'a packaged Nexus.toc without a Version line',
             lambda t: re.sub(r'(?im)^[ \t]*##[ \t]*Version[^\n]*\n', '', t)),
            ('toc-duplicate', 'a packaged Nexus.toc with two Version lines',
             lambda t: t.replace(stamped, stamped + chr(10) + stamped)),
            ('toc-cr-duplicate', 'a packaged Nexus.toc with a second Version line after a lone CR',
             lambda t: t.replace(stamped, stamped + chr(13) + '## Version: 9.9.9')),
            ('toc-other-build', 'a packaged Nexus.toc naming another build',
             lambda t: t.replace(stamped, f'## Version: {version} test.13-{commit[:7]}')),
            ('toc-unstamped', 'a packaged Nexus.toc left at the plain version',
             lambda t: t.replace(stamped, f'## Version: {version}'))):
        expect(what, run('tools/release_check.py', '--label', label, '--zip', str(toc_case(dirname, change))), False)

    # A test label the addon would read differently is refused, public or not,
    # so the TOC and Release.lua cannot describe two builds.
    for bad in (f'test.01-{commit[:7]}', f'test.3000000000-{commit[:7]}',
                'test.5-ABCDEF0', f'test.5-{commit[:7]}' + chr(10)):
        for extra in ((), ('--public',)):
            expect(f'packaging refuses the label {bad!r} {" ".join(extra)}'.rstrip(),
                   run('tools/build_package.py', '--label', bad, *extra, '--allow-dirty'), False)
    return problems


def source_toc_checks() -> list:
    """The repository Nexus.toc is build-neutral; the packager refuses one that
    is not, and one with no or two Version lines."""
    bp = load_build_package()
    files = bp.committed_files()
    problems = []
    if bp.check(files):
        problems.append('the committed tree does not pass the package check: ' + '; '.join(bp.check(files)))
    version = bp.release_version(files['data/Release.lua'])
    toc = files['Nexus.toc']
    line = f'## Version: {version}'.encode()
    for what, bad in (('no Version line', toc.replace(line, b'## X-Version-Note: none')),
                      ('two Version lines', toc.replace(line, line + b'\n' + line)),
                      ('a stamped Version in the source', toc.replace(line, line + b' test.1-abcdef0'))):
        if not bp.check(dict(files, **{'Nexus.toc': bad})):
            problems.append('the package check accepts a repository Nexus.toc with ' + what)
        else:
            print(f'ok    the package check refuses a repository Nexus.toc with {what}')
    return problems


TEXTURE = 'ui/Textures/NexusMinimap.tga'
TEXTURE_MEMBER = 'Nexus/' + TEXTURE
# A TGA 2.0 footer: valid in other TGA files, outside the exact admitted form.
TGA_FOOTER = bytes(8) + b'TRUEVISION-XFILE.\0'


def texture_variants(tga: bytes) -> list:
    """Malformed copies of the committed texture, each wrong in one way."""
    return [
        ('a truncated minimap texture', tga[:-1]),
        ('a minimap texture with a TGA footer', tga + TGA_FOOTER),
        ('an RLE minimap texture header', tga[:2] + bytes([10]) + tga[3:]),
        ('a bottom-left minimap texture', tga[:17] + bytes([0x08]) + tga[18:]),
        ('a 24-bit minimap texture header', tga[:16] + bytes([24]) + tga[17:]),
        ('a minimap texture with an image ID length', bytes([1]) + tga[1:]),
        ('a minimap texture with a colour map', tga[:1] + bytes([1]) + tga[2:]),
        ('a 32x64 minimap texture header', tga[:12] + bytes([32]) + tga[13:]),
        ('a fully transparent minimap texture', tga[:18] + bytes(len(tga) - 18)),
        ('a minimap texture with colour in a transparent pixel', tga[:18] + bytes([255, 0, 0, 0]) + tga[22:]),
    ]


def source_texture_checks() -> list:
    """The packager admits exactly one image, the minimap texture, at its exact
    path and in its exact form. It requires it, and refuses a malformed copy,
    a case or path variant, any other image, a copy in the support component
    and a Nexus.toc that would load it as code. Each refusal must name the
    offending file, so a case cannot pass by failing for another reason."""
    bp = load_build_package()
    files = bp.committed_files()
    tga = files.get(TEXTURE)
    if tga is None or bp.texture_problems(tga, TEXTURE):
        return [f'the committed tree has no valid {TEXTURE}: '
                + '; '.join(bp.texture_problems(tga, TEXTURE))]
    print(f'ok    the committed {TEXTURE} has the exact admitted form')
    without = {n: d for n, d in files.items() if n != TEXTURE}
    png = b'\x89PNG\r\n\x1a\n' + bytes(32)
    cases = [('no minimap texture', without, TEXTURE)]
    cases += [(what, dict(files, **{TEXTURE: bad}), TEXTURE) for what, bad in texture_variants(tga)]
    for what, name, data, keep in (
            ('the texture in a lower-case folder only', 'ui/textures/NexusMinimap.tga', tga, False),
            ('the texture under a lower-case name only', 'ui/Textures/nexusminimap.tga', tga, False),
            ('an upper-case suffix copy of the texture', 'ui/Textures/NexusMinimap.TGA', tga, True),
            ('the texture misplaced in ui/', 'ui/NexusMinimap.tga', tga, True),
            ('the texture under another runtime root', 'data/Textures/NexusMinimap.tga', tga, True),
            ('an unrelated TGA beside the texture', 'ui/Textures/Other.tga', tga, True),
            ('an unrelated PNG beside the texture', 'ui/Textures/NexusMinimap.png', png, True),
            ('a copy of the texture in the support component', 'companion/NexusSupport/ui/Textures/NexusMinimap.tga', tga, True),
            ('a texture at the support component root', 'companion/NexusSupport/NexusMinimap.tga', tga, True),
            ('a traversal path to the texture', 'ui/Textures/../Textures/NexusMinimap.tga', tga, True)):
        cases.append((what, dict(files if keep else without, **{name: data}), name))
    toc = files['Nexus.toc']
    cases.append(('a Nexus.toc that loads the texture as code',
                  dict(files, **{'Nexus.toc': toc + b'\nui\\Textures\\NexusMinimap.tga\n'}),
                  'Nexus.toc must not load a texture as code: ' + TEXTURE))
    problems = []
    for what, changed, needle in cases:
        found = bp.check(changed)
        if not any(needle in p for p in found):
            problems.append(f'the package check does not refuse {what} (problems: {found})')
        else:
            print(f'ok    the package check refuses {what}')
    return problems


def texture_artifact_checks(public: pathlib.Path, label: str, expect) -> list:
    """The release check inspects archives it did not build, so it applies the
    same texture rule to the artefact: the intended member passes; a missing,
    duplicated or malformed one, any other image and any path, case or
    support-component variant fails, and the failure names that member."""
    problems = []
    with zipfile.ZipFile(public) as z:
        names = z.namelist()
        tga = z.read(TEXTURE_MEMBER) if names.count(TEXTURE_MEMBER) == 1 else None
    if tga is None:
        return [f'the public package does not hold {TEXTURE_MEMBER} exactly once']
    if load_build_package().committed_files().get(TEXTURE) != tga:
        problems.append(f'the packaged {TEXTURE_MEMBER} differs from HEAD')
    dist = public.parent

    def crafted(dirname, change=None, drop=False, extras=()):
        target = dist / dirname / public.name
        target.parent.mkdir()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')   # a deliberate duplicate member warns
            with zipfile.ZipFile(public) as z, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as out:
                for item in z.infolist():
                    data = z.read(item.filename)
                    if item.filename == TEXTURE_MEMBER:
                        if drop:
                            continue
                        if change:
                            data = change(data)
                    out.writestr(item, data)
                for name, data in extras:
                    out.writestr(name, data)
        return target

    def release_check(target):
        done = subprocess.run([PY, 'tools/release_check.py', '--label', label, '--zip', str(target)],
                              cwd=ROOT, capture_output=True, text=True)
        return done.returncode, done.stdout + done.stderr

    # Control: rewriting the archive with the texture unchanged still passes,
    # so each refusal below comes from its one change.
    code, report = release_check(crafted('texture-same'))
    expect('a rewritten package with the intended minimap texture', code, True)
    if code != 0:
        problems.append('the intended texture is refused: ' + report.strip().replace('\n', ' | '))

    png = b'\x89PNG\r\n\x1a\n' + bytes(32)
    cases = [('texture-missing', 'a package without the minimap texture', {'drop': True}, TEXTURE_MEMBER),
             ('texture-duplicate', 'a package with the minimap texture twice',
              {'extras': ((TEXTURE_MEMBER, tga),)}, 'exactly once')]
    for index, (what, bad) in enumerate(texture_variants(tga)):
        cases.append((f'texture-bad-{index}', 'a package with ' + what, {'change': lambda d, bad=bad: bad},
                      TEXTURE_MEMBER))
    for dirname, what, name, data, drop in (
            ('texture-lower-folder', 'the texture only in a lower-case folder', 'Nexus/ui/textures/NexusMinimap.tga', tga, True),
            ('texture-lower-name', 'the texture only under a lower-case name', 'Nexus/ui/Textures/nexusminimap.tga', tga, True),
            ('texture-upper-suffix', 'an upper-case suffix copy of the texture', 'Nexus/ui/Textures/NexusMinimap.TGA', tga, False),
            ('texture-misplaced', 'the texture misplaced in Nexus/ui/', 'Nexus/ui/NexusMinimap.tga', tga, False),
            ('texture-root', 'the texture at the Nexus/ root', 'Nexus/NexusMinimap.tga', tga, False),
            ('texture-other-tga', 'an unrelated TGA', 'Nexus/ui/Textures/Other.tga', tga, False),
            ('texture-png', 'an unrelated PNG', 'Nexus/ui/Textures/NexusMinimap.png', png, False),
            ('texture-support', 'a copy of the texture in the support component', 'NexusSupport/ui/Textures/NexusMinimap.tga', tga, False),
            ('texture-support-root', 'a texture at the support component root', 'NexusSupport/NexusMinimap.tga', tga, False)):
        cases.append((dirname, 'a package with ' + what, {'drop': drop, 'extras': ((name, data),)}, name))
    cases.append(('texture-traversal', 'a package with a traversal path to the texture',
                  {'extras': (('Nexus/ui/Textures/../Textures/NexusMinimap.tga', tga),)}, 'escapes its folder'))
    cases.append(('texture-toc', 'a package whose Nexus.toc loads the texture as code', {},
                  'must not load a texture as code: ' + TEXTURE))
    for dirname, what, options, needle in cases:
        if dirname == 'texture-toc':
            target = dist / dirname / public.name
            target.parent.mkdir()
            with zipfile.ZipFile(public) as z, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as out:
                for item in z.infolist():
                    data = z.read(item.filename)
                    if item.filename == 'Nexus/Nexus.toc':
                        data = data + b'\nui\\Textures\\NexusMinimap.tga\n'
                    out.writestr(item, data)
        else:
            target = crafted(dirname, **options)
        code, report = release_check(target)
        expect(what, code, False)
        if code != 0 and needle not in report:
            problems.append(f'{what} is refused, but the report does not name {needle}: '
                            + report.strip().replace('\n', ' | '))
    return problems


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
        failures.extend(toc_version_checks(public, internal, label, other, version, commit, expect, rewrite))
        failures.extend(source_toc_checks())
        failures.extend(source_texture_checks())
        failures.extend(texture_artifact_checks(public, label, expect))
        failures.extend(decoder_bytes_checks())
    finally:
        shutil.rmtree(dist, ignore_errors=True)
    if failures:
        print('RESULT: FAILED:', '; '.join(failures)); return 1
    print('RESULT: release identity checks pass and fail where they must; dist/ removed; nothing published')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
