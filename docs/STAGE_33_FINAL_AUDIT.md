# Stage 33 HUD first-render source-only audit

Audit date: 2026-08-13

Verdict: **PASS OFFLINE / STOP BEFORE PACKAGING OR LIVE WORK**

This fail-closed audit proves the Stage 33 source repair at one exact reviewed
product head. It does not rebuild or replace test.14, create test.15, install
an addon, launch WoW, read or edit live SavedVariables, push, merge, tag,
release, publish, change licensing, or perform a remote action.

The existing test.14 archive remains immutable at SHA-256
`AB4307C6D9EBAC97485C0CDA14CE629EA8E81D04C18F3574C7BC788E6862D2A4`.
It predates this repair and therefore cannot prove the Stage 33 behavior live.

## Exact source boundary

- Branch: `codex/stutteralert-diagnostic-provider`.
- Stage 33 base: `06fd1537dc4e98efe562608fd40b112f3739727e`.
- Expected-red commit:
  `6d7debbd8017608bbbb119790bcf368f05c29025`.
- Reviewed product repair head:
  `4ac272320b9eb8b2ea06896cf5f8d20cf88445f4`.
- Pre-audit Stage 33 range: two commits, five paths, 692 insertions, and 57
  deletions.
- Public version: `1.20.0-beta.1`.
- Protocol: 7.
- TOC Author: `Valentine`.
- Upstream author attribution: `Boganic`, preserved through `UPSTREAM.md` and
  the existing metadata gate.
- Product worktree before this audit record: clean.

The five repaired or characterized paths are:

```text
core/Main.lua
core/MainLifecycle.lua
tests/run-upvalue-compatibility.js
tests/run_stage33_hud_first_render_characterization.lua
ui/Panel.lua
```

## Exact cause

`Panel.Show()`, `Panel.Toggle()`, and menu restoration could show the frame
created by `EnsureFrame()` even though no successful `Panel.Render()` had
committed a complete model. That constructor frame contained an empty header,
the raw `Auto: --` label, and uncommitted widget defaults.

`Panel.Render()` also assigned `_lastModel` before all widget and layout work
finished. A fault after one or more mutations could therefore leave a visible
partial tree and a stale signature that appeared current. Main's passive HUD
refresh evaluated model preparation outside its protected render call, so
preparation and render failures did not have separate attribution. A manual
first show with no cached Main input had no visibility-specific bounded
recovery route.

## Expected red and final green

The test-only checkpoint reproduced one named failure on the exact base:

```text
Stage 33.1 expected red (1): visible uncommitted HUD shell
show=1 toggle=1 menu=1 first_partial=1 later_partial=1
```

The reviewed repair produces:

```text
checks=36
raw_show=0 raw_toggle=0 raw_menu=0
first_partial=0 later_partial=0
setup_faults=1 layout_faults=1 provider_faults=1
recoveries=6
commits=4 render_failures=3 render_recoveries=3
main_requests=1
active=1 idle=2
actions=0 uploads=0 sync_uploads=0
```

No raw, first-partial, later-partial, menu-restored, or setup-fault tree becomes
visible. A fresh Main-owned first show remains hidden until the ordinary
automation owner publishes the first immutable model. Preparation and render
faults are attributed separately as `Main.RefreshHudView.Prepare` and
`Main.RefreshHudView.Render`.

## Repair ownership

- One fixed `renderState` table owns committed/applying/signature/failure
  state.
- `ApplyWantedVisibility()` is the only direct `frame:Show()` owner and
  requires a complete commit while no application is in progress.
- `ApplyCandidate()` runs widget setup and model application while the frame
  is hidden. Commit state, signature, and `_lastModel` publish only afterward.
- Any failed mutation clears commit and signature state, retains only the
  prior immutable model, and forces a complete later apply. Menu restoration
  cannot expose the invalid tree.
- `RequestFirstDisplay` is separate from generic `RefreshDisplay`: only
  Show/Toggle/menu recovery may request the existing bounded recompute owner.
  Ordinary Community/DPS/Sync view refresh remains passive.
- Main protects and attributes preparation separately from Panel application.
  Automation render failures are rethrown after attribution so the established
  owner still observes failure instead of treating it as success.

No second timer, retry state machine, scheduler, provider loop, dynamic
compilation, environment hack, or complete-model cache was added.

## Preservation receipts

| Boundary | Final deterministic result |
| --- | --- |
| Stage 33 assembled paths | 36 checks; five exposure counters zero; six bounded recoveries; zero gameplay/data mutations |
| Startup, Panel, HUD, lifecycle, dirty, refusal | Focused owners pass, including Changelog/menu and explicit-hide behavior |
| Direct safety fallback | 20 intervals, 500 polls, 20 checks, zero repairs/full steps/probes/associations/uploads/mutations |
| Action lifecycle | prepared 8, submitted 4, confirmed 3, uncertain 1, expired 1, superseded 4, preauthorization failures 0, selects 4 |
| Sync automation isolation | 50 accepted updates; 50 polls; full/policy/render/association/upload/Sync-upload/mutation all zero |
| Realistic UI work | 1,000 builds, 500 DPS rows, 25 warm ticks, 50 hidden ticks, 100 identical renders, four layout computations, 64 frames, four cards, 119/119 bounded scale samples |
| Integration | 70/70 checks pass; protected Blizzard globals remain stock-owned |
| Hostile Sync | 4,000/4,000 deterministic payloads remain bounded and fail closed |

Stage 25 semantic-board coalescing, revision-keyed projections, immutable
action intents, bounded fallback repair, zero repeated warm catalog/Wishlist/
slot traversals, and fixed Wishlist overlay state remain green. Stage 26 Sync,
DPS, UI, diagnostic, wire, ownership, tombstone, SavedVariables, paging, queue,
and compatibility behavior remains green.

The implementation-time complete replay caught one unacceptable intermediate
route where generic view refresh could request automation before a HUD input
existed. The final split between `RequestFirstDisplay` and `RefreshDisplay`
removes that amplification; only the repaired final run is counted.

## Complete validation

- Complete Lua suite: `179/179 PASS`, zero excluded or skipped.
- Lua 5.1 source/test parse: `1077/1077 PASS`.
- TOC inventory: 65 Lua files, zero missing.
- Upvalue boundary: 60 passes and 61 fails.
- Packaged-function source gate: 65 TOC files, 2,697 functions, zero above 60.
- Highest packaged function: `ui/Panel.lua:385 EnsureFrame=60`.
- `ApplyModel=47`, `M.Render=9`, `AutomationRuntime.Step=16`.
- Automation boot: 65 TOC files, one factory call, two polls, startup banner
  present, no error.
- Integration: `70/70 PASS`.
- Hostile Sync: `4,000/4,000 PASS`.
- Module inventory: 10 modules, 188 public surfaces, 14 assigned members, 155
  callback sites, 17 groups, zero unmapped.
- Package metadata: `Author=Valentine`; controlled runtime identity and
  upstream Boganic attribution pass.
- Deterministic bundled-build exporter: `PASS`.
- Read-only SavedVariables analyzer: `PASS`.
- Stage 30 diagnostic identity/privacy and compatibility isolation: `PASS`.
- StutterAlert registration, bounds, failure isolation, and session-only
  storage: `PASS`.
- Historical test.5-test.13 hashes: `9/9 PASS`.
- Existing test.14 hash: exact and unchanged.
- Added-line private-sentinel, dynamic-compilation, environment-hack,
  metadata, inventory, and diff checks: `PASS`.

No expected-red, interrupted timeout, intermediate failing replay, skipped,
unavailable, or malformed command is included in the green totals.

## Fixed offline

- Constructor widgets cannot become visible before a complete model commit.
- Signature equality cannot certify a failed or never-committed tree.
- First and later setup/widget failures stay hidden through menu restoration.
- The prior immutable model remains the only last-good owner; recovery performs
  a complete apply on the next valid existing refresh path.
- Manual first display requests exactly one bounded Main route without making
  generic view revisions stateful.
- Preparation and render failures have precise source/stage attribution.
- The former 58-upvalue render body is now a 47-upvalue application helper;
  the small transactional wrapper uses nine.

## Still live-unproven

- No artifact contains the Stage 33 repair. Test.14 remains the preserved
  pre-repair artifact and must not be used to claim this fix.
- Installation and startup of a separately authorized future exact-head build
  on either computer.
- In-game first Show/Toggle/menu behavior and injected-failure equivalence on
  the WoW 3.3.5a client.
- Exact same-build two-user Share and complete Sync convergence.
- Live frame time, memory high-water, garbage collection, and StutterAlert
  attribution after this repair.
- Project Ebonhold Orb of Lost Memories behavior without authoritative API,
  event, and roll-context evidence.

Stage 33 passes offline at reviewed product head `4ac2723`. The next permitted
action is only a separately authorized packaging checkpoint for a new artifact.
This workflow stops here with test.14 unchanged and no live or remote action.
