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
  - [x] Mixed owners or incompatible builds never produce an Average even when each is a category best.
  - [x] Multiple valid pairs choose the deterministic best real pair; no valid pair reports Average unavailable.
  - [x] Dummy and LK category bests remain independently available without implying a pair.
  - [x] Blocking DPS/board/UI, mapped, Fast, review/Full, and diff checks pass.
  - [ ] Nonblocking manual SavedVariables/native validation remains explicitly unverified.
- Demo commands:
  - `luajit tests/run_dps_boards.lua && luajit tests/run_leaderboard_ui.lua`
  - `luajit tests/run_paired_dps_summary.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e70de8a7582d0146cc6746677084b3f4a270290b`
- Evidence:
  - Pairing expected-red/green matrix, exact summary receipts, and independent Spec/Standards review.
