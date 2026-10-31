"""Full visible-UI localization: the final six-pack composition gate (Refs #143-#148, #147).

Registered in PYTHON_TESTS of tools/run_prototype_tests.py; tools/ci_check.py runs it as its own
process within PYTHON_TEST_TIMEOUT_SECONDS. It needs `luajit` on PATH, as the CI suite does: a
missing runtime fails the gate (runtime-unavailable), it is never skipped.

ActualRepositoryGate is the required gate over the actual checkout: it fails while any shipped
optional pack is incomplete, and passes once the final composition is complete and coherent.
Every other test uses known-good literals or a synthetic composition generated here from the
actual English: each optional language shifts the ASCII letters of every entry (placeholders
kept), and an entry without letters is declared legitimately identical by a synthetic entry-review
record that grants nothing. The full-size composition must pass the very same gate, static and
runtime. The static mutants use a reduced synthetic catalog (REDUCED_KEYS, all four kinds, with
its declarations, English and key-context rows regenerated from the actual ones), so each check
stays inside the whole-process limit; each mutant must fail for its intended reason. Synthetic
offline evidence only: no translation quality, rights, native glyph, layout or reload claim.
"""
import hashlib, importlib.util, io, json, pathlib, sys, tempfile, unittest, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = _load('l10n_full_ui_gate_under_test', ROOT / 'tools' / 'l10n_full_ui_gate.py')
# The independent literal oracle of the original 28 meanings (key, kind, exact English, producer).
CATALOG_TEST = _load('l10n_catalog_literals', ROOT / 'tools' / 'tests' / 'test_l10n_catalog.py')
ORIGINAL_28 = CATALOG_TEST.CURRENT_KEYS
ORIGINAL_PACK_COHORT = CATALOG_TEST.CURRENT_PACK_KEYS


def codes(report):
    return sorted({problem['code'] for problem in report['problems']})


def problem_keys(report, code):
    return sorted(problem.get('key') for problem in report['problems'] if problem['code'] == code)


def shift(text, amount):
    """The ASCII letters of text shifted by amount; {placeholders} and {{ }} kept."""
    out, index = [], 0
    while index < len(text):
        char = text[index]
        if char == '{' and text[index + 1:index + 2] != '{':
            close = text.index('}', index)
            out.append(text[index:close + 1])
            index = close + 1
            continue
        if char == '{':
            out.append('{{')
            index += 2
            continue
        if 'a' <= char <= 'z':
            char = chr((ord(char) - 97 + amount) % 26 + 97)
        elif 'A' <= char <= 'Z':
            char = chr((ord(char) - 65 + amount) % 26 + 65)
        out.append(char)
        index += 1
    return ''.join(out)


def packs_source(packs):
    """A literal packs file: {productId: (name, {key: text})}."""
    lines = ['Nexus = Nexus or {}', 'Nexus.LocalizationPacks = {']
    for product, (name, entries) in packs.items():
        lines.append('    %s = {' % product)
        lines.append('        name = %s,' % G._lua_string(name))
        lines.append('        entries = {')
        for key, text in entries.items():
            lines.append('            [%s] = %s,' % (G._lua_string(key), G._lua_string(text)))
        lines.append('        },')
        lines.append('    },')
    lines.append('}')
    return ('\r\n'.join(lines) + '\r\n').encode('utf-8')


ACTUAL = G.read_sources(ROOT)
STATIC = G.evaluate(ACTUAL)
MODEL = STATIC['model']

# The reduced catalog: the original 28, every receiver probe key and its slot keys, a block, a
# lines template and an entry without letters.
REDUCED_KEYS = [row[0] for row in ORIGINAL_28] + [
    'panel.label.more_count', 'panel.tooltip.size_explained', 'panel.chat.language_refused',
    'panel.status.language_reason_refused', 'usertext.body.glossary', 'guide.body.target_c_select',
    'leaderboard.column.rank', 'panel.tooltip.extra_above_targets',
    'help.body.troubleshooting_commands_2']


def declaration_line(key, declaration):
    quoted = lambda names: '{' + ', '.join('"%s"' % name for name in names) + '}'
    kind = declaration['kind']
    if kind in ('text', 'block'):
        body = 'kind = "%s"' % kind
    elif kind == 'format':
        body = 'fields = %s, kind = "format", slot = "count", resultLimit = %d' % (
            quoted(declaration['fields']), declaration['resultLimit'])
    else:
        body = 'kind = "template", fields = %s, slots = %s, resultLimit = %d' % (
            quoted(declaration['fields']), quoted(declaration['slots']), declaration['resultLimit'])
        if declaration.get('lines'):
            body += ', lines = true'
    return '    ["%s"] = {%s},' % (key, body)


def reduced_sources(keys=REDUCED_KEYS):
    text = ACTUAL['localization'].decode('utf-8')
    begin, end = '-- NEXUS-L10N-REGISTRY BEGIN\r\n', '-- NEXUS-L10N-REGISTRY END'
    head, rest = text.split(begin)
    _, tail = rest.split(end)
    block = ['local DECLARATIONS = {'] + [declaration_line(key, MODEL['declarations'][key]) for key in keys] + ['}']
    localization = head + begin + '\r\n'.join(block) + '\r\n' + end + tail
    english = ['Nexus = Nexus or {}', 'Nexus.LocalizationEnglish = {'] + [
        '    [%s] = %s,' % (G._lua_string(key), G._lua_string(MODEL['active'][key])) for key in keys] + ['}']
    context = json.loads(ACTUAL['keyContext'].decode('utf-8'))
    rows = {row['key']: row for row in context['keys']}
    context['keys'] = [rows[key] for key in keys]
    return dict(ACTUAL, localization=localization.encode('utf-8'),
                english=('\r\n'.join(english) + '\r\n').encode('utf-8'),
                keyContext=json.dumps(context, ensure_ascii=False).encode('utf-8'))


REDUCED = reduced_sources()
REDUCED_MODEL = G.evaluate(REDUCED)['model']


def synthetic_packs(model=REDUCED_MODEL):
    packs = {}
    for index, row in enumerate(model['products']):
        entries = {key: shift(text, index + 1) for key, text in model['active'].items()}
        packs[row['productId']] = (row['autonym'], entries)
    return packs


def synthetic_release(packs, release=ACTUAL['release'], model=REDUCED_MODEL):
    document = json.loads(release.decode('utf-8'))
    declarations = []
    for product, (_, entries) in packs.items():
        for key, text in entries.items():
            if text == model['active'].get(key):
                declarations.append({
                    'productId': product, 'key': key,
                    'translatedTextSha256': hashlib.sha256(text.encode('utf-8')).hexdigest(),
                    'reviewer': 'SYNTHETIC TEST FIXTURE (not a review)', 'decision': 'legitimately_identical',
                    'evidenceReference': 'https://example.invalid/synthetic-fixture', 'status': 'declared'})
    document['entryReview']['declarations'] = declarations
    return json.dumps(document, ensure_ascii=False, indent=1).encode('utf-8')


def composed(mutate=None, base=None, model=None, **replace):
    """The reduced (or, with base=ACTUAL, model=MODEL, the full) catalog with a complete
    synthetic composition (packs and release)."""
    base, model = base or REDUCED, model or REDUCED_MODEL
    packs = synthetic_packs(model)
    if mutate:
        mutate(packs)
    sources = dict(base)
    sources['packs'] = packs_source(packs)
    sources['release'] = synthetic_release(packs, model=model)
    sources.update(replace)
    return sources


FULL = {}


def full_composition():
    """The full-size synthetic composition and its static model, built once."""
    if not FULL:
        FULL['sources'] = composed(base=ACTUAL, model=MODEL)
        FULL['model'] = G.evaluate(FULL['sources'])['model']
    return FULL['sources'], FULL['model']


def with_declarations(extra=(), replace=()):
    """The reduced core/Localization.lua with extra declaration lines and exact replacements."""
    text = REDUCED['localization'].decode('utf-8')
    for old, new in replace:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    opener = 'local DECLARATIONS = {\r\n'
    assert text.count(opener) == 1
    text = text.replace(opener, opener + ''.join(line + '\r\n' for line in extra))
    return text.encode('utf-8')


def with_english(extra=(), replace=()):
    text = REDUCED['english'].decode('utf-8')
    for old, new in replace:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    opener = 'Nexus.LocalizationEnglish = {\r\n'
    assert text.count(opener) == 1
    text = text.replace(opener, opener + ''.join(line + '\r\n' for line in extra))
    return text.encode('utf-8')


def rewrite_json(name, change):
    document = json.loads(REDUCED[name].decode('utf-8'))
    change(document)
    return json.dumps(document, ensure_ascii=False, indent=1).encode('utf-8')


class GateRun:
    """Each full gate run (static + LuaJIT) once per process."""
    cache = {}

    @classmethod
    def get(cls, name, **arguments):
        if name not in cls.cache:
            cls.cache[name] = G.gate(ROOT, **arguments)
        return cls.cache[name]


def synthetic_paths(scratch, sources):
    path = pathlib.Path(scratch) / 'LocalizationPacks.lua'
    path.write_bytes(sources['packs'])
    return {'english': 'data/LocalizationEnglish.lua', 'packs': str(path),
            'localization': 'core/Localization.lua'}


class ActualRepositoryGate(unittest.TestCase):
    """The required gate: the actual shipped composition of this checkout."""

    def test_actual_shipped_composition_passes_the_full_gate(self):
        report = GateRun.get('actual')
        lines = G.summary_lines(report, limit=4)
        self.assertEqual(report['verdict'], 'PASS', 'the actual shipped composition fails the full '
                         'visible-UI gate:\n' + '\n'.join(lines).encode('ascii', 'replace').decode('ascii'))


class ActualRepositoryFacts(unittest.TestCase):
    """Facts of the actual checkout that hold before and after the final composition."""

    def test_only_pack_coverage_can_fail_and_the_runtime_agrees(self):
        report = GateRun.get('actual')
        self.assertEqual([code for code in codes(report) if not code.startswith('entry-')], [])
        self.assertEqual(report['runtime']['status'], 'RAN')
        for product in report['products']:
            self.assertEqual(sum(product['counts'][name] for name in G.CATEGORIES)
                             - sum(product['counts'][name] for name in ('unknown', 'orphan', 'obsolete')),
                             product['active'], product['productId'])

    def test_key_set_kinds_and_products_are_derived_from_the_actual_bytes(self):
        catalog = STATIC['catalog']
        self.assertEqual(catalog['declared'], catalog['english'])
        self.assertEqual(catalog['declared'], catalog['active'])
        self.assertEqual(sum(catalog['byKind'].values()), catalog['active'])
        self.assertEqual(catalog['byKind']['format'], 1)
        self.assertLessEqual(catalog['active'], G.MAX_ENTRIES)
        self.assertEqual([row['productId'] for row in MODEL['products']],
                         ['frFR', 'deDE', 'esES', 'plPL', 'ptBR', 'ruRU'])
        self.assertEqual([row['autonym'] for row in MODEL['products']],
                         [row[3] for row in CATALOG_TEST.EXPECTED_PRODUCTS[1:]])

    def test_original_28_meanings_keep_their_keys_kinds_and_exact_english(self):
        self.assertEqual(len(ORIGINAL_28), 28)
        for key, kind, english, _ in ORIGINAL_28:
            self.assertEqual(MODEL['declarations'][key]['kind'], kind, key)
            self.assertEqual(MODEL['active'][key], english, key)
        self.assertEqual(MODEL['declarations']['readout.charge_counts'],
                         {'kind': 'format', 'fields': ('banish', 'reroll', 'freeze'),
                          'slots': ('count', 'count', 'count'), 'resultLimit': 254})

    def test_old_27_entry_cohort_stays_valid_in_every_shipped_pack(self):
        self.assertEqual(len(ORIGINAL_PACK_COHORT), 27)
        for product in STATIC['products']:
            for key in ORIGINAL_PACK_COHORT:
                self.assertNotIn(key, product['categories']['missing'], product['productId'])
                self.assertNotIn(key, product['categories']['invalid'], product['productId'])

    def test_the_gate_reads_its_inputs_and_changes_none(self):
        before = {name: hashlib.sha256(data).hexdigest() for name, data in G.read_sources(ROOT).items()}
        GateRun.get('actual')
        after = {name: hashlib.sha256(data).hexdigest() for name, data in G.read_sources(ROOT).items()}
        self.assertEqual(before, after)
        self.assertNotIn('input-changed', codes(GateRun.get('actual')))

    def test_report_records_source_identity_and_exact_input_hashes(self):
        report = GateRun.get('actual')
        self.assertEqual([row['path'] for row in report['inputs']], [path for _, path in G.INPUTS])
        for row in report['inputs']:
            self.assertEqual(row['sha256'], hashlib.sha256((ROOT / row['path']).read_bytes()).hexdigest())
        identity = report['sourceIdentity']
        if identity['status'] == 'OBSERVED':
            self.assertRegex(identity['commit'], '^[0-9a-f]{40}$')
            self.assertRegex(identity['tree'], '^[0-9a-f]{40}$')
            self.assertEqual([row['path'] for row in identity['blobs']], [path for _, path in G.INPUTS])
            if identity['inputsClean']:
                self.assertTrue(all(row['matchesIndex'] for row in identity['blobs']))
        else:
            self.assertEqual(identity['status'], 'UNKNOWN')

    def main(self, arguments):
        stdout, real = io.StringIO(), sys.stdout
        sys.stdout = stdout
        try:
            return G.main(arguments), stdout.getvalue()
        finally:
            sys.stdout = real

    def test_command_line_exit_follows_the_verdict(self):
        with tempfile.TemporaryDirectory() as scratch:
            output = pathlib.Path(scratch) / 'report.json'
            status, shown = self.main(['--output', str(output)])
            report = json.loads(output.read_text(encoding='utf-8'))
        self.assertEqual(status, 0 if report['verdict'] == 'PASS' else 1)
        self.assertIn('RESULT: ' + report['verdict'], shown)
        status, shown = self.main(['--receipt', str(ROOT / 'no-such-receipt.json')])
        self.assertEqual(status, 2)
        self.assertTrue(shown.startswith('UNREADABLE: '))


class SyntheticComposition(unittest.TestCase):
    """A clean synthetic six-pack composition passes the same gate."""

    def test_complete_synthetic_composition_passes_static_runtime_and_receivers(self):
        # One shared run of the same inputs (synthetic_full_gate) also serves RealReceivers.
        report = synthetic_full_gate()
        self.assertEqual(report['problems'], [])
        self.assertEqual(report['verdict'], 'PASS')
        for product in report['products']:
            self.assertTrue(product['complete'])
            self.assertEqual(product['counts']['missing'], 0)
            self.assertGreater(product['counts']['legitimately_identical'], 0)
            self.assertEqual(product['counts']['draft'] + product['counts']['legitimately_identical'],
                             product['active'])
        probes = report['runtime']['probes']
        self.assertEqual(len(probes), 3 * 6 * len(G.RECEIVER_PROBES))
        self.assertTrue(all(row['result'] == 'PASS' for row in probes))
        # Not vacuous: each receiver shows its candidate in the complete run, English otherwise.
        for row in probes:
            want = 'candidate' if row['run'].startswith('complete:') else 'base'
            self.assertEqual(row['source'], want, row)
        kinds = {MODEL['declarations'][probe['key']]['kind'] for probe in G.RECEIVER_PROBES}
        self.assertTrue(all(probe['key'] in REDUCED_KEYS for probe in G.RECEIVER_PROBES))
        self.assertEqual(kinds, {'text', 'block', 'format', 'template'})
        slot_types = {slot for probe in G.RECEIVER_PROBES
                      for slot in MODEL['declarations'][probe['key']].get('slots', ())}
        self.assertEqual(slot_types, {'count', 'text'})

    def test_static_bytes_the_runtime_does_not_load_are_refused(self):
        # The static model claims the complete synthetic composition; the runtime loads (through the
        # synthetic_paths seam) the same packs with one first-pack entry removed. The shipped packs
        # are not used: their counts can match a model while their text differs (seam only).
        sources, model = full_composition()
        product, following = (row['productId'] for row in model['products'][:2])
        key = 'panel.button.my_builds'
        text = model['packs'][product]['entries'][key]
        self.assertEqual(text, shift(model['active'][key], 1))
        self.assertNotEqual(text, model['active'][key])
        self.assertEqual(sorted(model['packs'][product]['entries']), sorted(model['active']))
        full = sources['packs']
        line = ('            [%s] = %s,\r\n' % (G._lua_string(key), G._lua_string(text))).encode('utf-8')
        self.assertEqual(full.count(line), 1)
        begin = full.index(('    %s = {\r\n' % product).encode('utf-8'))
        end = full.index(('    %s = {\r\n' % following).encode('utf-8'))
        self.assertLess(begin, full.index(line))
        self.assertLess(full.index(line), end)
        loaded = full.replace(line, b'')
        entry_lines = lambda data, stop: data[begin:stop].count(b'\r\n            [')
        # The intended input difference: exactly one entry fewer in that pack, every other byte kept.
        self.assertEqual(entry_lines(full, end), len(model['active']))
        self.assertEqual(entry_lines(loaded, end - len(line)), len(model['active']) - 1)
        self.assertEqual(loaded[:begin], full[:begin])
        self.assertEqual(loaded[end - len(line):], full[end:])
        with tempfile.TemporaryDirectory(prefix='nexus-gate-test-') as scratch:
            paths = synthetic_paths(scratch, dict(sources, packs=loaded))
            self.assertEqual(pathlib.Path(paths['packs']).read_bytes(), loaded)
            problems, evidence = G.runtime_check(ROOT, model, paths=paths)
        found = sorted({problem['code'] for problem in problems})
        self.assertEqual(evidence['status'], 'RAN')
        self.assertIn('runtime-seam-mismatch', found)
        self.assertIn('runtime-load-mismatch', found)
        # Each for the intended reason: the removed key's seam, and that pack's admitted count.
        self.assertEqual(found, ['runtime-load-mismatch', 'runtime-seam-mismatch'])
        seam = [(p['path'], p.get('key')) for p in problems if p['code'] == 'runtime-seam-mismatch']
        self.assertEqual(seam, [('complete:' + product, key)])
        load = [p for p in problems if p['code'] == 'runtime-load-mismatch']
        self.assertIn('complete:' + product, [p['path'] for p in load])
        self.assertTrue(all(p['detail'].startswith('pack rows ') for p in load), load)


class PackCoverageMutants(unittest.TestCase):
    """Each category fails (or is reported) for its own reason; only pure static checks."""

    def product(self, report, product_id):
        return next(row for row in report['products'] if row['productId'] == product_id)

    def test_clean_composition_is_clean_statically(self):
        self.assertEqual(G.evaluate(composed())['problems'], [])

    def test_missing_entry_fails_only_its_pack(self):
        def mutate(packs):
            del packs['deDE'][1]['panel.button.my_builds']
        report = G.evaluate(composed(mutate))
        self.assertEqual(codes(report), ['entry-missing'])
        self.assertEqual(self.product(report, 'deDE')['categories']['missing'], ['panel.button.my_builds'])
        self.assertTrue(self.product(report, 'frFR')['complete'])

    def test_invalid_entries_fail_with_their_contract_reason(self):
        text_key = 'panel.button.my_builds'
        block_key = next(key for key, d in REDUCED_MODEL['declarations'].items() if d['kind'] == 'block')
        lines_key = next(key for key, d in REDUCED_MODEL['declarations'].items() if d.get('lines'))
        template_key = 'panel.label.more_count'
        cases = [
            (text_key, 'a|b', 'pipe'), (text_key, 'a\nb', 'line-feed'), (text_key, 'x' * 257, 'byte-length'),
            (text_key, '   ', 'whitespace-only'), (text_key, 'a\tb', 'control-byte'),
            (text_key, 'a\x01b', 'control-byte'), (text_key, 'a\x7fb', 'control-byte'),
            (block_key, 'a\r\nb', 'control-byte'), (block_key, 'x' * 1025, 'byte-length'),
            (template_key, 'more', 'template-grammar'), (template_key, '{count} {count}', 'template-grammar'),
            (template_key, '{other} more', 'template-grammar'), (template_key, '{count} {', 'template-grammar'),
            (template_key, '{count} }', 'template-grammar'),
        ]
        for key, text, reason in cases:
            with self.subTest(key=key, reason=reason):
                def mutate(packs):
                    packs['esES'][1][key] = text
                report = G.evaluate(composed(mutate))
                self.assertEqual(codes(report), ['entry-invalid'])
                self.assertEqual(self.product(report, 'esES')['invalidReasons'], {key: reason})
        # The boundaries themselves are valid.
        for key, text in ((text_key, 'x' * 256), (block_key, ('x' * 511 + '\n') * 2), (lines_key, None),
                          (template_key, '{{literal}} {count}'), (template_key, '\u00e9' * 100 + '{count}')):
            if text is None:
                fields = REDUCED_MODEL['declarations'][lines_key]['fields']
                text = 'first line\nsecond ' + ' '.join('{%s}' % name for name in fields)
            with self.subTest(boundary=key):
                def mutate(packs):
                    packs['esES'][1][key] = text
                self.assertEqual(G.evaluate(composed(mutate))['problems'], [])

    def test_identical_entry_needs_a_matching_declaration(self):
        key = 'panel.button.my_builds'
        packs = synthetic_packs()
        packs['plPL'][1][key] = REDUCED_MODEL['active'][key]
        undeclared = dict(REDUCED, packs=packs_source(packs), release=synthetic_release(synthetic_packs()))
        report = G.evaluate(undeclared)
        self.assertEqual(codes(report), ['entry-english-placeholder'])
        self.assertEqual(self.product(report, 'plPL')['categories']['english_placeholder'], [key])
        declared = dict(REDUCED, packs=packs_source(packs), release=synthetic_release(packs))
        report = G.evaluate(declared)
        self.assertEqual(report['problems'], [])
        self.assertIn(key, self.product(report, 'plPL')['categories']['legitimately_identical'])

    def test_stale_or_contradicting_declaration_is_refused(self):
        packs = synthetic_packs()
        release = json.loads(synthetic_release(packs))
        first = release['entryReview']['declarations'][0]
        first['translatedTextSha256'] = '0' * 64
        report = G.evaluate(dict(REDUCED, packs=packs_source(packs),
                                 release=json.dumps(release).encode('utf-8')))
        self.assertIn('entry-review-stale', codes(report))
        self.assertIn('entry-english-placeholder', codes(report))
        key = 'panel.button.my_builds'
        text = packs['frFR'][1][key]
        release = json.loads(synthetic_release(packs))
        release['entryReview']['declarations'].append({
            'productId': 'frFR', 'key': key, 'translatedTextSha256': hashlib.sha256(text.encode()).hexdigest(),
            'reviewer': 'x', 'decision': 'legitimately_identical', 'evidenceReference': 'https://e.invalid',
            'status': 'declared'})
        report = G.evaluate(dict(REDUCED, packs=packs_source(packs), release=json.dumps(release).encode('utf-8')))
        self.assertEqual(codes(report), ['entry-review-contradiction'])

    def test_unknown_orphan_and_obsolete_entries_are_separate_failures(self):
        def mutate(packs):
            packs['ptBR'][1]['Bad.Key'] = 'x'
            packs['ptBR'][1]['panel.never_declared'] = 'x'
            packs['ptBR'][1]['panel.retired_meaning'] = 'x'
        context = rewrite_json('keyContext', lambda d: d['retiredKeys'].__setitem__('keys', ['panel.retired_meaning']))
        report = G.evaluate(composed(mutate, keyContext=context))
        self.assertEqual(codes(report), ['entry-obsolete', 'entry-orphan', 'entry-unknown'])
        categories = self.product(report, 'ptBR')['categories']
        self.assertEqual((categories['unknown'], categories['orphan'], categories['obsolete']),
                         (['Bad.Key'], ['panel.never_declared'], ['panel.retired_meaning']))

    def test_actual_partial_pack_shape_is_missing_not_english_filled(self):
        # English fallback never counts: the actual draft packs miss every other key.
        for product in STATIC['products']:
            self.assertEqual(product['counts']['missing'], product['active'] - product['entries'])
            self.assertEqual(sorted(set(MODEL['active']) - set(product['categories']['missing'])),
                             sorted(MODEL['packs'][product['productId']]['entries']))

    def test_pack_set_autonym_and_cap(self):
        def drop(packs):
            del packs['ruRU']
        report = G.evaluate(composed(drop))
        self.assertEqual(codes(report), ['entry-missing', 'pack-absent', 'pack-set'])
        self.assertEqual(self.product(report, 'ruRU')['counts']['missing'], len(REDUCED_MODEL['active']))

        def rename(packs):
            packs['deDE'] = ('German', packs['deDE'][1])
        self.assertEqual(codes(G.evaluate(composed(rename))), ['autonym-mismatch'])

        def grow(count):
            def mutate(packs):
                entries = packs['frFR'][1]
                for index in range(count - len(entries)):
                    entries['zz.extra_%04d' % index] = 'x'
            return mutate
        at_cap = G.evaluate(composed(grow(G.MAX_ENTRIES)))
        self.assertEqual(codes(at_cap), ['entry-orphan'])
        over = G.evaluate(composed(grow(G.MAX_ENTRIES + 1)))
        self.assertIn('pack-over-cap', codes(over))
        self.assertEqual(self.product(over, 'frFR')['counts']['missing'], len(REDUCED_MODEL['active']))


class ContractMutants(unittest.TestCase):
    """The code-owned schema is checked independently of the metadata."""

    def test_declaration_schema_mutants_are_refused(self):
        template = '["panel.label.more_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},'
        assert ACTUAL['localization'].decode().count(template) == 1
        assert REDUCED['localization'].decode().count(template) == 1
        cases = {
            'lines': template.replace('resultLimit = 120', 'resultLimit = 120, lines = false'),
            'slots': template.replace('slots = {"count"}', 'slots = {"count", "text"}'),
            'slots-type': template.replace('slots = {"count"}', 'slots = {"number"}'),
            'result-limit-high': template.replace('resultLimit = 120', 'resultLimit = 2049'),
            'result-limit-zero': template.replace('resultLimit = 120', 'resultLimit = 0'),
            'placeholders': template.replace('fields = {"count"}', 'fields = {"count", "count"}'),
            'fields': template.replace('resultLimit = 120', 'resultLimit = 120, extra = "x"'),
        }
        expected = {'lines': 'lines', 'slots': 'slots', 'slots-type': 'slots', 'result-limit-high': 'result-limit',
                    'result-limit-zero': 'result-limit', 'placeholders': 'placeholders', 'fields': 'fields'}
        for name, line in cases.items():
            with self.subTest(name=name):
                report = G.evaluate(composed(localization=with_declarations(replace=[(template, line)])))
                rows = [p for p in report['problems'] if p['code'] == 'declaration-invalid']
                self.assertEqual([(p['key'], p['detail']) for p in rows],
                                 [('panel.label.more_count', expected[name])])
                self.assertIn('english-undeclared', codes(report))
        ok = template.replace('resultLimit = 120', 'resultLimit = 2048')
        report = G.evaluate(composed(localization=with_declarations(replace=[(template, ok)])))
        self.assertEqual(codes(report), ['context-mismatch'])
        charge = '["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},'
        report = G.evaluate(composed(localization=with_declarations(replace=[(
            'kind = "format", slot = "count", resultLimit = 254},',
            'kind = "format", slot = "count", resultLimit = 253},')])))
        self.assertEqual(problem_keys(report, 'declaration-invalid'), ['readout.charge_counts'])
        self.assertTrue(charge)
        text = '["panel.button.my_builds"] = {kind = "text"},'
        report = G.evaluate(composed(localization=with_declarations(replace=[(
            text, '["panel.button.my_builds"] = {kind = "text", lines = true},')])))
        self.assertEqual(problem_keys(report, 'declaration-invalid'), ['panel.button.my_builds'])

    def test_declaration_and_english_caps_fail_closed_at_cap_plus_one(self):
        room = G.MAX_ENTRIES - len(REDUCED_MODEL['declarations'])
        extra = ['["zz.extra_%04d"] = {kind = "text"},' % index for index in range(room)]
        at_cap = G.evaluate(composed(localization=with_declarations(extra)))
        self.assertNotIn('declarations-over-cap', codes(at_cap))
        self.assertEqual(len(problem_keys(at_cap, 'english-missing')), room)
        over = G.evaluate(composed(localization=with_declarations(extra + ['["zz.extra_over"] = {kind = "text"},'])))
        self.assertIn('declarations-over-cap', codes(over))
        self.assertEqual(over['catalog']['active'], 0)
        english = ['["zz.extra_%04d"] = "x",' % index for index in range(room + 1)]
        over = G.evaluate(composed(english=with_english(english)))
        self.assertIn('english-over-cap', codes(over))
        self.assertEqual(over['catalog']['active'], 0)

    def test_runtime_contract_constant_change_is_not_followed_silently(self):
        observed = G.runtime_constants(ACTUAL['localization'])
        self.assertEqual({name: observed.get(name) for name in G.CONTRACT}, dict(G.CONTRACT))
        source = with_declarations(replace=[('local MAX_BASE_ENTRIES = 4096', 'local MAX_BASE_ENTRIES = 4097')])
        self.assertEqual(codes(G.evaluate(composed(localization=source))), ['contract-constant'])

    def test_english_and_context_must_agree_with_the_declarations(self):
        key = 'panel.button.my_builds'
        english = with_english(replace=[('["%s"] = "My Builds",' % key, '["%s"] = "My|Builds",' % key)])
        report = G.evaluate(composed(english=english))
        self.assertEqual(problem_keys(report, 'english-invalid'), [key])

        def drift(document):
            row = next(row for row in document['keys'] if row['key'] == key)
            row['english'] = 'My builds'
            lines = next(row for row in document['keys'] if row.get('lines'))
            del lines['lines']
            document['keys'] = [row for row in document['keys'] if row['key'] != 'panel.button.options']
        report = G.evaluate(composed(keyContext=rewrite_json('keyContext', drift)))
        self.assertEqual(codes(report), ['context-mismatch', 'context-missing'])
        self.assertEqual(sorted(p['detail'] for p in report['problems'] if p['code'] == 'context-mismatch'),
                         ['english', 'lines'])

    def test_toc_order_profile_and_products_must_agree(self):
        toc = ACTUAL['toc'].replace(b'data\\LocalizationPacks.lua\r\ncore\\Localization.lua',
                                    b'core\\Localization.lua\r\ndata\\LocalizationPacks.lua')
        self.assertNotEqual(toc, ACTUAL['toc'])
        self.assertEqual(codes(G.evaluate(composed(toc=toc))), ['toc-order'])
        profile = ACTUAL['profile'].replace(b'"ptBR", "ruRU" }', b'"ptBR" }')
        self.assertNotEqual(profile, ACTUAL['profile'])
        self.assertIn('products-mismatch', codes(G.evaluate(composed(profile=profile))))


class CompositionReceipt(unittest.TestCase):
    """A supplied receipt binds the composed bytes and an explicit contract version."""

    def receipt(self, sources, basis='exact-supplied-bytes', overrides=(), **change):
        document = {'schema': G.RECEIPT_SCHEMA, 'schemaVersion': 1, 'contractVersion': 'synthetic-v3',
                    'hashBasis': basis,
                    'inputs': {G.INPUT_PATHS[name]: hashlib.sha256(G._basis_bytes(sources[name], basis)).hexdigest()
                               for name in ('english', 'packs', 'localization')},
                    'products': [row['productId'] for row in REDUCED_MODEL['products']],
                    'contractOverrides': list(overrides)}
        document.update(change)
        return json.dumps(document).encode('utf-8')

    def test_matching_receipt_and_required_receipt(self):
        sources = composed()
        report = G.evaluate(sources, self.receipt(sources), require_receipt=True)
        self.assertEqual(report['problems'], [])
        self.assertEqual(report['compositionReceipt']['status'], 'CURRENT_INPUTS_MATCHED')
        self.assertEqual(codes(G.evaluate(sources, None, require_receipt=True)), ['receipt-missing'])
        self.assertEqual(G.evaluate(sources)['compositionReceipt'], {'status': 'NOT_SUPPLIED'})

    def test_stale_wrong_products_and_basis_are_refused(self):
        sources = composed()
        stale = self.receipt(composed(lambda packs: packs['frFR'][1].__setitem__('panel.button.my_builds', 'Zz')))
        self.assertEqual(codes(G.evaluate(sources, stale)), ['receipt-stale'])
        self.assertEqual(codes(G.evaluate(sources, self.receipt(sources, products=['frFR']))), ['receipt-products'])
        # A Git-LF hash is a different fact from the physical CRLF bytes: it binds only under its basis.
        lf = self.receipt(sources, basis='crlf-as-lf')
        self.assertEqual(G.evaluate(sources, lf)['compositionReceipt']['status'], 'CURRENT_INPUTS_MATCHED')
        forged = json.loads(lf)
        forged['hashBasis'] = 'exact-supplied-bytes'
        self.assertEqual(codes(G.evaluate(sources, json.dumps(forged).encode())), ['receipt-stale'])
        self.assertEqual(codes(G.evaluate(sources, b'{"schema": 1}')), ['receipt-structure'])

    def test_contract_override_must_match_the_actual_declarations(self):
        # A reduced-catalog key the actual source still declares as text
        # (panel.tooltip.size_explained, the earlier example, became a block in the reviewed v4
        # contract, so a text -> block override of it is no longer stale).
        key = 'leaderboard.column.rank'
        override = {'key': key, 'kind': 'block', 'previousKind': 'text'}
        sources = composed()
        # The actual declaration is still text: an anticipated v3 receipt is stale composition.
        self.assertEqual(codes(G.evaluate(sources, self.receipt(sources, overrides=[override]))),
                         ['receipt-override-mismatch'])
        line = '["%s"] = {kind = "text"},' % key
        self.assertEqual(MODEL['declarations'][key], {'kind': 'text'})
        upgraded = composed(localization=with_declarations(replace=[(line, '["%s"] = {kind = "block"},' % key)]))
        report = G.evaluate(upgraded, self.receipt(upgraded, overrides=[override]))
        self.assertEqual(report['compositionReceipt']['status'], 'CURRENT_INPUTS_MATCHED')
        self.assertEqual([c for c in codes(report) if c.startswith('receipt-')], [])
        self.assertIn('context-mismatch', codes(report))  # the context rows must follow too
        noop = {'key': key, 'kind': 'block', 'previousKind': 'block'}
        self.assertIn('receipt-override-noop', codes(G.evaluate(upgraded, self.receipt(upgraded, overrides=[noop]))))


class ArchiveBinding(unittest.TestCase):
    def archive(self, members):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as bundle:
            for name, data in members.items():
                bundle.writestr(name, data)
        return buffer.getvalue()

    def members(self, sources):
        return {'Nexus/' + G.INPUT_PATHS[name]: sources[name].replace(b'\r\n', b'\n') for name in G.RUNTIME_INPUTS}

    def test_archive_members_bind_under_the_recorded_contract(self):
        problems = []
        result = G.check_archive(self.archive(self.members(ACTUAL)), ACTUAL, problems)
        self.assertEqual((result['status'], problems), ('FOUR_MEMBER_SUBSET_MATCHED', []))
        self.assertEqual(result['contract'], G.ARCHIVE_CONTRACT)

    def test_mismatched_or_missing_archive_member_fails(self):
        members = self.members(ACTUAL)
        members['Nexus/data/LocalizationPacks.lua'] = self.members(composed())['Nexus/data/LocalizationPacks.lua']
        problems = []
        self.assertEqual(G.check_archive(self.archive(members), ACTUAL, problems)['status'], 'REFUSED')
        self.assertEqual([p['code'] for p in problems], ['archive-mismatch'])
        members = self.members(ACTUAL)
        del members['Nexus/core/Localization.lua']
        problems = []
        G.check_archive(self.archive(members), ACTUAL, problems)
        self.assertEqual([p['code'] for p in problems], ['archive-member-missing'])
        problems = []
        G.check_archive(b'not a zip', ACTUAL, problems)
        self.assertEqual([p['code'] for p in problems], ['archive-unreadable'])


class ReceiverControls(unittest.TestCase):
    """A probe passes only for a real receiver; orphan and wrong receivers fail for their reason."""

    def test_orphan_and_wrong_receiver_fail_and_a_real_consumer_passes(self):
        # Its four probes run in the shared controls gate run (controls_gate), through G.gate.
        report = controls_gate()
        results = {}
        for row in report['runtime']['probes']:
            if row['run'] == 'complete:frFR' and row['probe'] in ORPHAN_IDS:
                results[row['probe']] = row['result']
        self.assertEqual(results, {'control.real': 'PASS', 'control.orphan': 'receiver-not-localized',
                                   'control.wrong': 'receiver-wrong-key', 'control.error': 'receiver-error'})
        own = {row['result'] for row in report['runtime']['probes'] if row['probe'] in ORPHAN_IDS} - {'PASS'}
        self.assertEqual(sorted(own), ['receiver-error', 'receiver-not-localized', 'receiver-wrong-key'])
        self.assertLessEqual(set(own), set(codes(report)))

    def test_missing_runtime_fails_the_gate(self):
        problems, evidence = G.runtime_check(ROOT, MODEL, luajit=str(ROOT / 'no-such-luajit'))
        self.assertEqual([p['code'] for p in problems], ['runtime-failed'])
        self.assertEqual(evidence['status'], 'FAILED')


# Review fix 1 (RF1) and the retro item: the entry-review record contract, the limited receipt and
# archive results, the real multiline receiver and the discarded-localization regression.

HELP_PROBE = 'help.page_troubleshooting_body'
HELP_KEY = 'help.body.troubleshooting_commands_2'
HELP_SLOTS = "{policy_command = '/nexus policy adaptive|released'}"


def synthetic_full_gate():
    """The full-size synthetic composition through the whole gate, once per process."""
    if 'syntheticGate' not in FULL:
        sources, _ = full_composition()
        with tempfile.TemporaryDirectory(prefix='nexus-gate-test-') as scratch:
            FULL['syntheticGate'] = G.gate(ROOT, sources=sources, paths=synthetic_paths(scratch, sources))
    return FULL['syntheticGate']


# The original receiver controls: a real consumer, a comment/list-only orphan, another key's
# receiver and a raising probe.
ORPHAN_CONTROLS = (
    {'id': 'control.real', 'key': 'panel.label.more_count',
     'code': "return Nexus.Panel.DetailNameLines({'a', 'b', 'c', 'd'})[3]", 'slots': {'count': '2'}},
    {'id': 'control.orphan', 'key': 'panel.label.more_count',
     'code': "-- panel.label.more_count\nlocal unused = {'panel.label.more_count'}\nreturn '+2 more'",
     'slots': {'count': '2'}},
    {'id': 'control.wrong', 'key': 'panel.button.my_builds',
     'code': "return (Nexus.UserText.Message('ROOT_MUTATION_PENDING'))"},
    {'id': 'control.error', 'key': 'panel.button.my_builds', 'code': 'error("boom")'},
)
# The discarded-localization controls: the real producer or the Help page runs (the seam is
# called), its localized value is discarded, and English or another page is shown instead.
DISCARD_CONTROLS = (
    {'id': 'control.discarded_panel', 'key': 'panel.label.more_count', 'slots': {'count': '2'},
     'receiver': 'test-only: Panel.DetailNameLines result discarded',
     'code': "local localized = Nexus.Panel.DetailNameLines({'a', 'b', 'c', 'd'})[3]\n"
             "assert(type(localized) == 'string')\n"
             "return (Nexus.LocalizationEnglish['panel.label.more_count']:gsub('{count}', '2'))"},
    {'id': 'control.discarded_help', 'key': HELP_KEY, 'match': 'segment',
     'slots': {'policy_command': '/nexus policy adaptive|released'},
     'receiver': 'test-only: Help page body read, then the English template shown',
     'code': "local L = Nexus.Localization\n"
             "local f = Nexus.Help.Show('troubleshooting'); local localized = f.body:GetText(); f:Hide()\n"
             "assert(type(localized) == 'string')\n"
             "return 'Reference\\n' .. L.Format('%s', %s, {})" % (HELP_KEY, HELP_SLOTS)},
    {'id': 'control.wrong_help_page', 'key': HELP_KEY, 'match': 'segment',
     'slots': {'policy_command': '/nexus policy adaptive|released'},
     'receiver': 'test-only: another Help page',
     'code': "local f = Nexus.Help.Show('about'); local text = f.body:GetText(); f:Hide(); return text"},
)
ORPHAN_IDS = {probe['id'] for probe in ORPHAN_CONTROLS}
DISCARD_IDS = {probe['id'] for probe in DISCARD_CONTROLS}


def controls_gate():
    """The full synthetic composition through G.gate with the real receivers and both control sets:
    one run serves the orphan and the discarded-localization tests, which share these inputs."""
    if 'controlsGate' not in FULL:
        sources, _ = full_composition()
        with tempfile.TemporaryDirectory(prefix='nexus-gate-test-') as scratch:
            FULL['controlsGate'] = G.gate(ROOT, sources=sources, paths=synthetic_paths(scratch, sources),
                                          probes=G.RECEIVER_PROBES + ORPHAN_CONTROLS + DISCARD_CONTROLS)
    return FULL['controlsGate']


def declaration_mutant(change, key='leaderboard.column.rank', product='frFR'):
    """The reduced composition with one complete legitimately_identical record changed in place."""
    packs = synthetic_packs()
    release = json.loads(synthetic_release(packs))
    record = next(r for r in release['entryReview']['declarations']
                  if r['productId'] == product and r['key'] == key)
    change(record, release)
    return G.evaluate(dict(REDUCED, packs=packs_source(packs),
                           release=json.dumps(release, ensure_ascii=False).encode('utf-8')))


class EntryReviewContract(unittest.TestCase):
    """The existing complete entry-review record contract decides every exemption."""

    def product(self, report, product_id):
        return next(row for row in report['products'] if row['productId'] == product_id)

    def test_full_english_copy_with_incomplete_records_fails_the_same_gate(self):
        # The Spec counterexample: every entry of all six full packs is the English, and every
        # declaration lacks reviewer and evidenceReference.
        def mutate(packs):
            for _, entries in packs.values():
                entries.update(MODEL['active'])
        packs = synthetic_packs(MODEL)
        mutate(packs)
        release = json.loads(synthetic_release(packs, model=MODEL))
        records = release['entryReview']['declarations']
        self.assertEqual(len(records), 6 * len(MODEL['active']))
        for record in records:
            del record['reviewer'], record['evidenceReference']
        sources = dict(ACTUAL, packs=packs_source(packs),
                       release=json.dumps(release, ensure_ascii=False).encode('utf-8'))
        with tempfile.TemporaryDirectory(prefix='nexus-gate-test-') as scratch:
            report = G.gate(ROOT, sources=sources, paths=synthetic_paths(scratch, sources))
        self.assertEqual(report['verdict'], 'FAIL')
        self.assertEqual(codes(report), ['entry-english-placeholder', 'entry-review-invalid'])
        invalid = [p for p in report['problems'] if p['code'] == 'entry-review-invalid']
        self.assertEqual(len(invalid), len(records))
        self.assertEqual({p.get('detail') for p in invalid}, {'evidence-field'})
        for product in report['products']:
            self.assertEqual(product['counts']['english_placeholder'], len(MODEL['active']))
            self.assertEqual(product['counts']['legitimately_identical'], 0)
            self.assertFalse(product['complete'])

    def test_complete_coherent_records_classify_legitimately_identical_terms(self):
        report = G.evaluate(composed())
        self.assertEqual(report['problems'], [])
        for product in report['products']:
            self.assertIn('leaderboard.column.rank', product['categories']['legitimately_identical'])
            self.assertEqual(product['counts']['english_placeholder'], 0)
        self.assertEqual(report['entryReview']['status'], 'RECORDS_CHECKED')
        self.assertIn('not evidence', report['entryReview']['notEvidenceOf'])

    def test_malformed_records_grant_no_exemption(self):
        cases = {
            'missing reviewer and reference': (lambda r, _: (r.pop('reviewer'), r.pop('evidenceReference')),
                                               'evidence-field'),
            'blank reviewer': (lambda r, _: r.__setitem__('reviewer', ''), 'evidence-reviewer'),
            'UNASSIGNED reviewer': (lambda r, _: r.__setitem__('reviewer', 'UNASSIGNED'), 'evidence-reviewer'),
            'non-https reference': (lambda r, _: r.__setitem__('evidenceReference', 'http://example.invalid/x'),
                                    'evidence-reference'),
            'reviewer not a string': (lambda r, _: r.__setitem__('reviewer', 7), 'evidence-type'),
            'status not declared': (lambda r, _: r.__setitem__('status', 'accepted'), 'evidence-status'),
            'extra field': (lambda r, _: r.__setitem__('approved', 'yes'), 'evidence-field'),
            'unknown key': (lambda r, _: r.__setitem__('key', 'panel.never_declared'), 'evidence-unknown-key'),
            'decision unknown': (lambda r, _: r.__setitem__('decision', 'approved'), 'evidence-decision'),
        }
        for name, (change, detail) in cases.items():
            with self.subTest(name=name):
                report = declaration_mutant(change)
                rows = [p for p in report['problems'] if p['code'].startswith('entry-review-')]
                self.assertEqual([(p['code'], p.get('detail')) for p in rows], [('entry-review-invalid', detail)])
                self.assertEqual(self.product(report, 'frFR')['categories']['english_placeholder'],
                                 ['leaderboard.column.rank'])
                self.assertIn('entry-english-placeholder', codes(report))
                # The other products keep their own complete records.
                self.assertIn('leaderboard.column.rank',
                              self.product(report, 'deDE')['categories']['legitimately_identical'])

    def test_wrong_product_or_entry_and_container_contract_are_refused(self):
        report = declaration_mutant(lambda r, _: r.__setitem__('productId', 'qaQA'))
        self.assertEqual([p.get('detail') for p in report['problems'] if p['code'] == 'entry-review-invalid'],
                         ['evidence-unknown-product'])
        self.assertIn('leaderboard.column.rank', self.product(report, 'frFR')['categories']['english_placeholder'])
        # A record for a key whose entry is absent from its pack names no present entry.
        def absent(record, release):
            record['key'] = 'panel.button.my_builds'
        packs = synthetic_packs()
        del packs['frFR'][1]['panel.button.my_builds']
        release = json.loads(synthetic_release(packs))
        record = next(r for r in release['entryReview']['declarations']
                      if r['productId'] == 'frFR' and r['key'] == 'leaderboard.column.rank')
        absent(record, release)
        report = G.evaluate(dict(REDUCED, packs=packs_source(packs), release=json.dumps(release).encode('utf-8')))
        self.assertIn('evidence-no-entry',
                      [p.get('detail') for p in report['problems'] if p['code'] == 'entry-review-invalid'])
        for version in (2, '1', None):
            with self.subTest(contractVersion=version):
                report = declaration_mutant(lambda r, rel: rel['entryReview'].__setitem__('contractVersion', version))
                self.assertIn(('entry-review-invalid', 'evidence-contract'),
                              [(p['code'], p.get('detail')) for p in report['problems']])
                for product in report['products']:
                    self.assertEqual(product['counts']['legitimately_identical'], 0)
                self.assertEqual(report['entryReview']['status'], 'REFUSED')

    def test_original_declarations_container_must_be_a_list(self):
        # A complete composition whose entries all differ from English needs no declaration, so a
        # valid empty list passes; a missing or non-list original member is refused, never read.
        packs = synthetic_packs()
        for _, entries in packs.values():
            for key, value in entries.items():
                if value == REDUCED_MODEL['active'][key]:
                    entries[key] = 'Z' + value
        sources = dict(REDUCED, packs=packs_source(packs), release=synthetic_release(packs))
        self.assertEqual(json.loads(sources['release'])['entryReview']['declarations'], [])
        report = G.evaluate(sources)
        self.assertEqual(report['problems'], [])
        self.assertEqual((report['entryReview']['status'], report['entryReview']['records']), ('RECORDS_CHECKED', 0))
        for name, value in (('missing', None), ('null', None), ('object', {}), ('string', ''), ('integer', 7)):
            with self.subTest(declarations=name):
                document = json.loads(sources['release'])
                if name == 'missing':
                    del document['entryReview']['declarations']
                else:
                    document['entryReview']['declarations'] = value
                report = G.evaluate(dict(sources, release=json.dumps(document).encode('utf-8')))
                self.assertEqual([(p['code'], p.get('detail')) for p in report['problems']],
                                 [('entry-review-invalid', 'evidence-contract')])
                self.assertEqual((report['entryReview']['status'], report['entryReview']['accepted']), ('REFUSED', 0))

    def test_duplicate_records_are_refused(self):
        report = declaration_mutant(lambda r, rel: rel['entryReview']['declarations'].append(dict(r)))
        self.assertEqual([p['code'] for p in report['problems'] if p['code'].startswith('entry-review-')],
                         ['entry-review-duplicate'])
        self.assertIn('leaderboard.column.rank', self.product(report, 'frFR')['categories']['english_placeholder'])


class ReceiptLimits(unittest.TestCase):
    """A receipt binds only the current inputs and shape; prior versions and lineage stay unverified."""

    receipt = CompositionReceipt.receipt

    def test_a_matching_receipt_reports_current_agreement_only(self):
        sources = composed()
        report = G.evaluate(sources, self.receipt(sources), require_receipt=True)
        result = report['compositionReceipt']
        self.assertEqual(result['status'], 'CURRENT_INPUTS_MATCHED')
        self.assertEqual(result['priorVersionAndLineage'], 'NOT_VERIFIED')
        report.pop('model', None)
        line = next(line for line in G.summary_lines(dict(report, sourceIdentity={}, runtime={}, verdict='PASS',
                                                          notEvidenceOf='', archive={'status': 'NOT_SUPPLIED'}))
                    if line.startswith('receipt:'))
        self.assertIn('prior version and lineage NOT_VERIFIED', line)

    def test_malformed_prior_kind_and_repeated_key_are_refused(self):
        key = 'panel.button.my_builds'
        sources = composed()
        cases = {
            'unknown prior kind': ([{'key': key, 'kind': 'text', 'previousKind': 'NOT_A_KIND'}],
                                   'receipt-override-malformed'),
            'prior kind not a string': ([{'key': key, 'kind': 'text', 'previousKind': 3}],
                                        'receipt-override-malformed'),
            'repeated key': ([{'key': key, 'kind': 'text', 'previousKind': 'block'}] * 2,
                             'receipt-override-duplicate'),
            'lines not exactly true': ([{'key': key, 'kind': 'text', 'previousKind': 'block', 'lines': False}],
                                       'receipt-override-malformed'),
            'wrong current limit': ([{'key': 'panel.label.more_count', 'kind': 'template', 'previousKind': 'text',
                                      'resultLimit': 121}], 'receipt-override-mismatch'),
            'wrong current lines': ([{'key': 'panel.label.more_count', 'kind': 'template', 'previousKind': 'text',
                                      'lines': True}], 'receipt-override-mismatch'),
        }
        for name, (overrides, code) in cases.items():
            with self.subTest(name=name):
                report = G.evaluate(sources, self.receipt(sources, overrides=overrides), require_receipt=True)
                self.assertIn(code, codes(report))
                self.assertEqual(report['compositionReceipt']['status'], 'REFUSED')


class ArchiveSubset(unittest.TestCase):
    def test_archive_result_names_the_four_member_subset_only(self):
        members = ArchiveBinding.members(None, ACTUAL)
        self.assertEqual(len(members), 4)
        problems = []
        # No TOC, Release, notices or UI file: the subset still agrees, and says it is only that.
        result = G.check_archive(ArchiveBinding.archive(None, members), ACTUAL, problems)
        self.assertEqual((result['status'], problems), ('FOUR_MEMBER_SUBSET_MATCHED', []))
        self.assertIn('not the whole archive', result['scope'])
        line = next(line for line in G.summary_lines({
            'inputs': [], 'problems': [], 'verdict': 'PASS', 'notEvidenceOf': '', 'compositionReceipt':
            {'status': 'NOT_SUPPLIED'}, 'archive': result}) if line.startswith('receipt:'))
        self.assertIn('four localization runtime-input members only', line)


class RealReceivers(unittest.TestCase):
    """The listed real display receivers, including one multiline (lines = true) template."""

    def test_help_reference_page_is_a_real_lines_template_receiver_in_every_condition(self):
        probe = next(p for p in G.RECEIVER_PROBES if p['id'] == HELP_PROBE)
        self.assertEqual(probe['key'], HELP_KEY)
        self.assertEqual(probe['match'], 'segment')
        self.assertIs(MODEL['declarations'][HELP_KEY].get('lines'), True)
        self.assertEqual(MODEL['declarations'][HELP_KEY]['slots'], ('text',))
        self.assertIn('\n', MODEL['active'][HELP_KEY])
        report = synthetic_full_gate()
        self.assertEqual(report['problems'], [])
        rows = [r for r in report['runtime']['probes'] if r['probe'] == HELP_PROBE]
        self.assertEqual(sorted(r['run'] for r in rows),
                         sorted('%s:%s' % (c, p) for c in ('complete', 'missing', 'invalid')
                                for p in MODEL['optionalIds']))
        for row in rows:
            self.assertEqual(row['result'], 'PASS', row)
            self.assertEqual(row['source'], 'candidate' if row['run'].startswith('complete:') else 'base', row)
        self.assertEqual(len(G.RECEIVER_PROBES), 8)
        self.assertTrue(all(p.get('receiver') for p in G.RECEIVER_PROBES))

    def test_report_separates_catalog_seam_and_display_receiver_coverage(self):
        coverage = synthetic_full_gate()['coverage']
        self.assertEqual(coverage['catalog']['activeKeys'], len(MODEL['active']))
        self.assertEqual(coverage['seam']['keysPerRun'], len(MODEL['active']))
        receivers = coverage['displayReceivers']
        self.assertEqual([r['id'] for r in receivers['probes']], [p['id'] for p in G.RECEIVER_PROBES])
        self.assertIn('not', receivers['scope'])
        for row in receivers['probes']:
            self.assertEqual(sorted(row['outcomes']), ['complete', 'invalid', 'missing'])

    def test_discarded_localization_result_fails_the_same_required_gate(self):
        # Valid complete composition; each control calls the real seam or the real producer, discards
        # the localized value and shows the old English (or another page). The real receivers pass.
        report = controls_gate()
        self.assertEqual(report['verdict'], 'FAIL')
        # Only display receivers fail: no static coverage, seam, load or setup problem.
        self.assertEqual(codes(report), ['receiver-error', 'receiver-mismatch', 'receiver-not-localized',
                                         'receiver-wrong-key'])
        for product in report['products']:
            self.assertTrue(product['complete'])
        results = {}
        for row in report['runtime']['probes']:
            results.setdefault(row['probe'], {})[row['run']] = row['result']
        for probe in G.RECEIVER_PROBES:
            self.assertEqual(set(results[probe['id']].values()), {'PASS'}, probe['id'])
        own = {results[i][run] for i in DISCARD_IDS for run in results[i]} - {'PASS'}
        self.assertEqual(sorted(own), ['receiver-mismatch', 'receiver-not-localized'])
        for product in MODEL['optionalIds']:
            self.assertEqual(results['control.discarded_panel']['complete:' + product], 'receiver-not-localized')
            self.assertEqual(results['control.discarded_help']['complete:' + product], 'receiver-not-localized')
            self.assertEqual(results['control.wrong_help_page']['complete:' + product], 'receiver-mismatch')
            # With English expected (missing or invalid entry) the discarded value cannot be told apart.
            for condition in ('missing', 'invalid'):
                self.assertEqual(results['control.discarded_panel']['%s:%s' % (condition, product)], 'PASS')
                self.assertEqual(results['control.discarded_help']['%s:%s' % (condition, product)], 'PASS')


if __name__ == '__main__':
    unittest.main()
