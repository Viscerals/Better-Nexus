# Stage 26 final offline audit

Stage 26 is complete at the offline source boundary. It repairs Sync transport
and session liveness, accepted inbound progress, DPS duration/publication,
active-Sync view responsiveness, and bounded diagnostics without creating or
installing an addon artifact.

This is not live evidence. Two-user convergence, client frame time, retained
memory, server throttle behavior, and Project Ebonhold integration remain
unproven until the separately authorized Stage 27 procedure.

## Source boundary

- Stage 25 base: `375dd59367aa911365470eb3b4719c8ba6cc71e8`.
- Reviewed Stage 26 product source before this audit record:
  `4a0b06ab917489dc1ea34b6985235ea627d50d47`.
- Branch: `codex/stutteralert-diagnostic-provider`.
- Stage 26 range before this audit record: 34 files, 2,343 insertions, and
  441 deletions.
- No artifact, install, live addon, SavedVariables mutation, deployment, push,
  merge, tag, release, or publication occurred.
- Historical test.9 remains unchanged.

## Verdict matrix

| Area | Offline verdict | Deterministic evidence | Remaining live risk |
| --- | --- | --- | --- |
| Request and transport liveness | `PASS` | A request admitted behind 8,190 bulk packets is attempted first; receive timing begins at that attempt. Four consecutive controls force one waiting bulk send within the next five sends. Convergence is capped at 300 seconds, receive at 180 seconds, three passes, and three transport attempts. | Real server pacing, throttle notices, and peer receipt timing are unproven. |
| Bounded reconciliation and Share | `PASS` | Response work admits at most 32 records per request in product configuration, preserves a bounded continuation, and stops preparation near queue saturation. Priority Share packets bypass ordinary control and bulk backlog while retaining FIFO within the Share class. | Large live libraries and mixed-version peers still need two-user observation. |
| Accepted inbound state | `PASS` | Strict network validation, sender/envelope/context checks, accepted-progress ownership, false-peer prevention, current/legacy compatibility, and 4,000 bounded hostile inputs pass. Rejected or unrelated input cannot prolong an absolute session. | Real channel interference and mixed client versions remain unproven. |
| DPS convergence | `PASS` | One rule is used for local, direct, relay, integrity, qualification, and publication: Dummy 30 seconds and Lich King 20 seconds. The 19/20/29/30 boundary matrix, direct/relay convergence, invalid stored-row exclusion, and nine fixed rejection counters pass. | Two-user capture, relay routing, and board publication remain unproven. |
| Community and Leaderboard | `PASS` | A real 1,000-build/1,200-DPS-row fixture changes scope, class, qualification, search, sort, page, category, and class state during receive with zero heavy publication. Last-good rows remain bound; Community and Leaderboard each publish exactly once after quiet. | WoW frame time and real interaction feel remain unproven. |
| Peer Test and Sync diagnostics | `PASS` | Peer Test delegates exclusion reasoning, refreshes once per visible active second, and does zero recurring hidden/disabled work. Its ring is 160 scalar events for at most 900 seconds. A 1,109-build Sync page performs one count and at most 100 summary reads, never a complete catalog copy; cursor faults remain contained. | Live report usefulness and long-session retained memory remain unproven. |
| Persistence and automation | `PASS` | Additive/legacy/future-field Store tests, read-only SavedVariables analysis, ownership/tombstone/merge suites, uncapped 1,000/1,109-build fixtures, 20-row Community paging, fixed UI pools, and 70 integration checks pass. Fifty accepted Sync updates cause zero automation full steps, policy calls, renders, associations, uploads, or gameplay mutations. | Backup/restore, reload, live unknown-field preservation, and the 0.2-second runtime cadence still require live verification. |
| Scoped cleanup | `PASS` | The destination-Wishlist status uses stable ASCII text and LogViewer owns one `CloseOtherWindows` call. The expected-red fixture isolated both defects before the two-line repair. | None beyond normal live rendering verification. |

## Before and after bounds

| Boundary | Before Stage 26 | Stage 26 deterministic bound |
| --- | --- | --- |
| Near-capacity request | One FIFO path could leave a request behind 8,190 bulk packets, roughly 2.5 hours at 1.10 seconds each. | Separate 512-packet control capacity; the request is the first attempted packet in the near-capacity fixture. |
| Fairness | No bounded control latency distinct from bulk. | At most four consecutive control sends while bulk waits; bulk progresses within five sends. |
| Request lifetime | Receive/convergence could be attributed to global unrelated work. | 180-second absolute receive cap, 300-second absolute convergence cap, and three passes; a later explicit request recovers after expiry. |
| Retry | An API-returned attempt could be misreported as complete after a throttle notice. | Exact-packet idempotent requeue, at most three attempts, explicit expiry/full/retry-exhausted outcomes, and no cap growth. |
| Reconciliation | A response could prepare a complete library before admission failed. | At most 32 response admissions per request, 8-packet bulk headroom, 128 pending responses/loadouts, and 300-second continuation age. Complete catalog storage is unchanged. |
| View work | Receive-time churn could make controls appear frozen or trigger expensive view work. | Zero heavy receive-time publications; source/join/copy work is at most 25 rows per pump, comparisons and sort moves at most 500, followed by one atomic publication per view. |
| Interactive diagnostics | Sync diagnostics copied the complete catalog and nested Echo data to show 100 rows. | One count, one summary cursor, at most 100 summary reads, zero complete Echo-list copies; the complete exporter remains resumable. |

## Validation receipts

- Combined Stage 26 adversarial matrix: `18/18 PASS`, `0 FAIL`.
- Complete Lua suite: `161/161 PASS`, `0 FAIL`.
- Lua 5.1 source/test parse: `227/227 PASS`, `0 FAIL`.
- Deterministic bundled-build exporter: `PASS`.
- Generated read-only SavedVariables analyzer: `PASS`.
- Integration: `70/70 PASS`, `0 FAIL`.
- Module inventory: 10 modules, 183 surfaces, 13 assigned members,
  152 callback sites, 17 groups, zero unmapped.
- StutterAlert provider registration, correlation, caps, failure isolation,
  and session-only storage: `PASS`.
- Package-source check: 62 TOC Lua entries, zero missing, zero duplicates;
  all 14 changed runtime Lua files are listed.
- Added-line privacy scan: zero hits.
- Artifact/log/test.9 additions: zero.
- `git diff --check`: `PASS`.

No expected-red, unavailable, skipped, or failing result is counted as a pass.

## Local Stage 26 commits before this audit record

- `43a496b` - characterize transport and session liveness.
- `c56b1df` - bound Sync transport liveness.
- `4b9921f` - tighten transport liveness boundaries.
- `ddbacde` - characterize strict inbound acceptance.
- `8e61e9e` - enforce strict inbound acceptance.
- `ee47016` - expose the strict DPS schema gap.
- `95ba5f5` - reject coercible DPS wire fields.
- `e87de5e` - characterize the DPS duration contract.
- `03def94` - unify DPS duration boundaries.
- `ea71bd8` - harden DPS publication review.
- `2c7c1bf` - characterize responsive Sync diagnostics.
- `7e40a1a` - keep Sync views responsive.
- `696a354` - harden responsive diagnostics review.
- `ec3ec1b` - characterize scoped cleanup defects.
- `4a0b06a` - clean up Sync-facing UI text.

## Exact changed files before this audit record

```text
core/Codec.lua
core/CommunityController.lua
core/DpsCapture.lua
core/MainDiagnostics.lua
core/PeerDebug.lua
core/Sync.lua
core/SyncInbound.lua
core/SyncProtocol.lua
core/SyncReconciler.lua
core/SyncSession.lua
core/SyncTransport.lua
core/ViewProjections.lua
tests/run_dps_capture.lua
tests/run_live_projection_work_budget.lua
tests/run_main_diagnostics_parity.lua
tests/run_peer_debug.lua
tests/run_scheduler.lua
tests/run_stage24_dps_convergence_characterization.lua
tests/run_stage24_share_convergence_characterization.lua
tests/run_stage26_dps_duration_contract.lua
tests/run_stage26_inbound_acceptance.lua
tests/run_stage26_scoped_cleanup.lua
tests/run_stage26_sync_ui_responsiveness.lua
tests/run_stage26_transport_liveness.lua
tests/run_sync_basic.lua
tests/run_sync_contract_characterization.lua
tests/run_sync_inbound_parity.lua
tests/run_sync_logging.lua
tests/run_sync_protocol_parity.lua
tests/run_sync_reconciler_parity.lua
tests/run_sync_response_backpressure.lua
tests/run_sync_transport_owner.lua
ui/CommunityRenderer.lua
ui/LogViewer.lua
```

## Proposed Stage 27 procedure - authorization required

1. Obtain separate explicit authorization for artifact creation, installation
   on both clients, and backup/restore handling. Recheck branch, exact source
   head, worktree ownership, and clean status first.
2. Build one unpublished artifact from that exact reviewed head in an isolated
   staging directory. Record its file manifest, size, and SHA-256. Do not edit
   source or historical test.5 through test.9.
3. Back up both clients' installed Nexus folders and Nexus SavedVariables
   without editing them. Record rollback paths and hashes.
4. Install the same artifact on both clients and independently verify byte-for-
   byte manifests and SHA-256 before launching the game. Stop on any mismatch.
5. With two nearby same-class users, establish a quiet baseline, then test an
   explicit Sync, one priority Share in each direction, direct and relayed DPS
   publication at the category duration boundaries, and final catalog/board
   convergence.
6. While receive work is active, exercise Community scope, class,
   qualification, search, sort, page, Leaderboard category/class/search, and
   visible Peer Test refresh. Confirm last-good rows stay usable and one quiet
   publication follows accepted completion or bounded expiry.
7. Capture only bounded Peer Test, Nexus diagnostic, and StutterAlert summaries.
   Compare request age, queue progress, receipt/acceptance, revision,
   publication, automation, frame-time, and retained-memory owners on both
   clients.
8. Stop immediately on byte mismatch, SavedVariables loss, false peer/progress,
   unbounded receive/convergence, stalled bulk, duplicate/unauthorized action,
   frozen controls, blank last-good boards, or material performance regression.
   Preserve the bounded evidence and roll back from the recorded backups.
9. Treat a clean live result as test evidence only. Push, merge, tag, release,
   and publication remain separate authorization boundaries.

Stage 27 remains deferred. Stage 26 makes no live convergence or performance
claim.
