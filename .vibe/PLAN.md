# PLAN

## Stage 50 â€” Sync Trust package partition

- Goal: publish Package A as a small reviewable trust boundary, then stop before
  the separately designed Package B catalog-authority state machine.
- Decision: Package A owns issues #24, #27, and #31 only.
- Decision: Package B owns issue #22 and every catalog admission, tombstone,
  retention, compaction, semantic-envelope, and rollback authority change.

### 50.1 â€” Publish Package A (#24, #27, #31)

- Status: `IN_PROGRESS`
- Objective:
  - Publish one clean draft PR directly atop exact PR #67.
- Deliverables:
  - Reversible inert presentation for untrusted remote text.
  - No unsolicited remote developer-status reply.
  - Peer versions retained as bounded observations without release authority.
  - Focused regressions, exact-head local gates, and exact-head GitHub CI.
- Acceptance:
  - [x] Raw storage and evidence remain lossless and separate from display text.
  - [x] Rich-text and focused EditBox sinks receive inert projections.
  - [x] Remote WLRQ handling is inert without rejection spam or pending state.
  - [x] Peer observations cannot create or preserve authoritative update notices.
  - [x] Package B and typed-digest owners remain outside the diff.
  - [x] Independent Spec and Standards reviews pass.
  - [ ] Final exact-head Fast and Full pass.
  - [ ] Draft PR and required exact-head CI pass.
- Evidence:
  - `.vibe/EVIDENCE.md` Stage 50.1 reconstruction and review receipt.

### 50.2 â€” Define Package B catalog authority (#22)

depends_on: [50.1]

- Status: `DONE`
- Objective:
  - Define one architecture-approved catalog-authority state machine before any
    Package B implementation.
- Acceptance:
  - [x] Master review supplies the authority model and bounded implementation
    contract after Package A publication.
  - [x] No Package B product, test, branch, or worktree work starts early.
- Evidence:
  - Accepted architecture commit `3b5de54f56f1c27678e53b1dd7e1de742de820af`
    supplies `docs/SYNC_TRUST_PACKAGE_PARTITION_AUDIT.md` and
    `docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md` as design authority
    only; neither is merged nor cherry-picked into the product range.

### 50.3 - Controlled tester stabilization after rejected Wave 3 (#22)

depends_on: [50.2]

- Status: `IN_REVIEW`
- Objective:
  - Complete one finite controlled tester-stabilization attempt from frozen Wave 3.
    Correct MASTER-W3-002, 007, and 010 through real consumers. Assess 009 and
    characterize 003-006. Defer 001/008 under the explicit tester contract unless a
    normal enabled trigger is demonstrated. Preserve the historical Wave 3 FAIL and
    3/3/0 counters. One freeze and one independent tester-profile campaign; no
    automatic post-review repair.
- Deliverables:
  - Three real-consumer corrections, synthetic persistence assessment, exact CI
    classifications, bounded work measurements, and one explicit tester profile.
- Acceptance:
  - [x] CI causes reproduced and classified; exact fixture/instrumentation corrections.
  - [x] DPS adoption and synthetic serialization/reload proven through public operations.
  - [x] Manual Sync readiness and cancellation proven through actual command/UI paths.
  - [x] Publication UI pending and terminal ownership proven through actual button path.
  - [x] Sidecar and ordinary/max performance dispositions recorded without hiding failures.
  - [x] Coherent integrated validation completed with exact deferrals and failures.
  - [ ] One candidate frozen and exact-head gates completed; no later tracked changes.
  - [ ] One independent tester-profile campaign and final aggregation completed.
- Evidence:
  - Current profile: `C:/T3/BN/receipts/TESTER_PROFILE_7efbd260.md`.
  - Append tester evidence to `.vibe/EVIDENCE.md`; preserve all historical records.
  - Start commit `7efbd2608b8f016bd405692e8669c5082a508d14`.
- Boundaries:
  - Historical Wave 3 remains FAIL; counters 3/3/0. This is a separate one-attempt
    exception, not a historical counter reset or full architectural repair.
  - No unrelated checkpoint work, GitHub write, package, installation, native WoW,
    live SavedVariables, API backend, controller mutation, or post-review repair.
