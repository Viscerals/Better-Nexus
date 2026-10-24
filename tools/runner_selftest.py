#!/usr/bin/env python3
"""Fail-capable self-test of the per-test process timeouts in tools/run_prototype_tests.py,
of the timing lines that tools/ci_check.py prints from the runner's report, and of the
registered Python tests that tools/ci_check.py checks and runs.

    python tools/runner_selftest.py

It imports the runner and calls its main() with subprocess.run, shutil.which and the clock
replaced by controlled stand-ins. No Lua runtime is started and nothing waits for a timeout:
a timeout is a raised subprocess.TimeoutExpired, and elapsed time is a fake clock that each
stand-in process advances. It calls tools/ci_check.py's main() with every process replaced
by a stand-in: the runner writes a controlled report, and a registered Python test exits
with a chosen code, times out or fails to start. No Python test file is run. Each case
prints one "ok" line; any wrong result prints WRONG and the exit status is 1.
"""
from __future__ import annotations
import contextlib, importlib.util, io, json, pathlib, subprocess, sys, tempfile, types

ROOT = pathlib.Path(__file__).resolve().parents[1]
LONG = {'catalog_root_capacity': 120, 'sync_admission_traffic_acceptance': 120}
# The one registered Python test, and the scope wording of tools/ci_check.py's Python lines.
PY = 'tools/tests/test_l10n_inventory.py'
PY_SCOPE = '(separate processes; not counted with the listed Lua tests)'


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
        self.commands = []   # every command passed to subprocess.run

    def monotonic(self) -> float:
        return self.now

    def run(self, command, **kwargs):
        name = pathlib.PurePosixPath(command[-1]).stem
        self.calls.append((name, kwargs.get('timeout')))
        self.commands.append(list(command))
        self.now += self.elapsed.get(name, 0.5)
        outcome = self.outcomes.get(name, 0)
        if outcome == 'timeout':
            raise subprocess.TimeoutExpired(command, kwargs.get('timeout'), output='partial out', stderr='partial err')
        return subprocess.CompletedProcess(command, outcome, stdout=f'{name} out', stderr='')


def run_main(runner, fake: FakeProcesses, *args: str):
    """Call runner.main() with the stand-ins; return (exit status, report or None, stderr)."""
    runner.subprocess = types.SimpleNamespace(run=fake.run, TimeoutExpired=subprocess.TimeoutExpired)
    runner.shutil = types.SimpleNamespace(which=lambda exe: '/stand-in/luajit' if exe == 'luajit' else None)
    runner.time = types.SimpleNamespace(monotonic=fake.monotonic)
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp) / 'report.json'
        saved_argv = sys.argv
        sys.argv = ['run_prototype_tests.py', '--runtime', 'luajit', '--output', str(out), *args]
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
    then per-test overrides (None removes the key; a NOT_RUN override replaces the whole row)."""
    runner = load_runner()
    results = []
    for n in names:
        if overrides.get(n, {}).get('status') == 'NOT_RUN':
            results.append({'test': n, 'status': 'NOT_RUN', 'reason': overrides[n].get('reason', 'stand-in')})
            continue
        row = {'test': n, 'status': 'PASS', 'exit': 0, 'seconds': 0.25, 'timeout_seconds': runner.timeout_for(n),
               'stdout': '', 'stderr': ''}
        row.update(overrides.get(n, {}))
        results.append({k: v for k, v in row.items() if v is not None})
    return {'schema': 'nexus-prototype-tests/1', 'runtime': 'LuaJIT', 'results': results}


def load_ci_check():
    """A fresh copy of tools/ci_check.py, so no stand-in leaks into the next case."""
    spec = importlib.util.spec_from_file_location('ci_check', ROOT / 'tools' / 'ci_check.py')
    ci = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ci)
    return ci


def python_test_name(argument, root) -> str:
    """The repository-relative POSIX path of a Python test process's script argument."""
    try:
        return pathlib.Path(argument).relative_to(root).as_posix()
    except ValueError:
        return str(argument)


def ci_check_call(report: dict, *args: str, python=None, prepare=None):
    """Call tools/ci_check.py main() with every process replaced by a stand-in.

    The runner process writes `report`. Any other process is a registered Python test: python
    maps its path to an exit code, 'timeout' (TimeoutExpired with partial bytes output, after
    45.25 s) or 'launch' (FileNotFoundError); the default is exit 0 after 0.5 s. The clock is
    fake and starts at 2000.0. prepare(ci) may change the module before main() runs.
    Returns code (an exception is returned as the exit status), out (stdout lines), calls
    ((command, keywords) of every process started, in order) and report (the --output file
    afterwards, or None)."""
    ci = load_ci_check()
    outcomes = python or {}
    calls = []
    clock = [2000.0]

    def fake_run(command, **kwargs):
        calls.append((list(command), kwargs))
        if any(str(part).endswith('run_prototype_tests.py') for part in command):
            pathlib.Path(command[command.index('--output') + 1]).write_text(json.dumps(report), encoding='utf-8')
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
        name = python_test_name(command[-1], ci.ROOT)
        outcome = outcomes.get(name, 0)
        if outcome == 'timeout':
            clock[0] += 45.25
            raise subprocess.TimeoutExpired(command, kwargs.get('timeout'), output=b'py partial out',
                                            stderr=b'py partial err')
        clock[0] += 0.5
        if outcome == 'launch':
            raise FileNotFoundError(2, 'stand-in launch failure')
        return subprocess.CompletedProcess(command, outcome, stdout=f'{name} out', stderr=f'{name} err')
    ci.subprocess = types.SimpleNamespace(run=fake_run, TimeoutExpired=subprocess.TimeoutExpired)
    ci.time = types.SimpleNamespace(monotonic=lambda: clock[0])
    out = io.StringIO()
    written = None
    with tempfile.TemporaryDirectory() as tmp:
        output = pathlib.Path(tmp) / 'report.json'
        saved_argv = sys.argv
        sys.argv = ['ci_check.py', '--output', str(output), *args]
        try:
            if prepare:
                prepare(ci)
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                code = ci.main()
        except Exception as exc:
            code = f'raised {exc!r}'
        finally:
            sys.argv = saved_argv
        if output.is_file():
            try:
                written = json.loads(output.read_text(encoding='utf-8'))
            except ValueError:
                written = None
    return types.SimpleNamespace(code=code, out=out.getvalue().splitlines(), calls=calls, report=written)


def run_ci_check(report: dict, *args: str):
    """Call tools/ci_check.py main() with its runner replaced by one that writes `report` and every
    registered Python test exiting 0. Return (exit status, stdout lines); an exception is returned
    as the exit status."""
    result = ci_check_call(report, *args)
    return result.code, result.out


def python_row(report) -> dict:
    """The first Python test row that tools/ci_check.py added to its report, or {}."""
    results = ((report or {}).get('python_tests') or {}).get('results') or [{}]
    return results[0] if isinstance(results[0], dict) else {}


def with_runner(python_tests=None, root=None):
    """A prepare(ci) for ci_check_call: a fresh runner, optionally with other PYTHON_TESTS, and
    optionally another repository root for the Python inventory."""
    def prepare(ci):
        runner = load_runner()
        if python_tests is not None:
            runner.PYTHON_TESTS = list(python_tests)
        ci.runner_module = lambda: runner
        if root is not None:
            ci.ROOT = root
    return prepare


def main() -> int:
    failures: list[str] = []

    def expect(name: str, good: bool, detail: str = '') -> None:
        print(('ok   ' if good else 'WRONG') + f' {name}' + ('' if good else f': {detail}'))
        if not good:
            failures.append(name)

    # 1. The declared values.
    runner = load_runner()
    expect('the default per-test timeout is 45 s',
           getattr(runner, 'DEFAULT_TIMEOUT_SECONDS', None) == 45,
           f'DEFAULT_TIMEOUT_SECONDS={getattr(runner, "DEFAULT_TIMEOUT_SECONDS", None)!r}')
    expect('the timeout map is exactly catalog_root_capacity=120 and sync_admission_traffic_acceptance=120',
           getattr(runner, 'TEST_TIMEOUT_SECONDS', None) == LONG,
           f'TEST_TIMEOUT_SECONDS={getattr(runner, "TEST_TIMEOUT_SECONDS", None)!r}')

    # 2. The complete inventory, every process exits 0.
    runner = load_runner()
    fake = FakeProcesses()
    code, report, err = run_main(runner, fake)
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
    code, report, err = run_main(runner, fake, '--only', 'parse,catalog_root_capacity,sync_admission_traffic_acceptance')
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
    code, report, err = run_main(runner, fake, '--only', 'parse,catalog_root_capacity')
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
    code, report, err = run_main(runner, fake, '--only', 'parse')
    row = rows(report).get('parse', {})
    expect('an ordinary test that times out is TIMEOUT with timeout_seconds=45 and seconds=45.75 (measured), exit 1',
           fake.calls == [('parse', 45)] and row.get('status') == 'TIMEOUT' and row.get('timeout_seconds') == 45
           and row.get('seconds') == 45.75 and code == 1 and counts(report) == (0, 1, 0),
           f'calls {fake.calls}, row {row}, exit {code}')

    # 5. No listed test needs a separate archive: the retired reference option is refused
    # before anything runs, and the two engine tests run like every other test.
    runner = load_runner()
    fake = FakeProcesses()
    code, report, err = run_main(runner, fake, '--reference', 'anywhere', '--only', 'parse')
    expect('the retired --reference option is refused: nonzero exit, nothing started, no report',
           code not in (0, None) and fake.calls == [] and report is None,
           f'exit {code}, calls {fake.calls}, report written {report is not None}')
    runner = load_runner()
    fake = FakeProcesses()
    code, report, err = run_main(runner, fake, '--only', 'echoweaver_planner,echoweaver_orb_policy,parse')
    expect('the engine tests run at 45 s like every other test and no row is NOT_RUN, exit 0',
           fake.calls == [('echoweaver_planner', 45), ('echoweaver_orb_policy', 45), ('parse', 45)]
           and counts(report) == (3, 0, 0) and code == 0,
           f'calls {fake.calls}, counts {counts(report)}, exit {code}')

    # 6. A timeout-map name that is not a listed test is refused before anything runs.
    runner = load_runner()
    runner.TEST_TIMEOUT_SECONDS = dict(getattr(runner, 'TEST_TIMEOUT_SECONDS', {}), catalog_root_capacty=120)
    fake = FakeProcesses()
    code, report, err = run_main(runner, fake, '--only', 'parse')
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
                 f'python inventory: 1 registered Python test files {PY_SCOPE}',
                 'runtime: LuaJIT',
                 f'passed {len(names)}, failed 0, NOT RUN 0, no result row 0, listed {len(names)}',
                 'RESULT: no listed test failed; every listed test ran']
    timing = ['timing: catalog_root_capacity PASS 71.25 s (limit 120 s)',
              'timing: sync_admission_traffic_acceptance PASS 88.5 s (limit 120 s)',
              'timing: startup_budget PASS 40.75 s (limit unknown s)',
              'timing: boot PASS 30.5 s (limit 45 s)',
              'timing: orbs PASS 20.25 s (limit 45 s)']
    python = [f'python: {PY} PASS 0.5 s (limit 45 s)',
              f'python: passed 1, failed 0, registered 1 {PY_SCOPE}']
    expect('ci_check prints the raised limits, then the five slowest, each test once, then the Python test lines,'
           ' just before RESULT',
           out == unchanged[:-1] + timing + python + unchanged[-1:], ' | '.join(out[-12:]))
    expect('ci_check output without the timing and Python run lines is the Lua output plus the Python inventory'
           ' line, exit 0',
           [line for line in out if not line.startswith(('timing: ', 'python: '))] == unchanged and code == 0,
           f'exit {code}')

    # 8. The same with a FAIL, a TIMEOUT, a missing seconds, a NOT_RUN row and a shard.
    shard = ['parse', 'boot', 'catalog_root_capacity', 'sync_admission_traffic_acceptance', 'orbs']
    code, out = run_ci_check(controlled_report(shard, {
        'orbs': {'status': 'NOT_RUN', 'reason': 'stand-in skip'},
        'parse': {'status': 'FAIL', 'exit': 1, 'seconds': 2.5, 'stdout': 'parse out', 'stderr': 'parse err'},
        'catalog_root_capacity': {'status': 'TIMEOUT', 'exit': None, 'seconds': 120.5, 'stdout': 'partial'},
        'sync_admission_traffic_acceptance': {'seconds': None}}), '--only', ','.join(shard))
    unchanged = [f'inventory: {len(names)} listed tests',
                 f'python inventory: 1 registered Python test files {PY_SCOPE}',
                 '--- parse: FAIL', 'parse out', 'parse err',
                 '--- catalog_root_capacity: TIMEOUT', 'partial', '',
                 'runtime: LuaJIT',
                 'passed 2, failed 2, NOT RUN 1, no result row 0, listed 5',
                 'NOT RUN (not a pass): orbs: stand-in skip',
                 'PARTIAL: a shard was selected; this is not a complete run',
                 'RESULT: FAILED']
    timing = ['timing: catalog_root_capacity TIMEOUT 120.5 s (limit 120 s)',
              'timing: sync_admission_traffic_acceptance PASS unknown s (limit 120 s)',
              'timing: parse FAIL 2.5 s (limit 45 s)',
              'timing: boot PASS 0.25 s (limit 45 s)']
    python = [f'python: NOT SELECTED in a shard (not run, not a pass): {PY}']
    expect('ci_check timing lines show TIMEOUT and FAIL rows and print a missing seconds as unknown;'
           ' a shard prints the Python test as NOT SELECTED',
           out == unchanged[:-1] + timing + python + unchanged[-1:], ' | '.join(out[-12:]))
    expect('ci_check output without the timing and Python run lines is unchanged apart from the Python inventory'
           ' line: failure printing, counts, RESULT: FAILED, exit 1',
           [line for line in out if not line.startswith(('timing: ', 'python: '))] == unchanged and code == 1,
           f'exit {code}')

    # 9. A NOT_RUN row in a complete inventory is never a pass: RESULT FAILED, exit 1.
    code, out = run_ci_check(controlled_report(names, {'parse': {'status': 'NOT_RUN', 'reason': 'stand-in skip'}}))
    expect('a NOT_RUN row is printed as NOT RUN and fails the check, exit 1',
           'NOT RUN (not a pass): parse: stand-in skip' in out and out[-1] == 'RESULT: FAILED' and code == 1,
           f'exit {code}, last {out[-1:]}')

    # 10. The Python test registry: apart from NAMES, never passed to the Lua runtime, never counted there.
    runner = load_runner()
    registered = getattr(runner, 'PYTHON_TESTS', None)
    expect(f'PYTHON_TESTS registers exactly {PY}, apart from the Lua NAMES',
           registered == [PY] and not set(registered) & set(runner.NAMES), f'PYTHON_TESTS={registered!r}')
    expect('a Python test process gets 45 s',
           getattr(runner, 'PYTHON_TEST_TIMEOUT_SECONDS', None) == 45,
           f'PYTHON_TEST_TIMEOUT_SECONDS={getattr(runner, "PYTHON_TEST_TIMEOUT_SECONDS", None)!r}')
    fake = FakeProcesses()
    code, report, err = run_main(runner, fake)
    not_lua = [c for c in fake.commands
               if not (len(c) == 2 and c[1].startswith('tests/prototype/') and c[1].endswith('.lua'))]
    expect('the runner passes only tests/prototype/*.lua files to the Lua runtime and counts only NAMES, exit 0',
           not not_lua and len(fake.commands) == len(runner.NAMES) and counts(report) == (len(runner.NAMES), 0, 0)
           and code == 0, f'non-Lua commands {not_lua[:3]}, counts {counts(report)}, exit {code}')
    expect('the runner report lists the registered Python tests as run by ci_check, not by the runner',
           report is not None and report.get('registered_python_tests') == [PY]
           and 'not run or counted by this runner' in str(report.get('python_tests_scope', '')).lower(),
           f'registered_python_tests={(report or {}).get("registered_python_tests")!r}')

    # 11. ci_check's Python inventory: this checkout, then a missing, a duplicate, a malformed and an
    # unregistered entry. Each is refused before any process starts.
    check = getattr(load_ci_check(), 'check_python_inventory', None)
    found = check(list(registered or [])) if callable(check) else 'tools/ci_check.py has no check_python_inventory'
    expect('every tools/tests/test_*.py file in this checkout is registered, and every registered file exists',
           found == [], f'{found}')
    complete = controlled_report(names, {})
    for case, tests, problem in (
            ('a registered Python test without a file', [PY, 'tools/tests/test_stand_in_missing.py'],
             'Python test listed but no file: tools/tests/test_stand_in_missing.py'),
            ('a Python test registered twice', [PY, PY], f'Python test listed more than once: {PY}'),
            ('a registered entry outside tools/tests', [PY, '../outside/test_stand_in.py'],
             'Python test entry is not a tools/tests/test_*.py path: ../outside/test_stand_in.py')):
        result = ci_check_call(complete, prepare=with_runner(python_tests=tests))
        expect(f'{case} fails the inventory check: exit 1, nothing started',
               result.code == 1 and result.calls == [] and f'INVENTORY PROBLEM: {problem}' in result.out,
               f'exit {result.code}, {len(result.calls)} processes, {result.out[:4]}')
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        for rel in (PY, 'tools/tests/test_stand_in_unregistered.py', 'tools/tests/nested/test_stand_in_nested.py',
                    'tools/tests/stand_in_helper.py'):
            (base / rel).parent.mkdir(parents=True, exist_ok=True)
            (base / rel).write_text('', encoding='utf-8')
        result = ci_check_call(complete, prepare=with_runner(root=base))
    problem = ('INVENTORY PROBLEM: Python test file not listed in PYTHON_TESTS of tools/run_prototype_tests.py'
               ' (it would never run): tools/tests/nested/test_stand_in_nested.py,'
               ' tools/tests/test_stand_in_unregistered.py')
    expect('an unregistered tools/tests/test_*.py file, also in a subdirectory, fails the inventory check: exit 1,'
           ' nothing started; a file not named test_*.py is not a test',
           result.code == 1 and result.calls == [] and problem in result.out
           and not any('stand_in_helper' in line for line in result.out),
           f'exit {result.code}, {len(result.calls)} processes, {result.out[:4]}')

    # 12. --inventory-only checks both inventories and starts no test.
    result = ci_check_call(complete, '--inventory-only')
    expect('--inventory-only reports both inventories, starts no process and exits 0',
           result.code == 0 and result.calls == [] and result.out == [
               f'inventory: {len(names)} listed tests', f'python inventory: 1 registered Python test files {PY_SCOPE}',
               'inventory check passed; no test was executed'],
           f'exit {result.code}, {len(result.calls)} processes, {result.out}')

    # 13. A complete run: the Lua runner once, then each registered Python test as its own process.
    result = ci_check_call(complete)
    commands = [command for command, _ in result.calls]
    lua_command = commands[0] if commands else []
    lua_ok = (len(lua_command) > 1 and str(lua_command[1]).endswith('run_prototype_tests.py')
              and '--only' not in lua_command and not any('test_l10n_inventory' in str(part) for part in lua_command))
    py_command, py_keywords = result.calls[1] if len(result.calls) == 2 else ([], {})
    expect('a complete run starts the Lua runner once, without --only or a Python test, then the Python test',
           len(commands) == 2 and lua_ok, f'{len(commands)} processes: {[c[:2] for c in commands]}')
    expect('the Python test runs as [this interpreter, -B, its file] from the repository root, without a shell,'
           ' with captured output and a 45 s limit',
           py_command == [sys.executable, '-B', str(ROOT / PY)] and py_keywords.get('cwd') == ROOT
           and py_keywords.get('timeout') == 45 and not py_keywords.get('shell')
           and py_keywords.get('capture_output') is True, f'command {py_command}, keywords {py_keywords}')
    row = python_row(result.report)
    pyrep = (result.report or {}).get('python_tests') or {}
    expect('a passing Python test is PASS (exit 0, 0.5 s, limit 45 s) in the report and the output; the Lua counts'
           ' stay Lua-only, exit 0',
           result.code == 0 and row.get('status') == 'PASS' and row.get('exit') == 0 and row.get('seconds') == 0.5
           and row.get('timeout_seconds') == 45 and pyrep.get('selected') is True
           and (pyrep.get('passed'), pyrep.get('failed')) == (1, 0)
           and f'python: {PY} PASS 0.5 s (limit 45 s)' in result.out
           and f'passed {len(names)}, failed 0, NOT RUN 0, no result row 0, listed {len(names)}' in result.out
           and result.out[-1:] == ['RESULT: no listed test failed; every listed test ran'],
           f'exit {result.code}, row {row}, last {result.out[-3:]}')

    # 14. A nonzero exit, a timeout and a launch failure of a Python test each fail the check.
    for case, outcome, status, seconds, exit_code, stdout, stderr in (
            ('a nonzero exit', 1, 'FAIL', 0.5, 1, f'{PY} out', f'{PY} err'),
            ('a timeout', 'timeout', 'TIMEOUT', 45.25, None, 'py partial out', 'py partial err'),
            ('a launch failure', 'launch', 'LAUNCH_FAILED', 0.5, None, '',
             'FileNotFoundError: [Errno 2] stand-in launch failure')):
        result = ci_check_call(complete, python={PY: outcome})
        row = python_row(result.report)
        tail = [f'--- python {PY}: {status}', stdout, stderr, f'python: {PY} {status} {seconds} s (limit 45 s)',
                f'python: passed 0, failed 1, registered 1 {PY_SCOPE}', 'RESULT: FAILED']
        expect(f'{case} of the Python test is {status}, printed and counted apart from the Lua tests, exit 1',
               result.code == 1 and result.out[-len(tail):] == tail
               and f'passed {len(names)}, failed 0, NOT RUN 0, no result row 0, listed {len(names)}' in result.out
               and row.get('status') == status and row.get('exit') == exit_code and row.get('seconds') == seconds
               and row.get('timeout_seconds') == 45,
               f'exit {result.code}, last {result.out[-6:]}, row {row}')

    # 15. A --only shard runs the selected Lua tests only; a Python test is NOT SELECTED, never a pass.
    result = ci_check_call(controlled_report(['parse', 'boot'], {}), '--only', 'parse,boot')
    pyrep = (result.report or {}).get('python_tests') or {}
    expect('a --only shard starts only the Lua runner for the shard, prints the Python test as NOT SELECTED and'
           ' stays PARTIAL, exit 0',
           result.code == 0 and len(result.calls) == 1 and result.calls[0][0][-2:] == ['--only', 'parse,boot']
           and f'python: NOT SELECTED in a shard (not run, not a pass): {PY}' in result.out
           and 'PARTIAL: a shard was selected; this is not a complete run' in result.out
           and pyrep.get('selected') is False and pyrep.get('results') == [],
           f'exit {result.code}, {len(result.calls)} processes, out {result.out[-4:]}, python_tests {pyrep}')

    if failures:
        print('RESULT: FAILED:', '; '.join(failures))
        return 1
    print('RESULT: per-test timeouts, result rows, counts, exit status, ci_check timing lines and the registered'
          ' Python tests behave as declared; no Lua runtime or Python test file was started')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
