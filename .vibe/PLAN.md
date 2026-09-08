# PLAN

## Stage 50 — Sync Trust package partition

- Goal: publish Package A as a small reviewable trust boundary, then stop before
  the separately designed Package B catalog-authority state machine.
- Decision: Package A owns issues #24, #27, and #31 only.
- Decision: Package B owns issue #22 and every catalog admission, tombstone,
  retention, compaction, semantic-envelope, and rollback authority change.

### 50.1 — Publish Package A (#24, #27, #31)

- Status: `IN_REVIEW`
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

### 50.2 — Define Package B catalog authority (#22)

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

### 50.3 — Implement Package B catalog authority (#22)

depends_on: [50.2]

- Status: `IN_REVIEW`
- Objective:
  - Complete `MASTER-RC-006`, the only open root in the accepted aggregated
    Repair Wave 1, then stop at one frozen locally validated candidate for fresh
    independent review.
- Deliverables:
  - Generation-bound resumable bounded admission with one published root.
  - Collision-free typed identity and explicit authority-state transitions.
  - Strict future-schema read-only isolation and unknown-field preservation.
  - Atomic tombstone replacement with deny-only reservations and a private
    one-shot readmission claim.
  - Bounded identity/fingerprint indexes, cursors, and status accounting.
  - Retention and compaction as transactions bound to the exact database.
  - Rollback/restart, mixed-client, protocol-7, and Package A compatibility.
  - One V1 slice per public admission call, constant-work cursor Begin, bounded
    Next and copy work, persistent frontiers, and fixed protected-commit work.
- Acceptance:
  - [x] A genuine expected-red matrix is recorded on exact PR #68 before any
    product edit.
  - [x] The focused Package B matrix passes on real public production seams.
  - [x] The complete Lua inventory, parse, integration, contracts, upvalue,
    workflow, Release Policy, security, and diff checks pass.
  - [x] No rejected-candidate implementation is imported and no protected path
    is modified.
  - [x] Eighteen roots are closed with coordinator rulings; only
    `MASTER-RC-006` remains open.
  - [x] `MASTER-RC-006` expected-red, maximum-frontier, fail-capability, focused,
    path-accounting, and residual proofs pass on the current repair.
  - [x] One candidate freeze commit records its exact commit, tree, parent, and
    path inventory.
  - [ ] Exact-head Fast and Full pass on the frozen candidate.
  - [ ] Independent review of the frozen candidate.
- Evidence:
  - `.vibe/EVIDENCE.md` Stage 50.3 implementation receipts.
  - `C:\T3\BN\receipts\wave1\CLOSURE_RULINGS_2026-09-06.md`.
  - `C:\T3\BN\receipts\wave1\CODEX_TAKEOVER_BLOCKED_2026-09-07.md`.
  - Governing Amendment 13 SHA-256
    `292d3258f86986297b8eb55c6f9223010bc2bfdb4e4c4ffdf49b99337ab031b4`.
