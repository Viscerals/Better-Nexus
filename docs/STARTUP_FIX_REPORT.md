# Nexus prototype P1.2 — startup work and readiness correction

## Changes made

- Evidence owner initialization occurs once per bootstrap/database, instead of on
  every resumed catalog-admission slice. A rebind has a separate source/owner
  check; normal per-pump catalog token validation is retained. No saved marker
  or persistent cached validation is introduced.
- Core UI, commands, local Wishlist editing, and Echo controls are released only
  after actual Store readiness and an admitted catalog. They no longer also wait
  for Community startup scanning/identity preparation to complete.
- Community preparation continues on the existing lifecycle under the existing
  2 ms soft allowance and finite slice cap. Sync and DPS service initialization,
  automatic maintenance, and their live events remain behind the shared-ready
  boundary. A shared preparation failure is recorded once, not retried endlessly,
  and does not invalidate already-safe local controls.
- Community and Leaderboard open a read-only preparing window until their shared
  data is ready. Closing it or opening another local window cancels the deferred
  view, preventing a late window from stealing focus. The selected view opens
  after completion if the waiting window is still open.
- Manual Sync during shared startup explicitly reports that it is unavailable
  yet; it does not silently retain/send a request. After service readiness the
  existing manual operation path and budgets remain in force.
- A legitimate catalog change while the shared startup cursor is scanning causes
  a fresh bounded scan of the new committed root, not publication of an old scan.

## Scope

Runtime owners changed: core/Store.lua, core/MainLifecycle.lua,
core/CommunityController.lua, core/Main.lua, core/Sync.lua,
ui/CommunityBuilds.lua, ui/Leaderboard.lua, ui/Panel.lua.

The planner, GameAdapter/P1.1 locked-Wishlist correction, WishlistController,
transport, catalog implementation, evidence algorithms, settings, and TOC are
unchanged. No automatic data deletion, quarantine, resource spending, installer,
or native game operation was performed. Source and test artifacts from P1.1
remain preserved.

## Evidence

20 prototype-specific scripts pass. This includes the previous 12 scripts and
8 startup regressions. The existing 10,000-case LoadoutPilot comparison and
96-assertion locked-Wishlist regression still pass.

New coverage:

- real local UI/commands usable while Community is held pending;
- safe shared-service/event gating and no pre-ready send;
- preparing-window close/transition behavior;
- once-per-source evidence initialization with real catalog admission;
- complete catalog and opaque/unknown data preservation;
- shared-initializer failure without local-service failure/retry storms;
- invalid Store input and replaced evidence-owner refusal;
- timer deadline, hard slice cap, overshoot, and missing/invalid clock fallback;
- synthetic save before shared readiness and literal-data fresh module reload;
- legitimate local/catalog changes during background scanning.

The same two focused startup regressions fail on the unchanged provided P1.1
source: local readiness is held behind pending Community, and evidence Init is
called 664 times for the 24-build/300-opaque-entry fixture. The corrected source
passes those assertions and retains all old prototype tests.

## Measured comparison (synthetic, two completed trials per row)

| Synthetic input | P1.1 evidence Init calls | P1.2 calls | P1.1 updates until local-ready | P1.2 updates until local-ready | P1.1 CPU until local-ready | P1.2 CPU until local-ready |
|---|---:|---:|---:|---:|---:|---:|
| 100 builds x 79 ordinary entries, 5,000 preserved opaque evidence entries | 2,827 | 1 | 1,109–1,126 | 287–296 | 2.946–3.039 s | 0.683–0.712 s |
| 400 builds x 79 ordinary entries, no initial opaque pool | 11,009–11,010 | 1 | 3,466–3,509 | 1,168–1,186 | 9.933–10.460 s | 2.904–3.041 s |

These are process CPU measurements and update counts in a synthetic environment
with 0.05-second simulated updates. They are NOT native startup times, frame
budgets, or a promise to reach readiness within a fixed number of real seconds.
Both versions produce matching sorted public ordinary-Echo records. Unknown
row data and the synthetic opaque evidence entries remain preserved.

Shared work is not pretended complete when local controls become available.
For the 100-build/5,000-entry case, total CPU to shared-ready fell from
2.946–3.039 s to 2.281–2.302 s. For 400 builds without the opaque pool, total CPU
to shared-ready remained about 10 seconds (9.933–10.460 before; 10.431–10.648
after): this case mainly benefits from earlier local readiness, not less total
shared-data processing. Initial Store/catalog validation still takes time and
is not bypassed.

Two multi-command benchmark batches hit the shell tool's aggregate timeout;
completed trials were preserved and the remaining trials were run as separate
bounded processes. No timed-out batch is counted as a passing trial.

## Runtime and limits

Actual tests: system liblua5.4 with the supplied test-only compatibility shims.
All 71 TOC Lua files compile in that environment. The existing reachable runtime
closure check remains at most 60 non-environment upvalues.

LuaJIT installation was unavailable because the disposable container could not
reach its package index. No LuaJIT/Lua 5.1 execution, full upstream suite,
independent model review, hosted CI, actual client reload, or native WoW timing
is claimed. No user's game/client/saved-data installation was accessed.

The source uses the existing target-compatible APIs and style, but offline
Lua 5.4 success is not proof of native Lua 5.1 behavior.

## Player retest

Close WoW and back up the current Nexus folder and WTF together. Replace only
the addon folder with P1.2. Do not delete saved builds or unknown fields.
Keep automation OFF for the initial check.

Confirm the test.9003 build identity with /nexus status after local readiness.
Measure login-to-local-control readiness separately from shared-ready time.
Open the same existing Wishlist and its lock targets, open Community/Leaderboard
while preparing, and perform one ordinary /reload to check preservation.

Community/Leaderboard/Sync/DPS may still be preparing after local controls work.
DPS capture is not claimed active until shared initialization completes. The
view explicitly shows its waiting/error state. Do not assume peer convergence
or perform forced/resource-consuming tests to validate this startup correction.

If local preparation still takes a long time, return a short build/status
screenshot and approximate times for the two readiness stages. Do not run a
full diagnostic export or clear data as a workaround.

## Provenance

Built from the provided P1.1 source ZIP, SHA-256:
097102392764345e355769851879225c7eea9090d83e01f718f999471a9d7d5c.

The local Git history begins with an import of that archive. Its parent must
not be described as a verified descendant of the unpublished b47b325 commit.
GitHub branches, T3 worktrees, original ZIPs, and player data are unchanged.
