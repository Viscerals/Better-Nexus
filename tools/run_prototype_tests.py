#!/usr/bin/env python3
"""Run only the prototype-specific checks. Never represents the upstream full suite.
Python 3.9+. Native LuaJIT is preferred if installed; the local Lua 5.4 fallback
is explicitly labelled and requires liblua5.4. No network or game access.
"""
from __future__ import annotations
import argparse, ctypes.util, hashlib, json, os, pathlib, shutil, subprocess, sys, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
NAMES=['parse','boot','wishlist','lock_evidence','ownership','typed_hash','transport','automation','manual_sync','diagnostics','features','planner_reference','startup','startup_evidence','startup_failure','startup_validation','startup_drift','startup_budget','startup_persistence','startup_source_change','role_selection','role_boundaries','role_persistence','role_export','current_locks','loading_status','loading_local','current_locks_reload','current_locks_exact','orbs','orbs_controls','orbs_ambiguity','orbs_same_echo','orbs_prerequisites','orbs_reload','orbs_policy','orbs_ui','orbs_context','orbs_permanent','orbs_loading','help','terminology']
NAMES += ['orbs_review_sources','orbs_review_lifecycle','orbs_review_same_id','orbs_review_recheck','orbs_review_availability','orbs_review_ordering','orbs_review_disclosure','orbs_review_recovery','terminology_consumers']
NAMES += ['orbs_review_rejected_selection','orbs_review_catalog','orbs_review_catalog_grouping']
NAMES += ['orbs_assigned','help_layout','assignment_restore','orbs_target_changes','orbs_assigned_protection','orbs_main_controls','session_permissions','orbs_assignment_races','orbs_assigned_resources','assignment_identity','orbs_loadout_change']

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--runtime',choices=['auto','luajit','lua54'],default='auto')
    ap.add_argument('--reference',type=pathlib.Path,help='Path to extracted supplied LoadoutPilot directory')
    ap.add_argument('--output',type=pathlib.Path,default=pathlib.Path('prototype-test-results.json'))
    ap.add_argument('--only',help='Comma-separated existing test names for a bounded shard; omitted runs every test')
    ns=ap.parse_args()
    names=ns.only.split(',') if ns.only else NAMES
    if len(names)!=len(set(names)) or any(n not in NAMES for n in names): ap.error('Unknown or duplicate --only test')
    native=shutil.which('luajit')
    if ns.runtime=='luajit' and not native: ap.error('LuaJIT requested but not installed')
    if native and ns.runtime!='lua54': command=[native]; runtime='LuaJIT'
    else:
        if not ctypes.util.find_library('lua5.4'): ap.error('Neither requested LuaJIT nor liblua5.4 is available')
        command=[sys.executable,str(ROOT/'tools/prototype_lua54.py')]
        runtime='Lua 5.4 with test-only compatibility shims; NOT LuaJIT/Lua 5.1/WoW'
    env=os.environ.copy()
    reference=(ns.reference or ROOT.parent/'reference/LoadoutPilot').resolve()
    env['LOADOUTPILOT_ROOT']=str(reference)
    results=[]
    for name in names:
        if (name=='planner_reference' and not (reference/'Engine/WishlistPlanner.lua').is_file()) or (name=='orbs_policy' and not (reference/'Memory/MemoryMode.lua').is_file()):
            results.append({'test':name,'status':'NOT_RUN','reason':'Supplied LoadoutPilot reference not available'});continue
        start=time.monotonic()
        try:
            p=subprocess.run(command+[f'tests/prototype/{name}.lua'],cwd=ROOT,env=env,text=True,capture_output=True,timeout=45)
            row={'test':name,'status':'PASS' if p.returncode==0 else 'FAIL','exit':p.returncode,
                 'seconds':round(time.monotonic()-start,6),'stdout':p.stdout,'stderr':p.stderr}
        except subprocess.TimeoutExpired as exc:
            row={'test':name,'status':'TIMEOUT','seconds':45,'stdout':str(exc.stdout or ''),'stderr':str(exc.stderr or '')}
        results.append(row);print(name,row['status']);print(row.get('stdout','').rstrip());print(row.get('stderr','').rstrip())
    runtime_files=[]
    for line in (ROOT/'Nexus.toc').read_text().splitlines():
        if line.strip() and not line.startswith('#'):
            p=ROOT/line.replace('\\','/');runtime_files.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    report={'schema':'nexus-prototype-tests/1','runtime':runtime,'selected_tests':names,'complete_inventory':NAMES,'source_runtime_files':runtime_files,
            'scope':'Prototype-specific synthetic offline tests, not the original 245-runner suite or native WoW validation',
            'results':results,'passed':sum(r['status']=='PASS' for r in results),
            'failed':sum(r['status'] in ('FAIL','TIMEOUT') for r in results),'not_run':sum(r['status']=='NOT_RUN' for r in results)}
    out=ns.output.resolve();out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('REPORT',out);return 1 if report['failed'] or report['not_run'] else 0
if __name__=='__main__': raise SystemExit(main())
