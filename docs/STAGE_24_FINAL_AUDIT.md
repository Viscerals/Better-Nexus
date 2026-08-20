# Stage 24 peer-convergence final audit

Audit date: 2026-08-11

Verdict: **PASS OFFLINE / LIVE TWO-USER TEST REQUIRED**

This audit is fail-closed. It reports source and deterministic offline evidence
only. It does not claim live delivery, install an addon, change live
SavedVariables, or authorize a push, merge, tag, release, or publication.

The optional test.9 package was not created in this run. Package manifest,
size, and SHA-256 are therefore `N/A`; the source remains the only audited
deliverable until a separate byte-matched two-user test is authorized.

## Audited source

- Branch: `codex/stutteralert-diagnostic-provider`
- Stage 24 base: `f66e8530149bbded0aa6fd1406e2e4003f737adb`
- Source head before this audit record: `80072b276ae8e4409385089972d28d1aefef8c4c`
- Stage 24 source commits: 12
- Stage 24 source range: 42 files, 3,237 additions, 205 deletions
- Source identity: `1.20.0-beta.1`, local and unpublished
- Installed addon, live saves, remotes, and release state: unchanged by this
  audit

Stage 24 commits, in order:

1. `fe2347bf260c4c33528ea359a12aa6bf996b58a1` - characterize peer
   convergence gaps.
2. `0599f591b1fb15a37eb0535d15760e1f7daadc4e` - tighten convergence
   characterization.
3. `ec45d446ba99d1c796f46542d271c8ca3ae340c0` - preserve all-false
   Wishlist discovery.
4. `29f9925f0ba55fd9ded7fd425c203d9f10b5b5c3` - lock Wishlist discovery
   boundaries.
5. `8a76025b210c15cdf2812fb300f936c2960cc5d3` - add bounded Peer Test
   diagnostics.
6. `167724ce7e906d37191386d716e59f6bb5406d3a` - bound Peer Test report
   output.
7. `8a868969ae1d4b2dfd36cd03b570847f1109b915` - make Share outcomes
   truthful and retryable.
8. `dea1ff98889669af298322c5b31ebe6fc840905f` - add truthful Community
   filters and cached pages.
9. `62aa726d6b85f97a7f1c0750cf1540dea89d2a45` - prove cached Community
   page controls.
10. `4cbaa49fff141a30ce1471bf4107ca618d04e852` - converge requested DPS
    buckets.
11. `3ed0ec845469fe07c2a79f59a1c0fbbd3b4f2c0b` - extend quiet for paced
    DPS buckets.
12. `80072b276ae8e4409385089972d28d1aefef8c4c` - record the sync
    transport decision.

## Offline verdict matrix

| Boundary | Verdict | Reproduced evidence | Live limit |
| --- | --- | --- | --- |
| Pending Wishlist discovery and action authorization | `PASS` | Structurally valid 80-85-entry all-false mirrors remain visible with pending evidence while every mutation path stays fail-closed. | The supplied historical UI case must still be repeated in WoW. |
| Opt-in Peer Test diagnostics | `PASS` | Disabled reporting performs zero provider/represented-data work and zero SavedVariables writes. The session ring retains 160 bounded events, expires, clears, and keeps formatted output below 60,000 characters. | A real two-user report has not been captured from this source. |
| Truthful Share action | `PASS` | Local save, queue admission/rejection, bounded retry, send completion, and unavailable peer confirmation remain distinct. Queue pressure does not produce an unconditional peer-success message or overwrite admitted FIFO work. | Peer storage cannot be claimed until the second client commits the record. |
| Community filters and paging | `PASS` | Current-class and qualified-only defaults remain additive; all-class/all-shared opt-outs, unknown/unqualified labels, a fixed 20-row page, and cached page changes pass. | Real frame time and user-visible control behavior remain unmeasured. |
| DPS and Leaderboard convergence | `PASS` | Matching hashes remain silent. One changed requested bucket relays only validated evidence, advances one DPS revision, reaches the offered digest, and publishes once after quiet. The 61-second paced response regression passes. | Channel reachability and two-client convergence remain unproved. |
| Ownership, tombstones, hostile input, and mixed versions | `PASS` | Direct-owner authority, non-owner relay status, tombstone rules, wrong request/target rejection, bounded hostile traffic, queue pressure, cold start, and compatibility suites pass. | A live mixed-version session was not run. |
| Transport replacement decision | `PASS` | The sourced decision keeps the existing mesh and Nexus policy; every external candidate is rejected or deferred as an unproved old-client drop-in. | A discovery-channel/directed-whisper experiment requires separate old-client evidence and coexistence design. |

No unresolved offline major or moderate finding remains. A `PASS` above means
the deterministic source boundary passed; it does not upgrade the corresponding
live claim.

## Validation receipts

### Focused adversarial matrix

Forty of 40 focused suites pass. The matrix includes:

- all four Stage 24 characterizations;
- Peer Test, performance diagnostics, and StutterAlert integration;
- GameAdapter, automation isolation, Panel, Wishlist, and full boot;
- Community controller/facade/projection/renderer and real Show budgets;
- Leaderboard UI, refresh, and live projection budgets;
- 4,000 deterministic hostile Sync messages;
- queue response backpressure, transport safety, and transport ownership;
- owner claims, tombstone relay, sender/inbound validation, record identity;
- current/legacy compatibility, cold start, hash cache, and mesh convergence;
- the ten-module contract inventory.

High-signal focused outputs:

- Stage 24 convergence: two direct chunks, two relay chunks, one revision,
  matching digest.
- Community projection: 1,000 builds, 500 DPS rows, 20 returned rows, six
  summary walks, six eligibility reads, one raw scan.
- Leaderboard budget: 1,000 builds, 500 DPS rows, 250 ranked rows, six board
  reads, five created row frames, zero active-Sync heavy work, one publication.
- Module contract: 10 modules, 182 public surfaces, 13 assigned members, 152
  callback sites, 17 callback groups, zero unmapped symbols.

### Complete gates

- Complete Lua suite: `153/153 PASS`, `0 FAIL`.
- Lua 5.1 source/test parse: `219/219 PASS`, `0 FAIL`.
- Deterministic bundled-build exporter: `PASS`.
- Generated read-only SavedVariables analyzer fixture: `PASS`.
- Stage 24 range `git diff --check`: `PASS`.
- Source worktree status before this audit record: clean.
- Stage 24 artifact/log-file additions: zero.
- Scoped supplied-identity/private-title/path scan over the Stage 24 diff:
  zero hits.

No expected-red, skipped, unavailable, guessed, or failed command is counted in
those totals. One malformed command-line attempt to parameterize Git was
discarded and replaced by the supported explicit argument form; only the
successful rerun supplies the range receipts above.

### Read-only supplied-snapshot analyzer

The analyzer read the two authorized snapshots without modifying either one or
the record counts:

| Snapshot | Bytes | Builds | DPS rows | Missing references | Conflicts | Record counts unchanged |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Supplied peer snapshot | 7,616,583 | 870 | 87 | 0 | 1 reference mismatch | yes |
| Supplied local snapshot at audit time | 7,108,923 | 589 | 596 | 0 | 0 | yes |

These aggregates reconfirm substantial asymmetric state. They do not identify
which live delivery boundary failed, and the local snapshot may continue to
change while the game runs. No snapshot, identity, title, account data, payload,
or complete Echo list is committed.

## Exact Stage 24 file scope

The 42 source-range paths are:

```text
Nexus.toc
core/BuildHashCache.lua
core/CommunityController.lua
core/CommunityProjection.lua
core/DpsCapture.lua
core/GameAdapter.lua
core/MainDiagnostics.lua
core/MainLifecycle.lua
core/PeerDebug.lua
core/Sync.lua
core/SyncDiagnostics.lua
core/SyncInbound.lua
core/SyncReconciler.lua
core/SyncSession.lua
core/SyncTransport.lua
core/ViewProjections.lua
docs/MODULAR_REFACTOR_CHARACTERIZATION.md
docs/MODULAR_REFACTOR_FINAL_AUDIT.md
docs/SYNC_TRANSPORT_DECISION.md
tests/module_contract_manifest.lua
tests/run_builds_sort_filter.lua
tests/run_community_contract_characterization.lua
tests/run_community_dps_eligibility.lua
tests/run_community_facade_parity.lua
tests/run_community_refresh_budget.lua
tests/run_main_diagnostics_parity.lua
tests/run_main_lifecycle_parity.lua
tests/run_module_contract_characterization.lua
tests/run_peer_debug.lua
tests/run_scheduler.lua
tests/run_stage24_community_filter_characterization.lua
tests/run_stage24_dps_convergence_characterization.lua
tests/run_stage24_share_convergence_characterization.lua
tests/run_stage24_wishlist_discovery.lua
tests/run_sync_contract_characterization.lua
tests/run_sync_facade_parity.lua
tests/run_sync_inbound_parity.lua
tests/run_sync_transport_owner.lua
ui/CommunityBuilds.lua
ui/CommunityRenderer.lua
ui/Leaderboard.lua
ui/LogViewer.lua
```

This list excludes this final audit record itself; its commit is the Stage 24.8
review surface.

## Fixed offline

- Pending Wishlist identities no longer disappear merely because passive lock
  evidence is incomplete; authorization still fails closed.
- Peer Test is part of the normal addon, opt-in, bounded, session-only, and
  effectively inert while disabled.
- Share no longer equates local save with network or peer success. Queue-full
  recovery is immutable, bounded, and honest about absent peer confirmation.
- Community exposes truthful scope and qualification controls, unknown and
  unqualified states, cached 20-row pages, and visible range totals without a
  storage cap.
- Requested DPS buckets can converge from validated direct-origin evidence
  without granting relay ownership or weakening tombstone/sender rules.
- Leaderboard publication remains coalesced after Sync quiet, including the
  paced-response boundary found during review.
- The transport comparison selects repair of the current mesh and defers any
  replacement until old-client compatibility, receive bounds, migration,
  coexistence, rollback, and licensing are proved.

## Still live-unproven

- Byte identity between two installed clients.
- Actual channel join, reconnect, throttle, whisper, and reachability behavior.
- End-to-end Share creation, admission, send, receiver commit, and projection
  on a second client.
- End-to-end DPS request/offer/accept convergence and one post-quiet
  Leaderboard publication on both clients.
- Real WoW frame time, memory high-water, UI lifecycle, and long-session
  diagnostic expiry.
- Mixed-version coexistence outside the deterministic harness.

## Separately authorized two-user procedure

Do not run this procedure until one ordinary unpublished artifact is separately
authorized for both users.

1. Produce or receive one ordinary Nexus artifact from the reviewed source.
   Record its SHA-256 and manifest count. Both users independently verify the
   same SHA-256 before installation; stop on any byte or manifest mismatch.
2. Back up each user's current addon and SavedVariables using the agreed live
   test protocol. Install only the byte-matched artifact, then reload both
   clients. Do not combine it with an older test build.
3. On both clients, open the diagnostic UI, enable Peer Test, clear the session,
   and optionally select the intended peer. Confirm the same addon/protocol
   identity and channel name. Numeric channel indices may differ locally.
4. Record the initial connected/receiving/quiet states, queue depth, bounded
   build and DPS counts, and compact digest state in each panel. Do not exchange
   SavedVariables or general logs.
5. On client A, invoke `Sync Now` once. On both clients, wait until receiving is
   false and the convergence state is quiet. Copy one bounded Peer Test Report
   from each client as the baseline receipt.
6. On client A, explicitly share one uniquely labeled disposable test build.
   Record the displayed local-save, queue-admission, retry/send, generated-ID,
   class, Echo-count, represented-revision, and confirmation-unavailable states.
   Do not treat local save or send completion as peer storage.
7. On client B, wait for transfer completion and quiet. Confirm one receiver
   commit or an exact bounded exclusion reason. Open Community, switch to `All
   Shared`, disable `Current Class Only` and `Qualified Only` as needed, search
   for the unique test label, and exercise Next/Prev if it falls outside page
   one. Record the projection result without exporting the build contents.
8. If an ordinary safe gameplay path is agreed in advance, create one controlled
   DPS update on client A. Invoke `Sync Now` once more, wait for quiet on both
   clients, and confirm requested/offered/accepted counters, matching compact
   digest state, one DPS revision, and exactly one post-quiet Leaderboard
   publication. Skip this step if the capture cannot be performed safely.
9. Copy one final bounded Peer Test Report from each client before the session
   expires. Compare share ID, request identity, admission/send/commit outcome,
   build/DPS revisions, compact digest state, Community reason, and Leaderboard
   publication. Share only those bounded reports.
10. Pass only if the byte identities match and every performed flow reaches its
    expected receiver/projection state without ownership, tombstone, validation,
    queue, or retry anomalies. Otherwise preserve the two reports, restore the
    backed-up live state if required, and return to offline diagnosis without
    publishing.

Stage 24 stops at this authorization gate. Offline PASS is not live success.
