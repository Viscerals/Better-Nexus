# Better-Nexus modular-refactor contract audit

This audit is fail-closed. It separates source/offline proof from behavior that
still requires a controlled WoW session. It does not authorize a build,
deployment, release, merge, or remote change.

## Audited snapshot

- Worktree: `.pr6-stage9-worktree`
- Branch: `agent/modular-refactor`
- Initial audit head: `49cdfc2f356452e91faf3faca59cb0e830022645`
- Corrected product head: `2345cfc` (native repair `bb55b12` plus adversarial
  admission hardening)
- Final Stage 16 review head: `0de6fd5e500ab6a8614c03b04c6594a95f9e7a6d`
- Source identity: `1.20.0-beta.1`, unpublished
- Installed addon identity observed read-only during the Stage 17 preflight:
  `1.20.0-beta.1-modular-refactor-test.2`
- The installed addon and test.2 package contain the exact `0de6fd5` runtime:
  61/61 manifest files match, with zero byte mismatches and zero normalized
  version mismatches. The package SHA-256 is
  `67CB06A12DD6B2A1543156FF6A04C08DAA28E53908889A9C6A19C54042C3E182`.

Initial verdict at `49cdfc2`: **BLOCKED**. The reviewed Stage 16 Community and
runtime work was present, but three historical Wishlist safety paths and their
exact regression coverage were absent. `fd21f27` and `2b3fe6d` are not
ancestors of this branch.

Corrected offline verdict at `2345cfc`: **PASS WITH LIVE DEFERRALS**. ISSUE-140
restores equivalent behavior natively inside the extracted Wishlist owners and
the review hardening keeps immutable admission inside the ordinary 79-copy
validation boundary.
No unresolved major or moderate source/offline contract finding remains; every
item marked `PARTIAL` or `NOT PROVEN` below is an explicitly deferred live or
unsupported-mode claim, not an offline pass claim.

Post-audit test.2 verdict: **FAILED LIVE PERFORMANCE VALIDATION**. The
source-matched diagnostic recorded no Lua errors, but `automation.step` reached
530.581 ms, `community.refresh` reached 1720.044 ms, and
`leaderboard.refresh` reached 501.528 ms. `gameadapter.poll` reached only
0.121 ms, `sync.update` 18.245 ms, and `sync.incoming` 17.303 ms, so transport
and direct polling are not the measured multi-second owners in this capture.
StutterAlert spans test.1 and test.2 sessions, so its aggregate hitch history is
supporting context rather than exact per-build attribution.

Status meanings:

- `PASS`: source ownership and meaningful offline regression evidence agree.
- `FAIL`: the current source still admits the historical failure or lacks a
  required frozen behavior.
- `PARTIAL`: offline behavior is protected, but a required live/UI/performance
  claim remains unverified.
- `NOT PROVEN`: the requested behavior cannot be established from this source
  and offline evidence.

## Regression matrix

| ID | Status and classification | Current implementation and evidence | Can the historical failure still occur? | Impact and smallest future correction |
| --- | --- | --- | --- | --- |
| NXR-01 | `PARTIAL` - known regression protected offline; live UI risk | `ui/WishlistRenderer.lua:331-353` shows the unassociated editor; `ui/WishlistEditor.lua:284-349` owns open/show/refresh/toggle. `tests/run_wishlist_editor.lua:80-118`, `tests/run_wishlist_contract_characterization.lua:81-125`, and `tests/run_wishlist_facade_parity.lua:1-251` protect visible creation, stable frames, and failure isolation. | The original hidden unassociated-editor path is not reachable in the harness. Menu restoration and repeated real-frame lifecycle remain unproven in WoW. | Moderate user impact if live frame/menu behavior differs. Perform the explicit linked/unlinked/failure/cancel/reopen live matrix before release. |
| NXR-02 | `PASS` - historical zero-slot regression restored | `core/WishlistController.lua:543-570` routes only active slots 1-5 through strict `SetLoadoutWishlist` and routes exactly `activeSlot=0` through `SetFirstRunWishlist`; `core/GameAdapter.lua:983-997` owns that first-run write, while `1086-1112` retains populated numbered-slot validation. `tests/run_wishlist_first_run_assignment.lua:27-91` covers level 80 and level 20 zero-slot selection, one-time promotion, empty/out-of-range refusal, one stored identity, and multi-identity ambiguity. | No in the exercised real-module path. Invalid nonzero active slots and empty/out-of-range numbered slots still fail closed. | Major if regressed. Preserve the controller routing split and exact first-run fixture. |
| NXR-03 | `PASS` - rendered-candidate identity is mutation input | `ui/WishlistRenderer.lua:1454-1496` passes the captured candidate to `core/WishlistController.lua:543-565`, which passes it unchanged to the adapter. `core/GameAdapter.lua:831-864` validates positive integer slot, total-copy budget, canonical key, and immutable payload; it follows the same live key across safe move/rename, rejects same-slot recycled content, and admits an absent already-rendered identity without a second fragile lookup. `tests/run_wishlist_candidate_churn.lua:27-113` covers disappearance, recycling, move/rename, malformed identity, nonpositive/fractional slots, over/exact budget, prior-state preservation, and duplicate names. | No in the exercised churn matrix. A changed identity at the same slot is explicitly refused instead of guessed. | Major if regressed. Keep immutable candidate validation at the GameAdapter mutation boundary. |
| NXR-04 | `PASS` - transient reads are non-destructive | `core/GameAdapter.lua:657-750` validates and bounds stored payloads to 79 total Echo copies; `861-935` retains association records and returns only an already-associated immutable fallback when live rows are absent. Explicit set/clear paths remain authoritative at `979-1124`. `tests/run_snapshot_wishlist_association.lua:42-82` proves the exact record table and an unknown future field survive nil, empty, partial, full, and repeated Store initialization. | No in the exercised eventually-consistent snapshot sequences. No read path clears the stored link. | Major if regressed. Keep reads non-destructive and bounded; clear only on explicit user mutation. |
| NXR-05 | `PASS` - exact regression coverage present | The real Store/GameAdapter/WishlistModel/WishlistController stack is exercised by `run_wishlist_first_run_assignment.lua` and `run_wishlist_candidate_churn.lua`; `run_snapshot_wishlist_association.lua` covers persistence sequences and unknown-field/table identity. Stage 15 facade/model/controller/renderer contracts also remain green. | The formerly uncovered NXR-02 through NXR-04 paths now have direct negative and positive fixtures. | Major if coverage is removed. Keep all three fixtures in the complete suite. |
| NXR-06 | `PARTIAL` - unproven live-runtime risk | `core/BuildCatalog.lua:356-520` owns bounded catalog initialization/summaries/count; `core/SyncReconciler.lua:221-283` plans delta/compatibility buckets; exact loadouts remain on demand through `core/Sync.lua:754-762`. `tests/run_startup_catalog_cost.lua:20-114`, `run_sync_baseline_delta.lua`, `run_sync_cold_start_complete.lua`, and `run_full_boot_polish.lua` pass. | Offline counters do not show the former full-baseline startup path. Startup freeze/crash behavior with real channels, 9 MB data, upgrades, reconnects, and `/reload` is still not proven. | High practical impact if live startup regresses. Use a controlled source-matched test build and before/after in-game trace; do not infer crash causality from offline success. |
| NXR-07 | `PARTIAL` - backpressure contract passes; live frame time unproven | `core/SyncTransport.lua:60-126` checks capacity and admits batches atomically. `core/SyncReconciler.lua:390-488` cheap-yields while backpressured and selects one fair unit per update; `294-300` supplies absolute expiry; claims follow admission at `328-358` and `462-482`. `run_sync_transport_owner.lua`, `run_sync_response_backpressure.lua`, `run_sync_transport_safety.lua`, and `run_sync_reconciler_parity.lua` pass, including 8190/8192 saturation. | The pre-admission rebuild/retry multiplier is blocked offline. A real WoW frame-time ceiling is not proven because admitted serialization and final send work remain synchronous units. | High live impact if one admitted unit is still expensive. Retain current transport behavior unless a source-matched live trace identifies the measured owner path. |
| NXR-08 | `PASS` - historical Sync safety/durability contract | Public facade remains at `core/Sync.lua:34` and `240-1668`; protocol validation is isolated in `core/SyncProtocol.lua` and `core/SyncInbound.lua`; durable admission is isolated in `core/SyncTransport.lua:48-137`; compatibility/candidate snapshots are isolated in `core/SyncCompatibility.lua`; reconciliation is isolated in `core/SyncReconciler.lua`. Sync facade, protocol, compatibility, canonical hash, delta, owner, tombstone, transport, safety, hostile-input, and convergence suites all pass. | No source/offline evidence of wire, canonical-hash, ownership, tombstone, queue, or convergence regression. Real channel reconnection remains part of live verification, not a claimed offline result. | High if regressed, but no current offline defect. Keep protocol-sensitive details internal and run mixed-version live convergence before publication. |
| NXR-09 | `PASS` - Community qualification is truthful and optional | `DpsCapture` builds one finite-positive exact-fingerprint Dummy/LK intersection per represented revision. `ViewProjections` keeps dual-positive qualification on by default, while an explicit `Qualified Only` opt-out retains one-sided and no-record synchronized builds with an `Unqualified` marker. Community eligibility, projection-contract, and Stage 24 characterization suites cover exact collisions, partial rows, revision reuse, and the 35-row complete-catalog path. | No in the exercised real-module path. | High discoverability impact if regressed. Preserve exact full-fingerprint joins, truthful qualification markers, and the default restriction. |
| NXR-10 | `PASS` - Community class scope is additive | The current character class remains the persistent default and still fails closed while the class token is unavailable. The explicit `Current Class Only` opt-out admits all classes, renders missing class data as `Unknown`, preserves unrelated filter fields, and can be used during a temporary class-token loss. Community contract, sort/filter, renderer, and Stage 24 characterization suites pass. | No in the exercised path. Leaderboard keeps its independent class filter. | Moderate if regressed. Preserve the default, explicit opt-out, unknown-class label, and recovery publication test. |
| NXR-11 | `PASS OFFLINE / LIVE RETEST REQUIRED` - Community construction and paging are resumable | `BuildCatalog.BeginSummaryCursor/SummaryCursorNext`, the revision-stable DPS eligibility cursor, and `ViewProjections.RequestBuilds/PumpBuilds` advance at most 25 source rows, 500 comparisons, and 500 merge moves per pump. One complete filtered/sorted query is cached, while 20-row page changes slice that cache without a catalog/DPS walk, re-sort, or revision change. `CommunityRenderer` keeps a fixed card pool, pauses pumps during active Sync, and binds once after atomic publication. Work-budget suites cover 1,000 builds and 1,200 DPS rows. | The source path no longer performs a full catalog/eligibility/sort/copy operation in one UI callback. Real WoW frame time remains unverified. | High live impact if one per-row unit is unexpectedly expensive in WoW. Retest the same source-matched live scenario and page controls before release. |
| NXR-12 | `PARTIAL` - bounded pools pass; live retained memory unproven | `ui/VirtualList.lua:15-44` bounds visible windows. Community pools are owned at `ui/CommunityRenderer.lua:1062-1238` and bound at `1864-2043`; Leaderboard pools are owned at `ui/Leaderboard.lua:13-27`, `174-190`, and `356-418`; Wishlist uses fixed pools verified by `tests/run_wishlist_renderer_parity.lua:101-190`. Community creates at most seven cards in the 1,000-row virtualization fixture and returns only 20 public rows. | One-frame-per-catalog-entry allocation is blocked offline. Actual WoW allocator/texture high-water and long-session retention remain unproven. | Moderate/high memory and stutter impact. Capture in-game high-water counts and memory after repeated open/filter/scroll cycles. |
| NXR-13 | `PASS OFFLINE / LIVE RETEST REQUIRED` - Leaderboard construction is resumable | The DPS board cursor, `ViewProjections.RequestLeaderboard/PumpLeaderboard`, bounded joins, and a bottom-up merge pass capped at 500 comparisons and 500 row moves per pump replace the dirty full-board read/join/sort/copy callback. The UI receives the immutable last-good ranking and its incrementally built selection index without a final full defensive copy, then binds only the visible pool once. The 600-row combined ranking in `run_live_projection_work_budget.lua` and existing ranking/virtualization suites remain green. | The source path no longer performs a complete board acquisition, ranking, copy, selection scan, or row bind in one callback. Real WoW frame time remains unverified. | High live impact if one row hydration is still costly. Retest Dummy, Lich King, and combined views live before release. |
| NXR-14 | `NOT PROVEN` - historical emergency-build behavior | Historical community-off/safe-mode commits `435ce26`, `a713dfb`, and `97cc6af` are not ancestors of this branch. The normal build initializes optional UI conditionally at `core/MainLifecycle.lua:92-103`, but there is no current supported Community-disabled product mode to audit end to end. | The historical emergency build behavior is not established in this source. This is not evidence that normal mode is broken. | A future emergency mode could expose incomplete facades. Decide explicitly whether it is a supported contract; if yes, implement complete inert facades and zero recurring work with boot tests instead of deleting modules. |
| NXR-15 | `PASS` - persistence/catalog migration contract | `core/Store.lua:98-154` binds/adopts/finishes the legacy decision; `177-188` preserves future versions; `192-235` orders owners. `Nexus.toc:7` retains both SavedVariables names. `core/BuildCatalog.lua:356-619` keeps baseline/overlay ownership. Store legacy, additive, contract, catalog migration, compaction, evidence, and analyzer suites pass. | No offline path overwrites current authority, unknown fields, future versions, builds, DPS, tombstones, diagnostics, or evidence. | Critical data impact if regressed. Keep dual declaration until a separate compatibility decision and require backup/live upgrade verification. |
| NXR-16 | `PASS OFFLINE / LIVE RETEST REQUIRED` - equivalent Echo replies are generation-coalesced | `GameAdapter.AutomationSignature` exposes semantic Echo generations plus bounded reference/scalar dependencies and the tome-safety probe. A hooked reply scans once, publishes only a complete validated snapshot, and marks dirty only for represented change; the fallback verifies every five seconds and repairs a missed signal once. The direct 0.2-second Poll performs no complete Echo scan unless a notification bit is pending. Fresh allocation/order churn, mixed changes, repeated notifications, malformed inputs, cache, dirty, parity, and the 70-check integration suite pass. | The source path no longer treats fresh raw Echo table identity as semantic change or enters a heavy pre-Policy step for an unchanged fallback. Real WoW timings remain unverified. | High live impact if canonical scanning or another client cost remains expensive. Compare the same automation and fallback metrics in unpublished test.4. |
| NXR-17 | `PASS` - modular ownership/public-contract audit | Facades remain `core/Sync.lua:34`, `core/Store.lua:9`, `core/GameAdapter.lua:12`, `ui/CommunityBuilds.lua:11`, and `ui/WishlistEditor.lua:7`. TOC order retains all extracted owners. `tests/run_module_contract_characterization.lua` reports 10 modules, 182 surfaces, 13 assigned members, 152 callback sites, 17 groups, and zero unmapped symbols. Sync/Community/Wishlist facade tests and GameAdapter static authority checks pass. | No duplicate transport, persistence, controller, renderer, or gameplay owner was found offline. | Critical architecture impact if regressed. Preserve one facade/one stateful owner and keep Project Ebonhold service I/O inside GameAdapter. |
| NXR-18 | `PARTIAL` - live performance owners confirmed; crash attribution unproven | `core/Performance.lua:13-30` defines bounded aggregate paths; `199-217` instruments complete public owners. Source-matched test.2 confirms the current performance owners are `automation.step`, `community.refresh`, and `leaderboard.refresh`; `gameadapter.poll`, `sync.update`, and `sync.incoming` are materially smaller, and the diagnostic recorded zero Lua errors. | The measured stalls are confirmed, but the evidence does not prove that any historical startup termination was a Nexus exception or that every hitch came from these owners. | High diagnostic/user impact. Keep crash and freeze claims separate, preserve bounded aggregate-only measurements, and compare the same owners on an unpublished corrected build. |

## Resolved blocking finding

ISSUE-140 is resolved by native modular repair commit `bb55b12` and review
hardening commit `2345cfc`; neither historical commit was merged wholesale. The
extracted controller owns zero-slot routing, the adapter owns bounded identity
validation and persistence, and the renderer remains presentation-only.
NXR-02 through NXR-05 now pass direct real-module fixtures without weakening
numbered-slot validation, the 79-copy budget, or stale same-slot/ambiguous
identity defenses.

## Remaining legacy and deferred live behavior

- Complete incoming Sync handling remains synchronous in the channel callback.
- One admitted Sync serialization unit remains synchronous; Community and
  Leaderboard construction is bounded offline, but that is not a formal live
  frame-time ceiling.
- Test.2 confirms the former final Community publication, Leaderboard
  construction, and unchanged five-second automation fallback exceeded the live
  frame budget. Stage 17 corrects those source paths offline; test.3 live
  verification remains required.
- `core/GameAdapter.lua` remains the intentionally sole, comparatively large
  Project Ebonhold I/O owner.
- The legacy `WishlistRealizerDB` TOC declaration remains intentionally loaded
  until a separate compatibility decision retires migration support.
- Community-disabled emergency behavior is not a supported, proven mode in this
  snapshot.
- Live startup, `/reload`, reconnect, channel throttle, 9 MB SavedVariables,
  migration backup, UI lifecycle, memory high-water, combat capture, corrected
  frame time, and crash attribution remain deferred pending a new authorized
  deployment. Test.2 is retained as failed live evidence, not rewritten as an
  offline pass.

## Final offline audit validation

- Historical Stage 16 final review at `0de6fd5` passed 10/10 high-risk suites,
  135/135 complete Lua suites, 198/198 Lua 5.1 parses, deterministic exporter,
  read-only analyzer, and exact-range diff checks before test.2 packaging.
- Stage 17 source-matched correction at `d87411f` passes 137/137 complete Lua
  suites, 200/200 Lua 5.1 parses, deterministic exporter, read-only analyzer,
  and exact-range/frozen-file diff checks. The product worktree is clean.
- The automation fixture records 500 direct polls across 20 unchanged fallback
  intervals, 20 cheap signature checks, zero repairs or pre-Policy/UI/action
  work, and one exact repair for a deliberately missed settings replacement.
  A fallback check coincident with board dirtiness also retains the admitted
  static catalog and Wishlist context.
- The 1,000-build/1,200-DPS fixture produces a complete uncapped 600-row
  combined Leaderboard. Per-pump maxima are 25 source rows, 25 joins, 25
  copies, 412 comparisons, and 500 merge moves; active-Sync and hidden work
  remains deferred and each completed view publishes/binds atomically once.
- Historical ancestry probe: `fd21f27=false`, `2b3fe6d=false`; Stage 9/16 Sync
  and Community performance commits `8773f26`, `362713d`, and `5cbe8ac` are
  ancestors. Equivalent Wishlist behavior is established by current source and
  the exact fixtures above, not ancestry.
- Offline PASS does not replace live verification. Test.2 remains the failed
  live-performance record; test.3 must be source-matched, user-deployed, and
  measured separately before any corrected frame-time or startup claim.
- No release, remote mutation, installed-addon change, deployment, or live
  SavedVariables write occurred during this audit.

## Stage 18 Echo-refresh addendum

- Test.3 live evidence superseded Stage 17's unchanged-fallback assumption:
  routine fresh Project Ebonhold Echo replies changed raw table identities and
  repeatedly escalated into automation repair/full-step work. Sync remained a
  negative owner in that capture and in the accepted-message offline control.
- Reviewed product head `1d75d39` replaces identity evidence with deterministic
  GameAdapter-owned semantic generations for slots, granted, locked,
  discovered/disabled Echoes, and active slot. Notifications coalesce behind
  one pending bit; complete scans occur only for a pending notification or the
  existing five-second self-healing check, never every ordinary Poll.
- Twenty shuffled fresh replies over 500 exact 0.2-second Polls produce zero
  generation mismatch, dirty flag, repair, full step, association refresh,
  Policy call, render, upload, action, or character mutation. Every represented
  genuine field change advances once, while one missed signal repairs once.
- Snapshot publication is atomic and fail-closed. Failing readers, missing
  required methods, invalid scalars/booleans, sparse arrays, conflicting locked
  aliases, cycles, and depth overflow retain every last-good generation and do
  no automation work. Supported flat, name-keyed, alternate-alias, and nested
  locked shapes remain equivalent.
- Fixed diagnostics expose five generation/field counters, two dirty counters,
  fixed fallback-mismatch and full-step-trigger maps, aggregate totals, and one
  bounded reason. Returned nested maps are defensive and repeated diagnostic
  reads do not influence scheduling, Policy, Sync, persistence, or UI work.
- Offline evidence does not prove corrected live frame time, startup behavior,
  Community interaction, reconnect/throttle behavior, migration backup, or
  `/reload`. Unpublished test.4 must be source-matched and user-deployed before
  any live-performance claim; this addendum authorizes no deployment or release.

## Stage 19 Builds-open and StutterAlert addendum

- StutterAlert provider results are always tables: unrelated, failed, and
  malformed internal captures become accepted empty results, while a correlated
  operation returns bounded context. The session ring remains fixed at 32
  entries, 15 seconds, and four fields, and is neither persisted nor populated
  by provider-time product work.
- Real `CommunityBuilds.Show()` coverage uses 1,000 builds, 500 DPS rows, three
  saved slots, cold and warm opens, and active-to-quiet Sync. Cold and warm
  opens perform zero `BuildCatalog.All` snapshots, complete catalog walks, or
  copies. Cold work advances at most 25 source/candidate units and 500
  comparisons per pump; the unchanged warm open performs no related lookup,
  saved write, revision, DPS join, projection rebuild/sort, frame creation, or
  publication.
- Related-build identity is revision-owned and narrow. Represented unlocked Echo
  rows override a stale stored fingerprint, while compacted fingerprint-only
  records retain their durable identity. Exact fingerprint, same-title, and
  full-subset matches preserve the established scorer without scanning unrelated
  authors or capping collision buckets.
- Saved reconciliation retains one last-good published view and restarts the
  complete pending job after represented catalog or GameAdapter slot-generation
  change. A temporarily unavailable fresh slot source restores the old job and
  remains pending; recovery restarts normally. The hostile fixture covers 80
  same-title collisions, stale preferred links/fingerprints, incremental index
  maintenance, unavailable-source recovery, two successful source restarts,
  and a maximum 25 candidates per pump with zero full reads.
- Active Sync performs no saved reconciliation, catalog traversal, DPS join,
  projection rebuild, or publication. Status remains responsive while receiving,
  then bounded work resumes and publishes once after quiet. Sync wire, hashes,
  handlers, queues, ownership, tombstones, retry/expiry, convergence, and
  GameAdapter I/O ownership are byte-unchanged by Stage 19.
- Exact reviewed runtime head `586019b` passes 143/143 complete Lua suites,
  208/208 Lua 5.1 source/test parses, deterministic bundled exporter, read-only
  SavedVariables analyzer, 180 module-contract surfaces, and Stage 19 diff
  checks. These offline results do not prove live frame time or that Sync caused
  any historical hitch.
- Unpublished test.6 may be packaged from the final clean audit commit after
  exact gates and normalized-byte verification. Packaging authorizes no install,
  deployment, release, push, merge, live SavedVariables write, or live-fixed
  claim; test.5 remains preserved as historical evidence.

## Stage 21 Wishlist evidence and Panel startup addendum

- Test.6 remains a failed live product artifact even though its short
  performance sample improved: a legitimate designed Wishlist reported
  `invalid wishlist`, and the default-visible Panel did not reliably return at
  startup. Stage 21 repairs only those characterized product paths; it does not
  convert the two-minute performance sub-result into final live proof.
- GameAdapter keeps the ordinary upload limit at 79 copies and admits up to six
  separately bounded locked targets only when complete authoritative lock flags
  are present. The stable Wishlist key is unchanged. Explicit associations
  preserve bounded Echo data plus additive `lockEvidenceVersion = 1`; legacy
  85-entry keys without that evidence stay pending until exact live content
  supplies it, with no guessed lock assignment or passive association rewrite.
- Controller, renderer, loadout Journal, and first-run Journal actions revalidate
  copied complete candidate snapshots. Exact-key moves/renames remain valid;
  recycled slots, forged keys, sparse arrays, malformed IDs/stacks, 80 ordinary
  copies, more than six locked targets, more than 85 total copies, and incomplete
  versioned evidence fail closed. Multiple legacy associations, pending relay
  identity, and unknown fields survive partial mirrors unchanged.
- Panel visibility intent is independent from frame materialization and temporary
  menu suppression. Changelog-before-first-render restores the default-visible
  Panel only after every Nexus menu closes, while explicit hide before or after
  first render and repeated menu transitions remain authoritative. No new
  SavedVariables or alternate navigation path was added.
- Exact reviewed runtime head `2e971c7` passes 146/146 complete Lua suites,
  211/211 Lua 5.1 source/test parses, deterministic bundled exporter, read-only
  SavedVariables analyzer, 180 module-contract surfaces, and Stage 21 diff
  checks. The unchanged fallback fixture performs 20 checks over 500 polls with
  zero repair, full-step, probe, association-refresh, upload, or mutation work.
- Unpublished test.7 may be packaged only from the final clean audit commit and
  must pass independent manifest, packaged-parse, normalized-byte, version-marker,
  source-commit, size, and SHA-256 verification. Packaging authorizes no install,
  deployment, release, push, merge, live SavedVariables mutation, or live-fixed
  claim; test.5 and test.6 remain preserved as historical artifacts.

## Stage 23 identity-only Wishlist and saved-import attribution addendum

- Test.7 remains a failed live product artifact. Source/package identity passed,
  but a legitimate 85-entry server Wishlist disappeared and seven Nexus hitches
  peaked at 402 ms. The historical 168.119 ms `community.saved-import` maximum
  identifies a correlation target, not a proven cause or phase owner.
- Missing raw lock fields now remain unavailable instead of becoming false.
  Identity-only candidates with at most 85 entries stay visible as awaiting lock
  evidence, retain stable keys and associations through move/rename, and cannot
  authorize upload, lock-in, first-run selection, editing, automation, or any
  character mutation. Exact authoritative 79-plus-six content promotes the same
  key without losing relay or unknown fields.
- Saved-import diagnostics are cumulative aggregate counters only. The scale
  fixture covers 568 builds, 595 DPS rows, 37,348 Echo rows, four saved slots,
  one 85-entry Wishlist, and active-to-quiet Sync. Cold work completes 197 work
  units over eight pumps with maxima of 25 work units and 25 candidates per
  pump, four saved-mirror writes, four incremental index updates, and one view
  publication; no full catalog read occurs.
- One active-Sync cycle is a zero-work deferral. A later catalog revision and an
  independent slot-generation change are attributed as separate source
  restarts, without claiming Sync performed the import work. Warm unchanged
  reconciliation performs zero catalog puts, writes, compactions, revisions,
  source restarts, or full reads.
- Checkpoint 23.4 is diagnostic-only. The covered fixture does not exhibit any
  allowed correction target: no full snapshot/copy per pump, self-write restart,
  whole-library index rebuild per finalize, unbounded pump, repeated warm work,
  or active-Sync publication. No speculative cadence, allocation, publication,
  Sync, persistence, or projection change is justified.
- Exact reviewed diagnostic head `341e29d` passes 148/148 complete Lua suites,
  213/213 Lua 5.1 source/test parses, focused Community, related-index,
  compaction, Wishlist, Sync-isolation, and full-boot controls. These offline
  results do not prove live frame-time ownership or a live performance fix.
- The final Stage 23 source audit classifies the result as `Wishlist repair +
  diagnostic`: every complete Lua suite and parse passes, the deterministic
  bundled exporter and read-only analyzer pass, and all 180 module-contract
  surfaces remain mapped. No skipped, unavailable, expected-red, or failing
  check is counted as passing.
- Any unpublished test.8 remains conditional on the final Stage 23 audit,
  deterministic exporter, read-only analyzer, module inventory, exact diff,
  independent archive verification, and clean source head. Packaging would
  authorize no install, deployment, release, push, merge, tag, rollback, live
  SavedVariables mutation, or live-fixed claim; test.5/test.6/test.7 remain
  preserved unchanged.
