# Stage 25 Echo-rolling performance final audit

Audit date: 2026-08-11

Verdict: **PASS OFFLINE / LIVE PERFORMANCE AND TWO-USER TEST REQUIRED**

This audit is fail-closed. It proves deterministic source behavior and bounded
operation counts only. It does not claim that the reported in-game freeze is
fixed, create or modify an artifact, install the addon, change live
SavedVariables, run the Stage 24 two-user procedure, or authorize a push,
merge, tag, release, or publication.

The existing test.9 archive is a preserved historical Stage 24.8 artifact
pinned to `e66fd87`; it is not a Stage 25 package and was neither opened nor
modified for this audit. A Stage 25 artifact does not exist.

## Audited source

- Branch: `codex/stutteralert-diagnostic-provider`
- Stage 25 base: `e66fd87ce8367e5ae544e4c61bf8470cae302354`
- Reviewed source head before this audit record:
  `477ac295ee9d0246cd2a3cfb0bbdbe6b10628ecd`
- Source identity: `1.20.0-beta.1`, local and unpublished
- Stage 25 source commits before this audit record: 9
- Stage 25 range before this audit record: 12 files, 2,009 additions, 133
  deletions
- Installed addon, live saves, remotes, releases, and preserved build archives:
  unchanged by Stage 25

Stage 25 commits, in order:

1. `06c63c138a771c4f9935b391735fa9a9a68479de` - characterize
   Echo-rolling phase amplification.
2. `69dbadef890ad8a28baed07171e42cf4476ea501` - characterize duplicate
   board delivery.
3. `e4d3ba256d4c10d93ae1c613f582d2e60be8dee1` - bound
   revision-aware automation work.
4. `245fd291dea8ceaccca17552b4a50d2cf99995ba` - harden board
   coalescing review cases.
5. `761824dc698da5338a2a2722eb7e66e6b8ee90d9` - bind automation
   actions to board intents.
6. `13153f9c6a8b752f128357034d9490868ec0f00a` - harden action
   lifecycle boundaries.
7. `7676c91be3b35d66d9a9b7bfbc71e03774280e15` - bound Wishlist
   overlay presentation work.
8. `0dd524cccd9ff4e932d8fa7ee4a584230de75281` - harden overlay
   revision boundaries.
9. `477ac295ee9d0246cd2a3cfb0bbdbe6b10628ecd` - eliminate uncached
   Wishlist traversals.

## Proven cause and repair

The supplied live evidence correctly identified `automation.step` as the
dominant synchronous owner, but it could not identify which internal work was
repeating. The Stage 25 expected-red fixture supplied that missing attribution:
200 semantic boards produced 200 valid decisions but also 401 slot reads over
170,425 Echo rows, 200 owned reads over 15,800 entries, 400 locked reads, and
200 lever reads over 46,000 membership checks. Twenty duplicate board Shows
also caused 20 unnecessary decisions and renders. Static catalog/Wishlist/plan
work was already cached, and accepted/rejected Sync traffic produced no
automation work, so chat/Sync was correlation rather than the measured owner in
the deterministic path.

Revision-keyed dynamic projections, semantic-board coalescing, and targeted
fallback repair removed those repeated automation acquisitions while preserving
one decision for each genuine board. Immutable board-bound action intents then
closed delayed, duplicate, missing, stale, and uncertain confirmation paths
without creating a second state machine or moving the direct safety tick.

The overlay follow-up made its Wishlist/Owned/Catalog projections revision-keyed,
kept fixed widgets and 90 scalar line states, skipped hidden or unchanged work,
and moved recursive styling to one-time frame construction.

The final cross-surface audit found a separate known-nil cache bug. When the
static snapshot intentionally contained no Wishlist, panel progress treated nil
as “not cached” and called `GameAdapter.Wishlist()` for every board. That call
walked all five saved slots: 201 calls and 85,425 Echo visits in the 200-board
fixture. The panel now distinguishes a known-nil static snapshot from a missing
snapshot, and run-start audit metadata uses the same static snapshot. The final
fixture records zero all-surface Wishlist calls, zero slot calls, and zero slot
Echo visits during the 200-board roll.

## Final adversarial verdict matrix

| Boundary | Verdict | Deterministic evidence | Live limit |
| --- | --- | --- | --- |
| Rapid distinct and duplicate boards | `PASS` | 200 distinct boards produce 200 Board reads, 600 cards, 200 policy decisions, zero static probes/compiles, and zero repeated Slots/Owned/Locked/Lever projections. Twenty identical Shows produce zero steps, decisions, renders, Board reads, or slot projections. | Real server cadence and frame time remain unmeasured. |
| Traffic and unrelated bursts | `PASS` | Twenty accepted and twenty rejected messages plus unrelated traffic schedule zero automation work. The isolation fixture admits 50 Sync updates with zero repair, full step, policy, render, association, upload, or mutation. | Live channel delivery may overlap a long frame; overlap is not causation. |
| Static and dynamic revisions | `PASS` | Slot, owned, locked, and lever changes refresh only their dependent projection once; catalog/settings/Wishlist changes refresh static context once. Equivalent notifications do no work. | Live provider shapes outside exercised validated forms remain unproved. |
| Five-second fallback | `PASS` | 500 polls over 20 matching intervals perform 20 cheap checks, zero repair/full-step/static-probe/compile/policy/render/action work. One deliberately missed granted change repairs once and does not loop. | Long-session live provider behavior remains unmeasured. |
| Action lifecycle | `PASS` | Prepared=8, submitted=4, confirmed=3, uncertain=1, expired=1, superseded=4, selects=4. Duplicate, stale, malformed, revoked, delayed, missing, exact-deadline, and run-reset paths do not duplicate or cross-apply mutation. | Server acknowledgement timing and every real mutation path require live observation. |
| Overlay and retained memory | `PASS` | 809 refreshes: 400 hidden skips, 401 visible revision skips, 8 bounded projection builds, 1 identical rebuilt model, 267 affected row writes, 1 style pass, 4 frames, 90 lines, and 90 retained scalar line states. | WoW allocator high-water and garbage-collection pauses remain unproved. |
| Community and Leaderboard interaction | `PASS` | 1,000 builds/500 DPS rows retain zero full catalog snapshots on Show, a warm-open zero-work path, bounded 25-row source/join/copy units, at most 500 merge moves, and atomic publications/binds. Active Sync defers work and resumes once quiet. | Real open/filter/scroll timings remain unproved. |
| Wishlist, Panel, full boot, and storage | `PASS` | Full boot/polish, Panel/Wishlist paths, Store migrations, reload-safe state, saved-loadout actions, malformed reads, and 70-check integration all pass in the complete suite. | Startup, reload, migration backup, and unknown live addon interactions remain unproved. |
| Sync, DPS, Peer Test, and wire ownership | `PASS` | Isolation, current/legacy compatibility, hostile input, queue/ownership/tombstone/convergence, DPS, bounded Peer Test, and StutterAlert provider suites pass. No wire or storage contract was changed by Stage 25. | Stage 24 two-user convergence remains unproved. |
| Diagnostics and privacy | `PASS` | Fixed 15-phase/15-context/six-projection snapshots, eight action counters, bounded recent-operation storage, defensive copies, and aggregate-only generated fixtures pass. Scoped identity/path/raw-log scan has zero hits. | A bounded live export still needs to be captured from a separately authorized build. |

No unresolved offline major or moderate finding remains. `PASS` means the
deterministic source boundary passed; it does not promote any live claim.

## Validation receipts

- Complete Lua suite: `156/156 PASS`, `0 FAIL` (Stage 24 baseline was
  `153/153`).
- Lua 5.1 source/test parse: `222/222 PASS`, `0 FAIL` (Stage 24 baseline was
  `219/219`).
- Integration: `70/70 PASS`.
- Module contract: 10 modules, 183 public surfaces, 13 assigned members, 152
  callback sites, 17 callback groups, zero unmapped symbols.
- Deterministic bundled-build exporter: `PASS`.
- Generated read-only SavedVariables analyzer fixture: `PASS`.
- StutterAlert registration, correlation, bounds, failure, and session-only
  storage: `PASS`.
- Stage 25 range `git diff --check`: `PASS`.
- Stage 25 scoped privacy scan: zero hits.
- Stage 25 artifact/log additions: zero.
- Product worktree status before this audit record: clean.

No expected-red, skipped, unavailable, malformed-command, or failing result is
included in those totals. Offline elapsed times are supporting evidence only;
the deterministic operation, mutation, transition, and retained-reference
counts above are the acceptance boundary.

## Package-source check without an artifact

The read-only manifest comparison found 62 Lua entries in `Nexus.toc`: every
entry exists with exact path casing, there are zero missing entries and zero
duplicates, and all five Stage 25 runtime files are listed. There are 63 Lua
files under `data`, `logic`, `core`, and `ui`; the sole unlisted file is the
pre-existing, unchanged `logic/Relay.lua`, which is test/reference-only and has
never been loaded by the product TOC. Stage 25 neither changed nor relied on it
as packaged runtime code.

This check deliberately did not create a staging directory or ZIP and did not
compare Stage 25 bytes to test.9, because test.9 is correctly pinned to the
older Stage 24.8 source.

## Exact Stage 25 file scope

The source range before this audit record changes:

```text
core/AutomationRuntime.lua
core/GameAdapter.lua
core/Main.lua
core/Performance.lua
docs/MODULAR_REFACTOR_CHARACTERIZATION.md
tests/module_contract_manifest.lua
tests/run_module_contract_characterization.lua
tests/run_performance_diagnostics.lua
tests/run_stage25_action_lifecycle.lua
tests/run_stage25_echo_rolling_characterization.lua
tests/run_stage25_overlay_memory.lua
ui/WishlistOverlay.lua
```

This final audit record is the only additional Stage 25 file.

## Fixed offline

- Board-only changes no longer reacquire unchanged slot, owned, locked, lever,
  catalog, Wishlist, or compiled-plan projections.
- Duplicate board notifications settle without another decision or render.
- Accepted/rejected chat and Sync activity remains isolated from automation.
- Matching fallback checks are cheap; a missed semantic change repairs only
  its component once.
- Each mutation is owned by one immutable board intent, re-reads the board, and
  reauthorizes immediately before the GameAdapter call.
- Hidden and unchanged Wishlist overlay refreshes perform no acquisition or
  rendering work; presentation retention is fixed-size.
- A known absent Wishlist is now cached through Panel preparation and run-start
  audit metadata instead of walking all saved loadouts on every board.
- Model/Policy/Ratchet/GameAdapter ownership, sole GameAdapter service I/O,
  policy/scoring semantics, the direct 0.2-second safety tick, the five-second
  fallback, SavedVariables, Sync wire/ownership/tombstones/queues/convergence,
  and complete uncapped storage remain intact.

## Still live-unproven

- Corrected in-game `automation.step` and `automation.update` frame time during
  real Echo rolling.
- Constant per-frame cost, memory high-water, retained UI memory, garbage
  collection, and long-session behavior.
- Rolling while real Sync is quiet versus receiving, including coincident
  channel/combat/event bursts.
- Real freeze, reroll, banish, select, save, delayed-confirmation, and
  missing-confirmation server behavior.
- Community/Leaderboard/overlay shown and hidden timings in WoW.
- Startup, reload, disconnect/reconnect, throttle, migration backup, and crash
  attribution.
- Stage 24 build/Share/DPS convergence between two byte-matched clients.

## Separately authorized combined live procedure

Do not run these steps until one ordinary unpublished artifact is separately
authorized from the final clean Stage 25 source.

1. Create one artifact from the reviewed commit, record source commit, manifest
   count, size, and SHA-256, then independently verify the same bytes for both
   clients. Stop on any mismatch. Preserve test.8 and test.9 unchanged.
2. Back up both clients' addon and SavedVariables according to the agreed live
   protocol, install only the byte-matched artifact, reload, and verify the
   same Nexus/protocol identity. Do not mix builds.
3. Enable and clear the bounded Nexus Peer Test and StutterAlert sessions on
   both clients. Capture baseline Sync state, queue depth, represented
   revisions/digests, Nexus memory, and bounded owner timings without sharing
   raw SavedVariables or general logs.
4. With Sync quiet, roll a controlled sequence of Echo boards. Exercise normal
   select plus safe freeze/reroll/banish paths if available, including one
   delayed or missing confirmation. Compare `automation.step`,
   `automation.update`, fallback, GameAdapter Poll, decision, action-lifecycle,
   overlay, memory, and hitch attribution against the historical test.8
   evidence.
5. Repeat controlled rolling while Sync is actively receiving. Vary Community
   and Leaderboard closed/open and Wishlist overlay hidden/visible. Confirm
   accepted/rejected/unrelated traffic does not create extra decisions/actions,
   no contradictory mutation occurs, and each visible surface remains usable.
6. On client A, perform one explicit direct Share to the nearby same-class
   client. Record local save, queue admission, send completion, receiver commit
   or exact bounded exclusion, then find it on client B with `All Shared`,
   `Current Class Only` disabled, and `Qualified Only` adjusted as needed.
7. Run the Stage 24 build convergence procedure from
   `docs/STAGE_24_FINAL_AUDIT.md`: invoke one controlled Sync, wait for quiet,
   compare bounded digests/revisions and Community projection, and do not call
   sender completion receiver success.
8. If a safe capture path is agreed, produce one controlled DPS change on
   client A, Sync again, wait for quiet on both clients, and confirm one
   requested/offered/accepted convergence plus one post-quiet Leaderboard
   publication. Skip rather than improvise an unsafe capture.
9. Verify Wishlist association/editor behavior, default Panel restoration,
   automation latches, SavedVariables/unknown-field preservation, reload, and
   session-only diagnostic expiry. Capture only bounded Peer Test, Nexus
   diagnostic, and StutterAlert summaries.
10. Pass only if byte identity matches, both Stage 24 convergence flows reach
    their receiver/projection states, rolling does not reproduce the historical
    Nexus stalls or duplicate/unauthorized actions, memory settles within the
    agreed bound, and the regression matrix remains intact. Otherwise preserve
    the bounded reports, restore backups if required, and return to offline
    diagnosis without publishing.

Stage 25 stops at this authorization gate. Offline PASS is not an in-game fix
claim, and this procedure is a proposal rather than permission to package or
deploy.
