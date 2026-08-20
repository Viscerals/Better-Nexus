# Stage 32 final source-only audit

Audit date: 2026-08-13

Verdict: **PASS OFFLINE / FORMAL REVIEW PASS - TEST.14 PACKAGING ONLY**

This audit is fail-closed. It proves deterministic source behavior, preserved
compatibility, and bounded offline work at one clean local head. It does not
claim live success, create or install an addon artifact, launch WoW, read or
change live SavedVariables, or authorize a push, merge, tag, release,
publication, licensing change, or remote action.

Historical test.5 through test.13 archives remain immutable. Test.13 remains
the failed live startup-and-behavior artifact for the defects repaired in this
stage. No test.14 archive exists at this audit boundary.

## Source boundary

- Branch: `codex/stutteralert-diagnostic-provider`.
- Stage 32 base: `171aa6f2ddfd429bebebd144d5cc75617c7ff4f8`.
- Audited implementation head before the original audit record:
  `87c0bd315a772f2399205fbced13c48f5cad4548`.
- Original audit-record commit:
  `ce0d135589b3b693579a18e4fbae644a92b9edc9`.
- Formal-review hardening source head before this reviewed audit update:
  `a656ea8bb25374b7cd173bfa46e463b080eb7fe9`.
- Stage 32 range before this reviewed audit update: 12 commits, 43 files,
  5,962 insertions, and 275 deletions.
- Public addon version: `1.20.0-beta.1`.
- Sync/DPS protocol: 7.
- TOC Author: `Valentine`.
- Upstream `UPSTREAM.md` SHA-256:
  `66FBE86742A58B738E8A701D6A81EAD8DEE97994F34C3C1A9DD508564B1B3F89`.
- Product worktree before this audit record: clean.

Stage 32 commits before this reviewed audit update, in order:

1. `0608f90d7c4430fb1c5d58e51085535538739b8e` - characterize legacy
   qualification identity.
2. `61028b2c3002d7e34f01c0d92fd0ed124c1dd52d` - repair legacy
   qualification identity.
3. `212478dd684c00744eb61386690ee61afe8f53f4` - harden legacy repair
   validation.
4. `c073fc775571693f9c3af9285054bca5c9b9eb17` - repair responsive Nexus
   layouts.
5. `ee71ba5ba11bf63e17d89fcbee5abdff43fddc46` - contain responsive layout
   faults.
6. `0fe7b37e8c1a14ebcfea23f06280059021e1af44` - preserve Leaderboard
   locked evidence.
7. `cbb881ee96bbf32643e0db354db30b04dccf1c76` - bound AutoLock
   confirmation.
8. `de1585a8f6f29046ec178392f118569af835406e` - characterize responsive UI
   work.
9. `4ff6007906d89c39d67763208ec626e28f574750` - harden the hidden UI work
   budget.
10. `87c0bd315a772f2399205fbced13c48f5cad4548` - reject malformed
    persisted AutoLock state.
11. `ce0d135589b3b693579a18e4fbae644a92b9edc9` - record the final
    source-only audit.
12. `a656ea8bb25374b7cd173bfa46e463b080eb7fe9` - harden persisted
    AutoLock identity and retry-deadline validation during formal review.

## Final adversarial verdict matrix

| Boundary | Offline verdict | Deterministic evidence | Remaining live limit |
| --- | --- | --- | --- |
| Legacy qualification and identity recovery | `PASS` | Ten bounded reason states pass without mutation. One realistic run recovers 225 exact historical identities, reuses 316 cumulative identities, rejects 14 cumulative candidates across restart passes, performs at most 25 work units per pump, resumes twice, and publishes exactly once. | The owner's real legacy records have not been migrated by this source in WoW. |
| Collision, ownership, and storage safety | `PASS` | Current colliding builds, tombstones, associations, evidence pools, unknown fields, and DPS rows remain unchanged. Recovered records use separate deterministic IDs, exact full fingerprints, and no `ownerKey`, `isMine`, `ownerVerified`, edit, delete, tombstone, or relay authority. | Live backup/reload and unknown-addon interaction remain unproved. |
| Responsive HUD and Community Builds layout | `PASS` | The pure matrix passes 1,150 checks across 32 Panel and 24 Community cases; the assembled UI passes 108 checks. Cached Nexus-owned geometry preserves aligned hit regions, fixed pools, default-scale behavior, and last-valid layout on faults. | Exact in-game appearance at the owner's font/UI settings remains unproved. |
| Leaderboard locked-evidence fidelity | `PASS` | The former inferred set `201382,201398,201410,210075,210076,210077` is replaced by exact displayed/editor/committed parity at `201382,201388,201398,201410,201416,201420`. The 40-check fixture rejects 89 ordinary copies, accepts exactly 79 ordinary plus six typed locked targets, and preserves overlap and confirmation identity. | The same copy/confirm flow has not been repeated in test.14 in WoW. |
| AutoLock submission and confirmation | `PASS` | The 63-check fixture makes four adapter calls total and records `prepared=4`, `submitted=3`, `awaiting=3`, `confirmed=2`, `rejected=1`, `expired=1`, `superseded=4`, and `postExpiryBlocked=3`. Adapter acceptance remains pending until authoritative locked evidence; capacity is read as `1/3`; immediate authorization and destructive-unlock guards remain intact. | Live server acknowledgement timing and every safe replacement path remain unproved. |
| Malformed persisted AutoLock state | `PASS` | Implementation expected red was `malformed AutoLock record key was normalized or deleted`; formal-review expected red was `malformed AutoLock identity was normalized or deleted`. Key/base-key/descriptor/identity mismatch, non-finite or impossible lifecycle times, impossible attempt counts, malformed retry state or deadline, and non-scalar diagnostics now fail closed before pruning or submission while unknown fields remain untouched. | Corrupt real SavedVariables were not created or edited for testing. |
| UI work and Stage 25 performance preservation | `PASS` | At 1,000 builds and 500 DPS rows, 25 unchanged visible ticks, 50 hidden ticks, and 100 identical Panel renders add zero geometry, projection, tree, row-bind, frame, or card churn. One revision recomputes once; totals are four layout computations, 64 frames, four cards, and bounded `119/119` scalar scale probes. The 200-board Stage 25 fixture retains zero repeated slot/owned/locked/lever/catalog/Wishlist traversal on warm paths. | The supplied 37-hitch/154-ms/101.6-MB observations remain uncorrelated and unassigned. |
| Stage 26/28/30 and Sync isolation | `PASS` | The focused matrix preserves request/session bounds, DPS duration rules, responsive views, descriptions, Wishlist transitions, persisted publication, exact Share identity, ownership, tombstones, wire compatibility, and storage. Fifty accepted Sync updates cause zero automation full step, policy, render, association, upload, or mutation work. | Exact same-build two-user convergence remains unproved. |
| Lua/WoW compatibility and boot | `PASS` | All source/test Lua parses as Lua 5.1. The 60-pass/61-fail boundary covers every TOC-loaded function; `ui/Panel.lua:353 EnsureFrame=60`, `AutomationRuntime.Step=16`. Full boot loads 65 TOC Lua files, registers the AutomationRuntime factory, polls twice, shows the startup banner, and records no suppressed error. | A real WoW 3.3.5a startup is still required for test.14. |
| Metadata, privacy, attribution, and artifacts | `PASS` | Public version/protocol/Author and upstream attribution are exact. Added-line privacy, dynamic-compilation, environment-hack, stale-marker, exporter, analyzer, inventory, and historical-hash gates pass. Test.14 count is zero. | Release/publication and live verification remain separate gates. |

No unresolved offline blocker, major finding, or active issue remains. `PASS`
means the deterministic source boundary passed; it does not promote a live or
release claim.

## Legacy recovery receipts

The pure classifier reports exactly these ten fixed scalar outcomes:

```text
no-catalog
no-dps
one-category
duration-or-category
exact-current
recoverable-history
build-id-collision
insufficient-evidence
unauthorized-owner
stale-or-superseded
```

The realistic first repair pass records:

- recoverable/recovered: 225/225;
- rejected: 7;
- deferred one-category: 1;
- deferred duration-or-category: 1;
- deferred build-ID collision: 1;
- deferred insufficient evidence: 2;
- deferred unauthorized owner: 1;
- deferred stale/superseded: 1;
- build publications: 1;
- maximum work per pump: 25;
- result pages: 20 plus 5.

After two intentional restart paths, cumulative diagnostics report 225
recovered, 316 reused, 14 rejected, two restarts, and still one publication.
Repeated login, refresh, import, migration, and Sync requests are idempotent.
The repair does not copy the complete catalog and recovered unverified records
do not enter Sync deltas or relay preparation.

## Locked evidence and AutoLock receipts

- Displayed, editor-previewed, and committed locked IDs are identical:
  `201382,201388,201398,201410,201416,201420`.
- Ambiguous 89-copy ordinary evidence remains visible and non-actionable.
- Exact 79 ordinary entries plus six explicit locked entries remains valid.
- Copy and cancel perform zero upload, association, gameplay, catalog, or
  SavedVariables mutation; one fresh confirmed save performs one authorized
  79-copy upload and association.
- Candidate, projection, editor, popup, destination, and retry drift fail
  closed before mutation.
- AutoLock performs four calls across three submitted lifetimes. One bounded
  spacing retry and one explicit retry do not extend or reset the original
  lifetime; three post-expiry pumps remain blocked.
- Formal review proves stale records with inconsistent identity, descriptor,
  or retry deadlines remain unchanged with zero adapter calls; a legitimate
  client-clock reset keeps its finite pre-reload lifetime semantics.
- A client-clock reset, unrelated dirtiness, reload-equivalent state, malformed
  current-schema state, future-schema state, missing capacity, and unsynced
  locked evidence all fail closed.
- The direct 0.2-second owner, five-second fallback, immediate pre-action
  authorization, immutable action intents, decision/latch/guarantee/forced
  selection/save-verification/runtime-demotion/deadline behavior remain exact.

## Layout and work receipts

- Pure responsive geometry: 1,150 checks; Panel cases 32; Community cases 24.
- Real UI consumers: 108 checks; four narrow cases, one wide case, four cards.
- Realistic work fixture: 1,000 builds, 500 DPS rows, 25 unchanged visible
  ticks, 50 hidden ticks, 100 identical Panel renders.
- Warm/hidden new geometry, projection, sort, defensive copy, acquisition,
  publication, row bind, frame/card, and theme-tree work: zero.
- One font/layout revision: one bounded computation; next identical refresh:
  zero additional geometry/tree allocation.
- Final responsive counters: four layout computations, 64 frames, four cards,
  and `119/119` constant-size font/UI-scale probes.
- Community refresh: 1,000 rows, 500 DPS rows, zero identity lookups, 500
  indexed rows, one deferred publication, three periodic skips.
- Stage 25 Echo rolling: 200 boards, 200 decisions, 600 cards, zero static
  probes/compiles and zero repeated slot/owned/locked/lever or all-surface
  Wishlist traversal; 20 duplicate Shows perform zero full steps, decisions,
  renders, or slot work.
- Stage 25 overlay: 809 refreshes, 400 hidden skips, 401 revision skips, eight
  builds, one identical model, 267 row updates, one style pass, four frames,
  and 90 fixed cached lines.

Offline work counts do not establish in-game frame time, garbage-collection
behavior, memory high-water, or hitch causation.

## Validation receipts

### Focused matrix

- Stage 32 oracles: `7/7 PASS`.
- Direct Stage 21/23/24/25/26/28/30, storage, ownership, wire, StutterAlert,
  and integration regressions: `64/64 PASS`.
- Combined focused result: `71/71 PASS`, `0 FAIL`.
- AutoLock implementation repair-focused result: `14/14 PASS`.
- AutoLock formal-review fixture: `63 checks PASS`, with the same four adapter
  calls and lifecycle totals.

### Complete gates

- Complete Lua suite: `178/178 PASS`, `0 FAIL`.
- Lua 5.1 source/test parse: `878/878 PASS`, `0 FAIL`.
- TOC upvalue gate: 65 files, 2,689 functions, zero above 60.
- Maximum: `ui/Panel.lua:353 EnsureFrame=60`.
- `AutomationRuntime.Step=16`.
- Boundary fixture: 60 upvalues passes; 61 fails.
- Automation boot: 65 TOC files, one factory registration, two polls, startup
  banner present, no error.
- Integration: `70/70 PASS`, `0 FAIL`.
- Sync compatibility stress: `4,000/4,000 PASS`.
- Module inventory: 10 modules, 188 public surfaces, 14 assigned members, 155
  callback sites, 17 groups, zero unmapped.
- Deterministic bundled-build exporter: `PASS`.
- Read-only SavedVariables analyzer: `PASS`.
- Package metadata and attribution: `PASS`.
- StutterAlert provider registration, bounds, failure isolation, and
  session-only storage: `PASS`.
- Stage 32 added-line private sentinel scan: zero hits.
- Product added-line dynamic compilation/environment hacks: zero.
- Product added-line `TODO`/`FIXME`/`HACK` markers: zero.
- Stage 32 range and all twelve pre-update commits `git diff/show --check`:
  `PASS`.
- Historical test.5-test.13 hashes: `9/9 PASS`.
- Test.14 ZIP count: zero.
- Product status before this reviewed audit update: clean.

No expected-red, skipped, unavailable, malformed-command, or failing result is
included in these green totals. The discarded pre-repair matrix is not counted
as final evidence.

## Package-source check without an artifact

`Nexus.toc` lists 65 unique Lua files. All 65 exist with exact path casing;
there are zero missing or duplicate entries. The source runtime directories
contain 66 Lua files; the sole unlisted file is the pre-existing unchanged
`logic/Relay.lua`, retained as a test/reference-only surface. Both new Stage 32
runtime modules are TOC-loaded in dependency order.

No staging directory or ZIP was created. Source/package byte parity, packaged
Lua parsing, archive CRC/path safety, runtime label injection, archive size,
and test.14 SHA-256 therefore remain `N/A` until checkpoint 32.8 is separately
dispatched after formal review.

## Historical artifact hashes

| Artifact | SHA-256 |
| --- | --- |
| test.5 | `C666E38232F540298F51657F22E2E2488F93B1F3D2532098E3C328307B8B58EE` |
| test.6 | `57285B97737E651229163CA3CE8421A19DF52FA14ED5A39A515B851FE8828653` |
| test.7 | `EC86D1598BE5584A856F5391F8ABA2F45FE4E9BD30894C88CC145DB1E5D1F301` |
| test.8 | `FE4055316B7E6CF7807343CA1D611054702F45184D3A16E79CF93C50A7DE4D00` |
| test.9 | `C64060C2DDD7BAB582F32AA4E82AE64CE03BEE71C05BAE4F045F8B103DAFFB37` |
| test.10 | `ECB38203E4F76F1E61D7270C710B77B85945E072F5944E91133B2B6B955F9DAB` |
| test.11 | `CFD1041A525D261956AE648D49F2010E9A6E90670DF3B963504FD6D292782459` |
| test.12 | `87A9BFF25576BB422B6516709AFF5A7B9B4E00468ABDF14DE662096D237C8E71` |
| test.13 | `0A9081A5B3DA23FC6AD11A5E2B98832AFEE07A70C1960099B578C18C54983404` |

## Exact Stage 32 file scope at formal review

```text
Nexus.toc
core/AutomationRuntime.lua
core/BuildCatalog.lua
core/DpsCapture.lua
core/GameAdapter.lua
core/LegacyQualificationRepair.lua
core/Main.lua
core/MainLifecycle.lua
core/Sync.lua
core/ViewProjections.lua
core/ViewRefresh.lua
core/WishlistController.lua
core/WishlistModel.lua
docs/MODULAR_REFACTOR_CHARACTERIZATION.md
docs/STAGE_32_FINAL_AUDIT.md
tests/harness.lua
tests/module_contract_manifest.lua
tests/run-bundled-build-export.js
tests/run-upvalue-compatibility.js
tests/run_automation_runtime_boot.lua
tests/run_dps_boards.lua
tests/run_gameadapter_contract_characterization.lua
tests/run_leaderboard_virtualization.lua
tests/run_main_contract_characterization.lua
tests/run_module_contract_characterization.lua
tests/run_panel_adaptive_states.lua
tests/run_stage32_autolock_confirmation.lua
tests/run_stage32_layout_work_budget.lua
tests/run_stage32_leaderboard_locked_fidelity.lua
tests/run_stage32_legacy_qualification_characterization.lua
tests/run_stage32_legacy_qualification_repair.lua
tests/run_stage32_responsive_layout.lua
tests/run_stage32_responsive_ui.lua
tests/run_view_projections.lua
tests/run_wishlist_editor.lua
tests/run_wishlist_model_parity.lua
tools/export-bundled-builds.js
ui/CommunityRenderer.lua
ui/LayoutMetrics.lua
ui/Leaderboard.lua
ui/Panel.lua
ui/WishlistEditor.lua
ui/WishlistRenderer.lua
```

This is the exact 43-path reviewed scope. Formal-review hardening touched only
the existing `core/AutomationRuntime.lua` and
`tests/run_stage32_autolock_confirmation.lua` paths.

## Fixed offline

- Exact historical loadouts can qualify through separate deterministic
  identities without rewriting current collisions or granting authority.
- The HUD and Community Builds page use bounded revision-keyed responsive
  geometry with fixed pools, aligned hit regions, and retained last-valid
  state.
- Leaderboard display, editor preview, and confirmed save preserve separate
  ordinary and locked evidence and the same exact six locked IDs.
- AutoLock distinguishes submission from authoritative confirmation, bounds
  retries and expiry, preserves lifetime across unrelated work/reload, and
  fails closed on absent capacity/evidence or malformed persisted records.
- Warm and hidden UI paths retain Stage 25 coalescing, projections, immutable
  intents, bounded fallback, and fixed presentation state.
- Stage 26 Sync/DPS/UI/diagnostic/wire/ownership/tombstone/storage behavior and
  Stage 30 persisted views, descriptions, Wishlist transitions, Share identity,
  and bounded diagnostics remain green.

## Still live-unproven

- Installation and startup of a future exact test.14 ZIP on either computer.
- Exact same-ZIP two-user Share and complete Sync convergence.
- Qualified legacy Community results on the owner's real stored data.
- HUD and Community Builds appearance at normal and enlarged live settings.
- Leaderboard locked-set Copy, explicit confirmation, and committed parity in
  WoW.
- Real LockPerk acknowledgement, timeout, replacement, and expiry behavior.
- Echo rolling, combat, leveling, ordinary Auto behavior, frame time, memory
  high-water, garbage collection, and StutterAlert attribution.
- Project Ebonhold Orb of Lost Memories behavior until authoritative API,
  event, and roll-context evidence exists through GameAdapter.
- Mixed-version transport behavior outside existing deterministic compatibility
  coverage.

Checkpoint 32.7 formal review passes at the exact source boundary above.
Checkpoint 32.8 may now create exactly one unpublished test.14 package and its
eleven-step checklist. Installation and live execution remain separate gates;
this audit update creates no artifact and authorizes no live or remote action.
