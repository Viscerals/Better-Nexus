# Stage 35 test.15 failure source-only audit

Audit date: 2026-08-13

Verdict: **PASS OFFLINE / STOP BEFORE TEST.16 OR LIVE WORK**

This fail-closed audit covers the complete Stage 35 repair range. It does not
create or install test.16, launch WoW, read or edit live SavedVariables, push,
merge, tag, release, publish, integrate licensing, change PR #6, or perform a
remote action.

Test.15 remains the immutable failed live artifact. It is 614,651 bytes with
SHA-256
`D36D24F010B0B79DF27DC6D83435A848099E967369B9CF13D1A9D74FE2A070A9`.
It predates every Stage 35 repair and is not release-ready.

## Exact source boundary

- Branch: `codex/stutteralert-diagnostic-provider`.
- Stage 35 base: `745cae32f1e42db91e09b93d68deb05736c9cb4b`.
- Reviewed repair head: `b5c792e4d53fe43474345afb7d65209f15226c63`.
- Range: nine commits, 49 unique paths, 4,133 insertions, 399 deletions.
- Public version: `1.20.0-beta.1`.
- Protocol: 7.
- TOC Author: `Valentine`.
- Upstream author attribution: `Boganic`, preserved.
- Product worktree before this audit record: clean.

The nine ordered commits are:

| Checkpoint | Commit | Scope |
| --- | --- | --- |
| 35.1 | `110a1e3e02bac9afb371cd3ba55b56ee729e23d9` | Characterize test.15 live failures; 1 path, +438/-0 |
| 35.2 | `22e86bcbfb938a15c1da59afddda28edc8385907` | Preserve typed candidate evidence; 16 paths, +675/-291 |
| 35.3 | `91da0c17a06ce8f4c649310b86061e9f4e072ad0` | Resolve recovered navigation identity; 6 paths, +405/-17 |
| 35.4 | `2ed3ea876e70d5cc6bb9a10d72b36ebef54b9d91` | Characterize burst and locked-only blockers; 3 paths, +532/-0 |
| 35.5 | `ffe041ae552bb176a8f36d9a5c09adbadd046e1e` | Bound instant-level burst work; 8 paths, +188/-26 |
| 35.6 | `2432ee7c27cc03305dc944f7959adb180dca86a5` | Quarantine locked-only loadouts; 20 paths, +588/-182 |
| 35.7 | `7af60776cc627c21bd13b1e1c3f3cbead793b686` | Resolve Leaderboard class authority; 7 paths, +396/-68 |
| 35.8 | `252495c9f8c854eadb0375d9cb4a0d131e375a90` | Expose Community catalog status; 13 paths, +578/-66 |
| 35.9 | `b5c792e4d53fe43474345afb7d65209f15226c63` | Classify useful Sync progress; 10 paths, +629/-45 |

The 49 unique Stage 35 paths are:

```text
Nexus.toc
core/AutomationRuntime.lua
core/BuildCatalog.lua
core/CandidateEvidence.lua
core/CommunityController.lua
core/DpsCapture.lua
core/GameAdapter.lua
core/LegacyQualificationRepair.lua
core/LoadoutEvidence.lua
core/Main.lua
core/MainDiagnostics.lua
core/PeerDebug.lua
core/Sync.lua
core/SyncCompatibility.lua
core/SyncDiagnostics.lua
core/SyncSession.lua
core/ViewProjections.lua
core/WishlistController.lua
docs/MODULAR_REFACTOR_CHARACTERIZATION.md
tests/harness.lua
tests/module_contract_manifest.lua
tests/run-upvalue-compatibility.js
tests/run_automation_runtime_boot.lua
tests/run_build_catalog_related_index.lua
tests/run_community_catalog_status.lua
tests/run_community_contract_characterization.lua
tests/run_leaderboard_class_presentation.lua
tests/run_leaderboard_refresh_budget.lua
tests/run_leaderboard_virtualization.lua
tests/run_level_burst_characterization.lua
tests/run_live_projection_work_budget.lua
tests/run_locked_only_loadout_characterization.lua
tests/run_main_contract_characterization.lua
tests/run_main_diagnostics_parity.lua
tests/run_module_contract_characterization.lua
tests/run_peer_debug.lua
tests/run_recovered_build_navigation.lua
tests/run_stage30_diagnostic_identity.lua
tests/run_stage32_leaderboard_locked_fidelity.lua
tests/run_stage35_candidate_evidence.lua
tests/run_stage35_live_failure_characterization.lua
tests/run_sync_autoshare.lua
tests/run_sync_late_post.lua
tests/run_sync_transport_safety.lua
tests/run_sync_two_peer.lua
tests/run_sync_useful_progress.lua
tests/run_view_projections.lua
ui/CommunityRenderer.lua
ui/Leaderboard.lua
```

## Cause-to-owner map

| Live evidence | Exact source cause | Repair owner |
| --- | --- | --- |
| Candidate evidence could lose an ordinary/locked shared spell or exceed the intended envelope | Community, Leaderboard, and Wishlist did not share one immutable typed evidence contract | `core/CandidateEvidence.lua` plus the existing three consumers |
| Recovered Community row opened the wrong colliding current build | Navigation retained the raw identity instead of the resolved exact historical identity | Existing projection/navigation owners; no second catalog |
| Instant level 1-to-60 transition preceded a native client exit | Native causation is unproven; addon event work lacked fixed scalar burst attribution | Existing `GameAdapter` dirty owner, one existing automation pump, bounded diagnostics |
| Locked-only evidence appeared as a complete Record Loadout | Locked supplemental evidence could imply ordinary completeness | One independently fingerprint-validated ordinary-completeness verdict across catalog, projection, UI, qualification, export, and Sync |
| Leaderboard class icon was missing or misleading | Raw class filtering happened before accepted record/exact build/current-player/later-enrichment resolution; UI trusted row build class independently | `core/ViewProjections.lua` authority, `ui/Leaderboard.lua` neutral consumer |
| Bundled Community baseline appeared absent under filters | Only one aggregate catalog count was visible and there was no explicit search-only clear action | Existing BuildCatalog cursor provenance, projection status scalars, controller-owned Clear Search |
| Duplicate/rejected traffic looked like Sync progress | `SyncSession.NoteInbound` coupled bounded request liveness to `peerProgress=true`; accepted commits had no request-scoped outcome | Existing SyncSession/SyncDiagnostics state, fixed scalar outcome callback, existing Sync commit points |

No finding justified another automation state machine, event queue, timer,
scheduler task, full-catalog cache, wire field, dependency, storage rewrite,
queue/send-cap increase, dynamic compilation, or environment hack.

## Expected red and final green

The assembled Stage 35 runner initially retained 16 expected reds. The final
reviewed bytes report:

```text
checks=42
expected_red=0
typed=green
navigation=green
class=green
catalog=green
sync=green
baseline=504
echoes=36187
protocol=7
peers=2
```

Focused Stage 35 replay passes `9/9`:

- typed candidate evidence: ordinary 79 plus locked six, shared role retained,
  80/seven/sparse/future rejected, zero mutation;
- recovered navigation: 200 rows, exact historical identity, zero scans or
  mutations, warm cache retained;
- instant-level burst: 59 transitions, one coalesced pump, zero actions,
  Sync amplification, or scheduler growth, with no native-cause claim;
- locked-only matrix: six cases with one-to-six locks, no false catalog-ready,
  qualification, Copy, Open, EBH1, or Sync authority;
- Leaderboard class: 200 rows, authoritative sources and neutral unavailable
  state, zero warm delta;
- Community status: bundled 504, overlay one, available 505, page/filter/search
  state retained, zero warm delta;
- useful Sync: new/updated/intended Share only, baseline/duplicate/rejected/
  unrelated non-useful, fixed expiry/no-useful/drop/full/requeue/disconnect
  outcomes and bounded scalars;
- two-peer protocol 7: isolated request identity, one overlay admission,
  duplicate suppression, unrelated rejection, and Share priority.

## Preservation receipts

| Boundary | Final deterministic result |
| --- | --- |
| Complete Lua | `188/188 PASS`, zero excluded or skipped |
| Lua 5.1 source/test parse | `1284/1284 PASS` |
| Upvalue compatibility | 60 passes / 61 fails; 66 TOC files; 2,756 functions; zero above 60 |
| Highest packaged function | `ui/Panel.lua:385 EnsureFrame=60`; `AutomationRuntime.Step=16` |
| Boot/factory/Main | `toc=66 factoryCalls=1 polls=2 banner=yes error=none` |
| Integration | `70/70 PASS`; protected Blizzard globals stock-owned |
| Hostile Sync | `4,000/4,000` deterministic payloads bounded and fail closed |
| Module inventory | 11 modules, 193 surfaces, 14 assigned members, 156 callback sites, 17 groups, zero unmapped |
| Stage 25 | Semantic-board coalescing, immutable intents, action/refusal/deadline/fallback, zero warm repeated traversal, fixed overlay state all pass |
| Stage 26-33 | Automation isolation, Sync/DPS ownership, wire, tombstone, paging, queue, storage, UI, startup, and diagnostic controls pass |
| Export/privacy | Exact diagnostic golden/export isolation, Peer bounds, StutterAlert, zero Stage 35 added private-path hits |
| Build/export tools | Bundled exporter and read-only SavedVariables analyzer pass |
| Metadata | `Author=Valentine`, public version `1.20.0-beta.1`, protocol 7, upstream Boganic attribution preserved |
| Historical artifacts | test.5 through test.15 hashes `11/11 PASS` |
| Scope | `SyncProtocol.lua` and `data/Release.lua` unchanged; range and final diff checks pass |

The useful-Sync review caught three unacceptable intermediate omissions before
commit: human Sync/Peer diagnostics did not expose the new scalars; accepted
unsolicited Shares no longer fed the historical `LastSyncNewCount`; and late
retry/drop events lost attribution after the first send attempt. The final
bytes repair all three. Intermediate failing commands are not counted.

## Fixed offline

- Typed ordinary and locked candidate roles remain separate and immutable.
- Recovered navigation uses the exact resolved historical identity.
- Instant level notifications coalesce through fixed existing owners with
  bounded scalar attribution and no new queue.
- Locked-only evidence cannot create ordinary completeness or authority.
- Leaderboard class is resolved before filtering and unavailable class is
  neutral rather than guessed.
- Community status tells the truth about bundled, overlay, available, matched,
  qualifying, result, displayed, search, and catalog-version state.
- Request liveness no longer proves useful Sync progress. New, updated,
  intended Share, baseline, duplicate, rejected, unrelated, terminal, and
  queue outcomes remain fixed bounded diagnostics.

## Still live-unproven

- Test.15 contains none of these repairs and remains the preserved failed
  startup/product artifact.
- No test.16 has been created, installed, or started on either computer.
- In-game Community baseline/filter/search presentation and Leaderboard class
  presentation after these repairs.
- Exact same-build two-user Share, complete two-client Sync convergence,
  bounded request terminal reporting, and locked-only recovery.
- Native-client stability and cause during instant-level transitions; absence
  of a retained export proves neither Nexus involvement nor exclusion.
- Live HUD/Community layouts, frame time, memory high-water, garbage
  collection, and StutterAlert attribution on the repaired head.
- Project Ebonhold Orb of Lost Memories behavior without authoritative API,
  event, and roll-context evidence.

Stage 35 passes offline at reviewed repair head `b5c792e`. The next action is
separately gated: explicit authorization would be required to create one
unpublished test.16 from the exact clean final audit head, install it on both
computers, and restart the complete live checklist. This workflow stops before
that boundary.
