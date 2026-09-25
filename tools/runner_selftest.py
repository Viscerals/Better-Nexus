#!/usr/bin/env python3
"""Fail-capable self-test of the per-test process timeouts in tools/run_prototype_tests.py
and of the timing lines that tools/ci_check.py prints from the runner's report.

    python tools/runner_selftest.py

It imports the runner and calls its main() with subprocess.run, shutil.which and the clock
replaced by controlled stand-ins. No Lua runtime is started and nothing waits for a timeout:
a timeout is a raised subprocess.TimeoutExpired, and elapsed time is a fake clock that each
stand-in process advances. It calls tools/ci_check.py's main() with the runner replaced by a
stand-in that writes a controlled report. Each case prints one "ok" line; any wrong result
prints WRONG and the exit status is 1.
"""
from __future__ import annotations
import contextlib, importlib.util, io, json, pathlib, subprocess, sys, tempfile, types

ROOT = pathlib.Path(__file__).resolve().parents[1]
LONG = {'catalog_root_capacity': 120, 'sync_admission_traffic_acceptance': 120}
NOT_RUN_ROW_KEYS = {'test', 'status', 'reason'}


def load_runner():
    """A fresh copy of the runner module for each case, so no stand-in leaks into the next."""
    spec = importlib.util.spec_from_file_location('run_prototype_tests', ROOT / 'tools' / 'run_prototype_tests.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeProcesses:
    """Stands in for subprocess.run and time.monotonic.

    outcomes maps a test name to an exit code or 'timeout' (default exit 0).
    elapsed maps a test name to the seconds its process takes (default 0.5).
    All values are exact binary fractions, so the runner's elapsed time is exact."""

    def __init__(self, outcomes=None, elapsed=None):
        self.outcomes = outcomes or {}
        self.elapsed = elapsed or {}
        self.now = 1000.0
        self.calls = []   # (test name, timeout keyword passed to subprocess.run)

    def monotonic(self) -> float:
        return self.now

    def run(self, command, **kwargs):
        name = pathlib.PurePosixPath(command[-1]).stem
        self.calls.append((name, kwargs.get('timeout')))
        self.now += self.elapsed.get(name, 0.5)
        outcome = self.outcomes.get(name, 0)
        if outcome == 'timeout':
            raise subprocess.TimeoutExpired(command, kwargs.get('timeout'), output='partial out', stderr='partial err')
        return subprocess.CompletedProcess(command, outcome, stdout=f'{name} out', stderr='')


def run_main(runner, fake: FakeProcesses, reference: pathlib.Path, *args: str):
    """Call runner.main() with the stand-ins; return (exit status, report or None, stderr)."""
    runner.subprocess = types.SimpleNamespace(run=fake.run, TimeoutExpired=subprocess.TimeoutExpired)
    runner.shutil = types.SimpleNamespace(which=lambda exe: '/stand-in/luajit' if exe == 'luajit' else None)
    runner.time = types.SimpleNamespace(monotonic=fake.monotonic)
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp) / 'report.json'
        saved_argv = sys.argv
        sys.argv = ['run_prototype_tests.py', '--runtime', 'luajit', '--output', str(out),
                    '--reference', str(reference), *args]
        err = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
                try:
                    code = runner.main()
                except SystemExit as exc:
                    code = exc.code
        finally:
            sys.argv = saved_argv
        report = json.loads(out.read_text(encoding='utf-8')) if out.is_file() else None
    return code, report, err.getvalue()


def rows(report) -> dict:
    return {r['test']: r for r in report['results']} if report else {}


def counts(report):
    """(passed, failed, not_run) from the report, or None when no report was written."""
    return (report['passed'], report['failed'], report['not_run']) if report else None


def controlled_report(names, overrides: dict) -> dict:
    """A runner report written without a runner: each test PASS in 0.25 s at its configured limit,
    the two reference-dependent tests NOT_RUN, then per-test overrides (None removes the key)."""
    runner = load_runner()
    results = []
    for n in names:
        if n in ('planner_reference', 'orbs_policy'):
            results.append({'test': n, 'status': 'NOT_RUN', 'reason': 'Supplied LoadoutPilot reference not available'})
            continue
        row = {'test': n, 'status': 'PASS', 'exit': 0, 'seconds': 0.25, 'timeout_seconds': runner.timeout_for(n),
               'stdout': '', 'stderr': ''}
        row.update(overrides.get(n, {}))
        results.append({k: v for k, v in row.items() if v is not None})
    return {'schema': 'nexus-prototype-tests/1', 'runtime': 'LuaJIT', 'results': results}


def run_ci_check(report: dict, *args: str):
    """Call tools/ci_check.py main() with its runner replaced by one that writes `report`.
    Return (exit status, stdout lines); an exception is returned as the exit status."""
    spec = importlib.util.spec_from_file_location('ci_check', ROOT / 'tools' / 'ci_check.py')
    ci = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ci)

    def write_report(command, **kwargs):
        pathlib.Path(command[command.index('--output') + 1]).write_text(json.dumps(report), encoding='utf-8')
        return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
    ci.subprocess = types.SimpleNamespace(run=write_report)
    out = io.StringIO()
    with tempfile.TemporaryDirectory() as tmp:
        saved_argv = sys.argv
        sys.argv = ['ci_check.py', '--output', str(pathlib.Path(tmp) / 'report.json'), *args]
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = ci.main()
        except Exception as exc:
            code = f'raised {exc!r}'
        finally:
            sys.argv = saved_argv
    return code, out.getvalue().splitlines()


def main() -> int:
    failures: list[str] = []

    def expect(name: str, good: bool, detail: str = '') -> None:
        print(('ok   ' if good else 'WRONG') + f' {name}' + ('' if good else f': {detail}'))
        if not good:
            failures.append(name)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        empty = tmp / 'no-reference'
        full = tmp / 'reference'
        planner_only = tmp / 'planner-only'
        empty.mkdir()
        for base, files in ((full, ('Engine/WishlistPlanner.lua', 'Memory/MemoryMode.lua')),
                            (planner_only, ('Engine/WishlistPlanner.lua',))):
            for f in files:
                (base / f).parent.mkdir(parents=True, exist_ok=True)
                (base / f).write_text('-- stand-in\n', encoding='utf-8')

        # 1. The declared values.
        runner = load_runner()
        expect('the default per-test timeout is 45 s',
               getattr(runner, 'DEFAULT_TIMEOUT_SECONDS', None) == 45,
               f'DEFAULT_TIMEOUT_SECONDS={getattr(runner, "DEFAULT_TIMEOUT_SECONDS", None)!r}')
        expect('the timeout map is exactly catalog_root_capacity=120 and sync_admission_traffic_acceptance=120',
               getattr(runner, 'TEST_TIMEOUT_SECONDS', None) == LONG,
               f'TEST_TIMEOUT_SECONDS={getattr(runner, "TEST_TIMEOUT_SECONDS", None)!r}')

        # 2. The complete inventory, every process exits 0, reference present.
        runner = load_runner()
        fake = FakeProcesses()
        code, report, err = run_main(runner, fake, full)
        passed = dict(fake.calls)
        names = list(runner.NAMES)
        expect('every listed test is started exactly once',
               [n for n, _ in fake.calls] == names, f'{len(fake.calls)} calls for {len(names)} tests')
        ordinary = [n for n in names if n not in LONG]
        expect(f'an ordinary test gets 45 s ({len(ordinary)} tests, e.g. parse={passed.get("parse")})',
               all(passed.get(n) == 45 for n in ordinary),
               'not 45: ' + ', '.join(f'{n}={passed.get(n)}' for n in ordinary if passed.get(n) != 45))
        raised = {n: t for n, t in fake.calls if t != 45}
        expect('exactly catalog_root_capacity and sync_admission_traffic_acceptance get 120 s, nothing else',
               raised == LONG, f'tests not at 45 s: {raised}')
        r = rows(report)
        expect('each row records the timeout passed to subprocess.run as timeout_seconds',
               bool(r) and all(r.get(n, {}).get('timeout_seconds') == t for n, t in fake.calls),
               'mismatch: ' + ', '.join(n for n, t in fake.calls if r.get(n, {}).get('timeout_seconds') != t)[:300])
        expect('each row records the measured elapsed time as seconds',
               bool(r) and all(r[n].get('seconds') == 0.5 for n in r),
               'seconds values: ' + str(sorted({str(r[n].get('seconds')) for n in r})))
        expect(f'all pass: PASS rows, counts passed={len(names)} failed=0 not_run=0, exit 0',
               code == 0 and report is not None and all(x['status'] == 'PASS' and x['exit'] == 0 for x in r.values())
               and counts(report) == (len(names), 0, 0),
               f'exit {code}, counts {counts(report)}, {err.strip()}')

        # 3. A nonzero exit is FAIL, for an ordinary and a long test.
        runner = load_runner()
        fake = FakeProcesses(outcomes={'parse': 1, 'catalog_root_capacity': 3})
        code, report, err = run_main(runner, fake, full, '--only', 'parse,catalog_root_capacity,sync_admission_traffic_acceptance')
        r = rows(report)
        got = {n: (x['status'], x.get('exit'), x.get('timeout_seconds')) for n, x in r.items()}
        want = {'parse': ('FAIL', 1, 45), 'catalog_root_capacity': ('FAIL', 3, 120),
                'sync_admission_traffic_acceptance': ('PASS', 0, 120)}
        expect('a nonzero exit is FAIL with its exit code and configured timeout',
               got == want, f'{got}')
        expect('FAIL is counted as failed (passed=1 failed=2 not_run=0) and the exit status is 1',
               code == 1 and counts(report) == (1, 2, 0),
               f'exit {code}, counts {counts(report)}, {err.strip()}')

        # 4. TimeoutExpired is TIMEOUT; configured timeout and elapsed time are separate fields.
        runner = load_runner()
        fake = FakeProcesses(outcomes={'catalog_root_capacity': 'timeout'}, elapsed={'catalog_root_capacity': 121.25})
        code, report, err = run_main(runner, fake, full, '--only', 'parse,catalog_root_capacity')
        row = rows(report).get('catalog_root_capacity', {})
        expect('a long test that times out is TIMEOUT with timeout_seconds=120 and seconds=121.25 (measured)',
               fake.calls == [('parse', 45), ('catalog_root_capacity', 120)]
               and row.get('status') == 'TIMEOUT' and row.get('timeout_seconds') == 120 and row.get('seconds') == 121.25
               and 'exit' not in row and row.get('stdout') == 'partial out' and row.get('stderr') == 'partial err',
               f'calls {fake.calls}, row {row}')
        expect('TIMEOUT is counted as failed (passed=1 failed=1 not_run=0) and the exit status is 1',
               code == 1 and counts(report) == (1, 1, 0),
               f'exit {code}, counts {counts(report)}, {err.strip()}')
        runner = load_runner()
        fake = FakeProcesses(outcomes={'parse': 'timeout'}, elapsed={'parse': 45.75})
        code, report, err = run_main(runner, fake, full, '--only', 'parse')
        row = rows(report).get('parse', {})
        expect('an ordinary test that times out is TIMEOUT with timeout_seconds=45 and seconds=45.75 (measured), exit 1',
               fake.calls == [('parse', 45)] and row.get('status') == 'TIMEOUT' and row.get('timeout_seconds') == 45
               and row.get('seconds') == 45.75 and code == 1 and counts(report) == (0, 1, 0),
               f'calls {fake.calls}, row {row}, exit {code}')

        # 5. Reference-dependent tests: NOT_RUN without the reference file, unchanged rows and counts.
        shard = 'planner_reference,orbs_policy,parse'
        runner = load_runner()
        fake = FakeProcesses()
        code, report, err = run_main(runner, fake, empty, '--only', shard)
        r = rows(report)
        expect('without the reference: planner_reference and orbs_policy are NOT_RUN, not started, rows unchanged, exit 1',
               [n for n, _ in fake.calls] == ['parse']
               and all(set(r.get(n, {})) == NOT_RUN_ROW_KEYS and r[n]['status'] == 'NOT_RUN'
                       and r[n]['reason'] == 'Supplied LoadoutPilot reference not available'
                       for n in ('planner_reference', 'orbs_policy'))
               and counts(report) == (1, 0, 2) and code == 1,
               f'calls {fake.calls}, rows {r}, exit {code}')
        runner = load_runner()
        fake = FakeProcesses()
        code, report, err = run_main(runner, fake, planner_only, '--only', shard)
        r = rows(report)
        expect('with only Engine/WishlistPlanner.lua: planner_reference runs at 45 s, orbs_policy is NOT_RUN, exit 1',
               fake.calls == [('planner_reference', 45), ('parse', 45)]
               and r.get('planner_reference', {}).get('status') == 'PASS' and r.get('orbs_policy', {}).get('status') == 'NOT_RUN'
               and counts(report) == (2, 0, 1) and code == 1,
               f'calls {fake.calls}, exit {code}')
        runner = load_runner()
        fake = FakeProcesses()
        code, report, err = run_main(runner, fake, full, '--only', shard)
        expect('with the reference: planner_reference and orbs_policy run at 45 s and pass, exit 0',
               fake.calls == [('planner_reference', 45), ('orbs_policy', 45), ('parse', 45)]
               and counts(report) == (3, 0, 0) and code == 0,
               f'calls {fake.calls}, exit {code}')

        # 6. A timeout-map name that is not a listed test is refused before anything runs.
        runner = load_runner()
        runner.TEST_TIMEOUT_SECONDS = dict(getattr(runner, 'TEST_TIMEOUT_SECONDS', {}), catalog_root_capacty=120)
        fake = FakeProcesses()
        code, report, err = run_main(runner, fake, full, '--only', 'parse')
        expect('a timeout-map name that is not in NAMES is refused: nonzero exit, nothing started, no report',
               code not in (0, None) and fake.calls == [] and report is None and 'catalog_root_capacty' in err,
               f'exit {code}, calls {fake.calls}, report written {report is not None}, stderr {err.strip()!r}')

    # 7. tools/ci_check.py timing lines, complete inventory, all pass. startup_budget has no
    # timeout_seconds; transport is the sixth slowest and must not be printed.
    names = list(load_runner().NAMES)
    code, out = run_ci_check(controlled_report(names, {
        'catalog_root_capacity': {'seconds': 71.25}, 'sync_admission_traffic_acceptance': {'seconds': 88.5},
        'startup_budget': {'seconds': 40.75, 'timeout_seconds': None}, 'boot': {'seconds': 30.5},
        'orbs': {'seconds': 20.25}, 'transport': {'seconds': 3.0}}))
    unchanged = [f'inventory: {len(names)} listed tests',
                 'runtime: LuaJIT',
                 f'passed {len(names) - 2}, failed 0, NOT RUN 2, no result row 0, listed {len(names)}',
                 'NOT RUN (not a pass): planner_reference: Supplied LoadoutPilot reference not available',
                 'NOT RUN (not a pass): orbs_policy: Supplied LoadoutPilot reference not available',
                 'RESULT: no listed test failed; 2 reference-dependent test(s) NOT RUN']
    timing = ['timing: catalog_root_capacity PASS 71.25 s (limit 120 s)',
              'timing: sync_admission_traffic_acceptance PASS 88.5 s (limit 120 s)',
              'timing: startup_budget PASS 40.75 s (limit unknown s)',
              'timing: boot PASS 30.5 s (limit 45 s)',
              'timing: orbs PASS 20.25 s (limit 45 s)']
    expect('ci_check prints the raised limits, then the five slowest, each test once, just before RESULT',
           out == unchanged[:-1] + timing + unchanged[-1:], ' | '.join(out[-12:]))
    expect('ci_check output without the timing lines is unchanged, exit 0',
           [line for line in out if not line.startswith('timing: ')] == unchanged and code == 0, f'exit {code}')

    # 8. The same with a FAIL, a TIMEOUT, a missing seconds and a shard.
    shard = ['parse', 'boot', 'catalog_root_capacity', 'sync_admission_traffic_acceptance', 'orbs_policy']
    code, out = run_ci_check(controlled_report(shard, {
        'parse': {'status': 'FAIL', 'exit': 1, 'seconds': 2.5, 'stdout': 'parse out', 'stderr': 'parse err'},
        'catalog_root_capacity': {'status': 'TIMEOUT', 'exit': None, 'seconds': 120.5, 'stdout': 'partial'},
        'sync_admission_traffic_acceptance': {'seconds': None}}), '--only', ','.join(shard))
    unchanged = [f'inventory: {len(names)} listed tests',
                 '--- parse: FAIL', 'parse out', 'parse err',
                 '--- catalog_root_capacity: TIMEOUT', 'partial', '',
                 'runtime: LuaJIT',
                 'passed 2, failed 2, NOT RUN 1, no result row 0, listed 5',
                 'NOT RUN (not a pass): orbs_policy: Supplied LoadoutPilot reference not available',
                 'PARTIAL: a shard was selected; this is not a complete run',
                 'RESULT: FAILED']
    timing = ['timing: catalog_root_capacity TIMEOUT 120.5 s (limit 120 s)',
              'timing: sync_admission_traffic_acceptance PASS unknown s (limit 120 s)',
              'timing: parse FAIL 2.5 s (limit 45 s)',
              'timing: boot PASS 0.25 s (limit 45 s)']
    expect('ci_check timing lines show TIMEOUT and FAIL rows and print a missing seconds as unknown',
           out == unchanged[:-1] + timing + unchanged[-1:], ' | '.join(out[-12:]))
    expect('ci_check output without the timing lines is unchanged: failure printing, counts, RESULT: FAILED, exit 1',
           [line for line in out if not line.startswith('timing: ')] == unchanged and code == 1, f'exit {code}')

    if failures:
        print('RESULT: FAILED:', '; '.join(failures))
        return 1
    print('RESULT: per-test timeouts, result rows, counts, exit status and ci_check timing lines behave as declared;'
          ' no Lua runtime was started')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
