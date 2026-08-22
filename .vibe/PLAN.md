# PLAN

## Stage 49 — Historical DPS authority and real paired summaries

- Goal: keep historical locked snapshots immutable and make every Dummy/LK average represent one real authority-compatible pair rather than independently selected category maxima.
- Decision: historical snapshot evidence and current/build copy authority are separate; neither timestamp nor category winner alone may rewrite the other.
- Decision: category bests may remain useful independently, but Average is unavailable unless a real pair shares canonical owner, ordinary fingerprint, and locked/full-combat identity.

### 49.1 — Separate historical locked snapshots from copy authority (#23)

- Status: `DONE`
- Objective:
  - Preserve capture-time locked evidence while resolving current copy authority only through a stronger exact association.
- Deliverables:
  - Explicit historical-snapshot versus current/build-authority roles in locked evidence resolution.
  - Focused later-current-state, category-order, timestamp-order, exact-authority, conflict, reload, and Sync coverage.
  - Immutable historical DPS rows when exact copy authority is absent.
- Acceptance:
  - [x] Later current/build state cannot rewrite a historical locked snapshot by resemblance or recency.
  - [x] Category winner and timestamp order never select copy authority by themselves.
  - [x] Stronger exact current authority may resolve a copy operation without mutating historical evidence.
  - [x] Conflicting or incomplete authority preserves history and reports unavailable/conflict explicitly.
  - [x] Blocking focused, mapped, Fast, review/Full, and diff checks pass.
  - [ ] Nonblocking manual SavedVariables/native validation remains explicitly unverified.
- Demo commands:
  - `luajit tests/run_locked_evidence_resolver.lua && luajit tests/run_stage32_leaderboard_locked_fidelity.lua`
  - `luajit tests/run_historical_locked_authority.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e70de8a7582d0146cc6746677084b3f4a270290b`
- Evidence:
  - Historical/current expected-red matrix, focused green, and independent review receipt.

### 49.2 — Compute Average only from a real compatible Dummy/LK pair (#26)

depends_on: [49.1]

- Status: `DONE`
- Objective:
  - Select the best real Dummy/LK pair sharing verified owner and exact ordinary plus locked/full-combat identity, or expose Average as unavailable.
- Deliverables:
  - One pair-compatibility predicate and deterministic best-real-pair selector in the DPS projection owner.
  - Focused mixed-owner, mixed-ordinary, mixed-locked, multiple-valid-pair, missing-authority, ordering, and reload coverage.
  - Preservation of independently useful category bests without synthesizing their mean.
- Acceptance:
  - [x] Every displayed Average comes from two actual records with the same verified canonical owner.
  - [x] The pair shares the same ordinary fingerprint and locked fingerprint/full-combat identity.
  - [x] Mixed owners or incompatible builds never produce an Average, while independent category bests remain available.
  - [x] Multiple valid pairs choose the deterministic best real pair; no valid pair reports Average unavailable.
  - [x] Blocking DPS/board/UI, mapped, Fast, review/Full, and diff checks pass.
  - [ ] Nonblocking manual SavedVariables/native validation remains explicitly unverified.
- Demo commands:
  - `luajit tests/run_dps_boards.lua && luajit tests/run_leaderboard_ui.lua`
  - `luajit tests/run_paired_dps_summary.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e70de8a7582d0146cc6746677084b3f4a270290b`
- Evidence:
  - Pairing expected-red/green matrix, exact summary receipts, and independent Spec/Standards review.

## Stage 50 — Typed build identity in Sync bucket hashes

- Goal: make every eight-bucket build digest preserve the typed build identity that BuildCatalog and Sync reconciliation already treat as semantically distinct.
- Decision: encode the raw ID type in canonical build and tombstone hash material at the existing BuildHashCache boundary; do not coerce catalog identity or change bucket count.
- Decision: preserve deterministic ordering and validate delta, legacy, invalidation, reconciliation, and mixed-client behavior together so protocol-compatible peers cannot retain false equality.

### 50.1 — Preserve typed IDs in build and tombstone bucket material (#40)

depends_on: [49.2]

- Status: `IN_REVIEW`
- Objective:
  - Ensure numeric and string forms of the same textual build ID produce distinct deterministic build and tombstone bucket hashes without changing the bounded eight-bucket design.
- Deliverables:
  - Focused expected-red typed build/tombstone, peer-reconciliation, delta/legacy, invalidation, and iteration-order coverage.
  - Typed canonical entry material for build and tombstone rows in `core/BuildHashCache.lua`.
  - Explicit mixed old/new digest compatibility behavior that prevents permanent false equality.
- Acceptance:
  - [ ] Numeric `1` and string `"1"` hash differently for builds and tombstones; exactly equal typed records hash equally.
  - [ ] A numeric/string peer mismatch cannot report bucket equality or skip reconciliation.
  - [ ] A bucket containing both typed IDs is deterministic across Lua table iteration order and targeted/full rebuilds.
  - [ ] Delta and legacy hash modes preserve the same typed identity rule, while ordinary string IDs remain deterministic.
  - [ ] Mixed old/new behavior is compatibility-gated or versioned if required to prevent protocol-compatible false equality.
  - [ ] Blocking focused, mapped, Fast, Full, Lua, parse, integration, policy, and exact-diff checks pass; native WoW remains explicitly unverified.
- Demo commands:
  - `luajit tests/run_sync_hash_cache.lua`
  - `luajit tests/run_sync_baseline_delta.lua && luajit tests/run_sync_compatibility_parity.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 8f5d28008935cef2d973b800167695ab50e0f70b`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full -BaseRef 8f5d28008935cef2d973b800167695ab50e0f70b`
- Evidence:
  - Expected-red typed-collision receipt, focused green compatibility matrix, and exact-head gate/diff receipt.
