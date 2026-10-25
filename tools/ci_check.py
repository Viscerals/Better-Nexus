#!/usr/bin/env python3
"""Repository check for a clean checkout: test inventory integrity, then the offline suite.

Python 3.9+ and a `luajit` executable on PATH. No network, no game client.

    python tools/ci_check.py                      # inventory check + complete suite
    python tools/ci_check.py --inventory-only     # no Lua runtime needed; no test is started
    python tools/ci_check.py --only parse,boot    # bounded Lua shard (never reported as complete)

Results are reported as they are. A test that was not run is NOT a pass:
  * FAIL or TIMEOUT                      -> exit 1
  * a listed test without a result row   -> exit 1
  * a NOT_RUN row                        -> printed as NOT RUN; exit 1
Every listed test runs from this checkout; none needs a separate project, archive or variable.
The inventory size is whatever tools/run_prototype_tests.py lists; no count is hard-coded here.
Before the RESULT line, "timing:" lines give the elapsed time and limit of every executed test whose
limit is not the runner's default, and of the five slowest executed tests. They change no result.

Python tests are registered in PYTHON_TESTS in tools/run_prototype_tests.py, apart from the Lua
NAMES. The inventory check fails for a duplicate entry, an entry that is not a tools/tests/test_*.py
path, a registered file that is missing, or a test_*.py file under tools/tests that is not
registered. After the Lua suite, a complete run starts each registered file as its own process with
this Python interpreter: no shell, PYTHON_TEST_TIMEOUT_SECONDS each. A nonzero exit (FAIL), a
timeout (TIMEOUT) or a process that cannot start (LAUNCH_FAILED) fails the check. "python:" lines
report them just before the RESULT line; they are not counted with the Lua tests, and the --output
report gains a "python_tests" object. --inventory-only starts no test. A --only shard selects Lua
tests only: it starts no Python test, prints each as NOT SELECTED (not run, not a pass) and stays
PARTIAL. If the Lua runner writes no report, no Python test is started and the check fails.
"""
from __future__ import annotations
import argparse, importlib.util, json, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests' / 'prototype'
# Files under tests/prototype that are loaded by tests and are not tests themselves.
SUPPORT = {'harness', 'policy_adapter', 'startup_benchmark'}
# Ends the Python inventory and summary lines.
PYTHON_SCOPE = '(separate processes; not counted with the listed Lua tests)'


def runner_module():
    spec = importlib.util.spec_from_file_location('run_prototype_tests', ROOT / 'tools' / 'run_prototype_tests.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def inventory() -> list[str]:
    return list(runner_module().NAMES)


def timing_lines(rows: dict, default_timeout) -> list[str]:
    """Every executed test whose timeout_seconds is not the default, then the five slowest executed
    tests by seconds; each test once. A missing seconds or timeout_seconds is printed as unknown."""
    executed = {n: r for n, r in rows.items() if r['status'] != 'NOT_RUN'}
    raised = [n for n, r in executed.items()
              if default_timeout is not None and r.get('timeout_seconds') not in (None, default_timeout)]
    timed = [n for n, r in executed.items() if isinstance(r.get('seconds'), (int, float))]
    slowest = sorted(timed, key=lambda n: executed[n]['seconds'], reverse=True)[:5]

    def shown(value):
        return 'unknown' if value is None else value
    return [f'timing: {n} {executed[n]["status"]} {shown(executed[n].get("seconds"))} s '
            f'(limit {shown(executed[n].get("timeout_seconds"))} s)'
            for n in raised + [n for n in slowest if n not in raised]]


def check_inventory(names: list[str]) -> list[str]:
    problems = []
    duplicates = sorted({n for n in names if names.count(n) > 1})
    if duplicates:
        problems.append('listed more than once: ' + ', '.join(duplicates))
    missing = sorted(n for n in set(names) if not (TESTS / (n + '.lua')).is_file())
    if missing:
        problems.append('listed but no file: ' + ', '.join(missing))
    on_disk = {p.stem for p in TESTS.glob('*.lua')}
    unlisted = sorted(n for n in on_disk - set(names) if n not in SUPPORT and not n.endswith('_support'))
    if unlisted:
        problems.append('test file not listed in tools/run_prototype_tests.py (it would never run): ' + ', '.join(unlisted))
    return problems


def python_test_path_ok(path) -> bool:
    """A registered Python test entry: a relative POSIX path tools/tests/.../test_*.py, already canonical.
    Its literal '/'-separated segments are checked, not a normalized path: an empty, '.' or '..' segment
    is refused, so a './', '//' or trailing '/' spelling of a test file is not accepted as that file."""
    if not isinstance(path, str) or '\\' in path:
        return False
    parts = tuple(path.split('/'))
    return (len(parts) >= 3 and parts[:2] == ('tools', 'tests') and {'', '.', '..'}.isdisjoint(parts)
            and parts[-1].startswith('test_') and parts[-1].endswith('.py'))


def check_python_inventory(paths: list, root: pathlib.Path = None) -> list[str]:
    """Problems with the registered Python tests, checked against <root>/tools/tests (default ROOT)."""
    root = ROOT if root is None else root
    problems = []
    duplicates = sorted({str(p) for p in paths if paths.count(p) > 1})
    if duplicates:
        problems.append('Python test listed more than once: ' + ', '.join(duplicates))
    malformed = sorted({str(p) for p in paths if not python_test_path_ok(p)})
    if malformed:
        problems.append('Python test entry is not a tools/tests/test_*.py path: ' + ', '.join(malformed))
    missing = sorted({p for p in paths if python_test_path_ok(p) and not (root / p).is_file()})
    if missing:
        problems.append('Python test listed but no file: ' + ', '.join(missing))
    on_disk = {p.relative_to(root).as_posix() for p in (root / 'tools' / 'tests').rglob('test_*.py') if p.is_file()}
    unlisted = sorted(on_disk - {p for p in paths if isinstance(p, str)})
    if unlisted:
        problems.append('Python test file not listed in PYTHON_TESTS of tools/run_prototype_tests.py '
                        '(it would never run): ' + ', '.join(unlisted))
    return problems


def as_text(value) -> str:
    """Captured output as text; a timeout can leave bytes or None."""
    if value is None:
        return ''
    if isinstance(value, bytes):
        return value.decode('utf-8', errors='replace')
    return str(value)


def run_python_tests(paths: list[str], timeout) -> list[dict]:
    """Start each registered Python test file as its own process with this interpreter (-B, no shell,
    the repository root as working directory) and return one result row per file, in order:
    PASS, FAIL (nonzero exit), TIMEOUT (the limit expired) or LAUNCH_FAILED (it could not start)."""
    results = []
    for path in paths:
        command = [sys.executable, '-B', str(ROOT / path)]
        start = time.monotonic()
        try:
            run = subprocess.run(command, cwd=ROOT, capture_output=True, encoding='utf-8', errors='replace',
                                 timeout=timeout)
            row = {'test': path, 'status': 'PASS' if run.returncode == 0 else 'FAIL', 'exit': run.returncode,
                   'stdout': as_text(run.stdout), 'stderr': as_text(run.stderr)}
        except subprocess.TimeoutExpired as exc:
            row = {'test': path, 'status': 'TIMEOUT', 'stdout': as_text(exc.stdout), 'stderr': as_text(exc.stderr)}
        except (OSError, ValueError) as exc:
            row = {'test': path, 'status': 'LAUNCH_FAILED', 'stdout': '', 'stderr': f'{type(exc).__name__}: {exc}'}
        row['seconds'] = round(time.monotonic() - start, 6)
        row['timeout_seconds'] = timeout
        results.append(row)
    return results


def python_lines(rows: list[dict], registered: list[str], shard: bool) -> list[str]:
    """The "python:" lines; a failed row's output tails come first, as for a failed Lua test."""
    if shard:
        return [f'python: NOT SELECTED in a shard (not run, not a pass): {p}' for p in registered]
    lines = []
    for r in rows:
        if r['status'] != 'PASS':
            lines += [f'--- python {r["test"]}: {r["status"]}', r['stdout'][-1500:], r['stderr'][-1500:]]
    lines += [f'python: {r["test"]} {r["status"]} {r["seconds"]} s (limit {r["timeout_seconds"]} s)' for r in rows]
    passed = sum(r['status'] == 'PASS' for r in rows)
    lines.append(f'python: passed {passed}, failed {len(rows) - passed}, registered {len(registered)} {PYTHON_SCOPE}')
    return lines


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--inventory-only', action='store_true')
    ap.add_argument('--only', help='comma-separated Lua test shard; no Python test runs; the result is labelled PARTIAL')
    ap.add_argument('--output', type=pathlib.Path, default=ROOT / 'build' / 'prototype-test-results.json')
    ns = ap.parse_args()

    runner = runner_module()
    names = list(runner.NAMES)
    python_tests = list(runner.PYTHON_TESTS)
    problems = check_inventory(names) + check_python_inventory(python_tests)
    print(f'inventory: {len(names)} listed tests')
    print(f'python inventory: {len(python_tests)} registered Python test files {PYTHON_SCOPE}')
    for p in problems:
        print('INVENTORY PROBLEM:', p)
    if problems:
        return 1
    if ns.inventory_only:
        print('inventory check passed; no test was executed')
        return 0

    command = [sys.executable, str(ROOT / 'tools' / 'run_prototype_tests.py'), '--runtime', 'luajit', '--output', str(ns.output)]
    if ns.only:
        command += ['--only', ns.only]
    ns.output.parent.mkdir(parents=True, exist_ok=True)
    if ns.output.exists():
        ns.output.unlink()
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if not ns.output.is_file():
        print(run.stdout[-4000:]); print(run.stderr[-4000:])
        print('RESULT: the runner wrote no report; nothing is counted as passed')
        return 1
    report = json.loads(ns.output.read_text(encoding='utf-8'))
    rows = {r['test']: r for r in report['results']}
    # The Python tests run after the Lua suite, never in a shard; their rows stay apart from the Lua rows.
    python_rows = [] if ns.only else run_python_tests(python_tests, runner.PYTHON_TEST_TIMEOUT_SECONDS)
    python_failed = [r['test'] for r in python_rows if r['status'] != 'PASS']
    report['python_tests'] = {'registered': python_tests, 'selected': not ns.only,
                              'python_version': sys.version.split()[0], 'results': python_rows,
                              'passed': len(python_rows) - len(python_failed), 'failed': len(python_failed)}
    ns.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    expected = ns.only.split(',') if ns.only else names
    unexecuted = [n for n in expected if n not in rows]
    # Anything that is not an explicit PASS or NOT_RUN counts as failed, including an unknown status.
    failed = [n for n, r in rows.items() if r['status'] not in ('PASS', 'NOT_RUN')]
    not_run = [n for n, r in rows.items() if r['status'] == 'NOT_RUN']
    passed = [n for n, r in rows.items() if r['status'] == 'PASS']
    for n in failed:
        r = rows[n]
        print(f'--- {n}: {r["status"]}')
        print((r.get('stdout') or '')[-1500:]); print((r.get('stderr') or '')[-1500:])
    print(f'runtime: {report["runtime"]}')
    print(f'passed {len(passed)}, failed {len(failed)}, NOT RUN {len(not_run)}, no result row {len(unexecuted)}, listed {len(expected)}')
    for n in not_run:
        print(f'NOT RUN (not a pass): {n}: {rows[n].get("reason", "")}')
    if ns.only:
        print('PARTIAL: a shard was selected; this is not a complete run')
    for line in timing_lines(rows, getattr(runner, 'DEFAULT_TIMEOUT_SECONDS', None)):
        print(line)
    admission = rows.get('sync_admission_traffic_acceptance')
    if admission and admission['status'] == 'PASS' and admission.get('stdout'):
        print((admission.get('stdout') or '').rstrip())
    for line in python_lines(python_rows, python_tests, bool(ns.only)):
        print(line)
    if failed or unexecuted or not_run or python_failed:
        print('RESULT: FAILED')
        return 1
    print('RESULT: no listed test failed; every listed test ran')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
