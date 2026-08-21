# PLAN

## Stage 48 — Exact Wishlist tiers and locked-role evidence

- Goal: preserve exact ordinary tier rows, exact locked copy counts, authoritative lock mirroring, and exact-quality progress across the complete Wishlist pipeline.
- Decision: exact `spellId` is the ordinary row identity when trustworthy; family remains grouping metadata and never satisfies or edits a sibling tier.
- Decision: ordinary, locked, and active-loadout evidence remain separate roles with separate limits and authority.

### (DONE) 48.1 — Preserve exact ordinary tier rows (#43)

- Status: `DONE`
- Objective:
  - Make editor open/edit/save and row actions round-trip every ordinary quality tier independently.
- Deliverables:
  - Exact-tier draft/model identity with deterministic fail-closed resolution for compatibility callers lacking an exact row handle.
  - Exact-row `+`, `-`, selection, and remove behavior.
  - Multi-tier family save/reload and supported import/export round-trip with 79-copy total coverage.
- Acceptance:
  - [ ] Common, Uncommon, and Rare rows in one family survive a no-op round-trip unchanged.
  - [ ] Editing or removing one exact tier cannot modify a sibling tier.
  - [ ] Ordinary total validation counts stack copies across every exact row and enforces 79.
  - [ ] Locked intent remains outside the ordinary editor-row identity.
  - [ ] Existing single-tier and compatibility-row behavior remains deterministic.
  - [ ] Focused Wishlist model/editor tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_wishlist_editor.lua && luajit tests/run_wishlist_model_parity.lua`
  - `luajit tests/run_wishlist_tier_roundtrip.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e674f033cc51494a382191b987c9a99cb6827f4a`
- Evidence:
  - Multi-tier expected-red/green matrix, compact gates, and independent review receipt.

### 48.2 — Preserve and validate exact locked copy totals (#44)

depends_on: [48.1]

- Status: `NOT_STARTED`
- Objective:
  - Validate locked evidence by copy total and preserve valid stack counts through candidate, draft, and export boundaries.
- Deliverables:
  - One locked-role copy-total owner enforcing `sum(stacks) <= 6` without row-count shortcuts.
  - Candidate-to-draft-to-export stack, exact-tier, provenance, and unknown-field preservation.
  - Focused valid duplicate, six-copy, seven-copy, malformed, overflow, and ordinary/locked-role coverage.
- Acceptance:
  - [ ] Six locked copies are accepted whether represented by one or several exact rows.
  - [ ] Seven locked copies and malformed/overflow stacks are rejected rather than clamped.
  - [ ] A valid `stacks=N` value never silently becomes one during conversion or export.
  - [ ] Ordinary copies and locked copies retain separate roles and limits.
  - [ ] Focused CandidateEvidence/Wishlist tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_stage35_candidate_evidence.lua && luajit tests/run_locked_only_loadout_characterization.lua`
  - `luajit tests/run_locked_copy_totals.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e674f033cc51494a382191b987c9a99cb6827f4a`
- Evidence:
  - Copy-total expected-red/green matrix, focused gate summaries, and independent review receipt.

### 48.3 — Derive exact ordinary and locked roles at read time (#20)

depends_on: [48.2]

- Status: `NOT_STARTED`
- Objective:
  - Derive ordinary and locked roles from an exact verified active-loadout total and authoritative active locked counts without rewriting the loadout mirror.
- Deliverables:
  - One exact multiset subtraction boundary consuming checkpoint 48.2 locked evidence.
  - Focused mixed-role, multi-copy, same-family sibling, underflow, partial, stale, reload, and no-authority coverage.
  - Read-only preservation of active, Snapshot, and Designed evidence.
- Acceptance:
  - [ ] Exact active totals minus exact authoritative locked counts produce exact ordinary counts and preserve both roles.
  - [ ] One spell/tier may carry both ordinary and locked copies without collapsing either role.
  - [ ] Partial totals, stale/unproven locks, sibling-tier ambiguity, and locked-total underflow fail closed.
  - [ ] Short-name, family, subset, title, slot proximity, and stale-ID resemblance never authorize derivation.
  - [ ] Derivation is order-independent, deterministic across reload, and does not mutate source evidence.
  - [ ] Focused association tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_snapshot_wishlist_association.lua && luajit tests/run_locked_evidence_resolver.lua`
  - `luajit tests/run_active_wishlist_lock_bridge.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e674f033cc51494a382191b987c9a99cb6827f4a`
- Evidence:
  - Authority/collision expected-red matrix, focused green, and independent review receipt.

### 48.4 — Report exact-tier Wishlist progress (#35)

depends_on: [48.1, 48.2, 48.3]

- Status: `NOT_STARTED`
- Objective:
  - Make overlay, HUD, model, and editor progress consume the same exact tier and role evidence.
- Deliverables:
  - One exact-spell/tier progress boundary shared by `ui/WishlistOverlay.lua`, the model, editor, and automation consumers.
  - Focused sibling-tier, per-tier quota, locked-role, refresh, and parity coverage.
  - Removal of family-level satisfaction as an authority decision.
- Acceptance:
  - [ ] A lower-quality sibling never satisfies a higher-quality target.
  - [ ] Each exact tier reports its own owned copies, target quota, and completion state.
  - [ ] Ordinary and locked progress consume their correct evidence roles.
  - [ ] Overlay, HUD, model, and editor agree before and after refresh/reload.
  - [ ] Focused overlay/parity tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_wishlist_overlay.lua && luajit tests/run_wishlist_renderer_parity.lua`
  - `luajit tests/run_wishlist_exact_progress.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef e674f033cc51494a382191b987c9a99cb6827f4a`
- Evidence:
  - Sibling-tier expected-red/green matrix, parity gates, and independent review receipt.

## Stage 49 — Historical DPS authority and real paired summaries

- Goal: keep historical locked snapshots immutable and make every Dummy/LK average represent one real authority-compatible pair rather than independently selected category maxima.
- Decision: historical snapshot evidence and current/build copy authority are separate; neither timestamp nor category winner alone may rewrite the other.
- Decision: category bests may remain useful independently, but Average is unavailable unless a real pair shares canonical owner, ordinary fingerprint, and locked/full-combat identity.

### 49.1 — Separate historical locked snapshots from copy authority (#23)

- Status: `NOT_STARTED`
- Objective:
  - Preserve capture-time locked evidence while resolving current copy authority only through a stronger exact association.
- Deliverables:
  - Explicit historical-snapshot versus current/build-authority roles in locked evidence resolution.
  - Focused later-current-state, category-order, timestamp-order, exact-authority, conflict, reload, and Sync coverage.
  - Immutable historical DPS rows when exact copy authority is absent.
- Acceptance:
  - [ ] Later current/build state cannot rewrite a historical locked snapshot by resemblance or recency.
  - [ ] Category winner and timestamp order never select copy authority by themselves.
  - [ ] Stronger exact current authority may resolve a copy operation without mutating historical evidence.
  - [ ] Conflicting or incomplete authority preserves history and reports unavailable/conflict explicitly.
  - [ ] Focused locked-evidence/DPS tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_locked_evidence_resolver.lua && luajit tests/run_stage32_leaderboard_locked_fidelity.lua`
  - `luajit tests/run_historical_locked_authority.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Historical/current expected-red matrix, focused green, and independent review receipt.

### 49.2 — Compute Average only from a real compatible Dummy/LK pair (#26)

depends_on: [49.1]

- Status: `NOT_STARTED`
- Objective:
  - Select the best real Dummy/LK pair sharing verified owner and exact ordinary plus locked/full-combat identity, or expose Average as unavailable.
- Deliverables:
  - One pair-compatibility predicate and deterministic best-real-pair selector in the DPS projection owner.
  - Focused mixed-owner, mixed-ordinary, mixed-locked, multiple-valid-pair, missing-authority, ordering, and reload coverage.
  - Preservation of independently useful category bests without synthesizing their mean.
- Acceptance:
  - [ ] Every displayed Average comes from two actual records with the same verified canonical owner.
  - [ ] The pair shares the same ordinary fingerprint and locked fingerprint/full-combat identity.
  - [ ] Mixed owners or incompatible builds never produce an Average even when each is a category best.
  - [ ] Multiple valid pairs choose the deterministic best real pair; no valid pair reports Average unavailable.
  - [ ] Dummy and LK category bests remain independently available without implying a pair.
  - [ ] Focused DPS/board/UI tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_dps_boards.lua && luajit tests/run_leaderboard_ui.lua`
  - `luajit tests/run_paired_dps_summary.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Pairing expected-red/green matrix, exact summary receipts, and independent Spec/Standards review.
