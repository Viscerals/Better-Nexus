#!/usr/bin/env python3
"""Repository check for a clean checkout: test inventory integrity, then the offline suite.

Python 3.9+ and a `luajit` executable on PATH. No network, no game client.

    python tools/ci_check.py                      # inventory check + complete suite
    python tools/ci_check.py --inventory-only     # no Lua runtime needed
    python tools/ci_check.py --only parse,boot    # bounded shard (never reported as complete)

Results are reported as they are. A test that was not run is NOT a pass:
  * FAIL or TIMEOUT                      -> exit 1
  * a listed test without a result row   -> exit 1
  * NOT_RUN outside REFERENCE_DEPENDENT  -> exit 1
  * NOT_RUN inside REFERENCE_DEPENDENT   -> printed as NOT RUN; exit 0 only without --require-reference
REFERENCE_DEPENDENT tests compare against a third-party LoadoutPilot archive that this repository
has no permission to redistribute (see THIRD_PARTY.md and tools/prepare_pilot_reference.py).
The inventory size is whatever tools/run_prototype_tests.py lists; no count is hard-coded here.
Before the RESULT line, "timing:" lines give the elapsed time and limit of every executed test whose
limit is not the runner's default, and of the five slowest executed tests. They change no result.
"""
from __future__ import annotations
import argparse, importlib.util, json, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests' / 'prototype'
REFERENCE_DEPENDENT = {'planner_reference', 'orbs_policy'}
# Files under tests/prototype that are loaded by tests and are not tests themselves.
SUPPORT = {'harness', 'policy_adapter', 'startup_benchmark'}


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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--inventory-only', action='store_true')
    ap.add_argument('--only', help='comma-separated shard; the result is labelled PARTIAL')
    ap.add_argument('--require-reference', action='store_true', help='fail when a reference-dependent test was not run')
    ap.add_argument('--reference', type=pathlib.Path, help='extracted LoadoutPilot reference directory')
    ap.add_argument('--output', type=pathlib.Path, default=ROOT / 'build' / 'prototype-test-results.json')
    ns = ap.parse_args()

    runner = runner_module()
    names = list(runner.NAMES)
    problems = check_inventory(names)
    print(f'inventory: {len(names)} listed tests')
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
    if ns.reference:
        command += ['--reference', str(ns.reference)]
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
    unexpected_not_run = [n for n in not_run if n not in REFERENCE_DEPENDENT or ns.require_reference]
    if failed or unexecuted or unexpected_not_run:
        print('RESULT: FAILED')
        return 1
    print('RESULT: no listed test failed' + (f'; {len(not_run)} reference-dependent test(s) NOT RUN' if not_run else ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
