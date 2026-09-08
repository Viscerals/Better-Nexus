# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 50
- Checkpoint: 50.3
- Status: IN_REVIEW
- Branch: `bugfix/test19-catalog-authority-22-wave1`
- Starting head: rejected candidate `e69497d248875d4b2ff69a658ca478247a0ea02b`
- Worktree: `C:\T3\BN\catalog-authority-22-wave1`
- Base: exact PR #68 head `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f`

## Objective (current checkpoint)

Complete `MASTER-RC-006`, the only open root in the accepted 19-root Catalog
Authority Repair Wave 1 aggregate, then freeze one clean locally validated
candidate for fresh independent review.

## Deliverables (current checkpoint)

- Generation-bound resumable bounded admission publishing one root.
- Collision-free typed identity and explicit authority-state transitions.
- Strict future-schema read-only isolation and unknown-field preservation.
- Atomic tombstone replacement with deny-only reservations and a private
  one-shot readmission claim.
- Bounded identity/fingerprint indexes, cursors, and status accounting.
- Retention and compaction as transactions bound to the exact database.
- Rollback/restart, mixed-client, protocol-7, and Package A compatibility.
- One-slice public admission and readmission, constant-work cursor Begin,
  bounded Next and copy frontiers, persistent `nextIndex`, and zero variable
  scans inside protected commit.

## Acceptance (current checkpoint)

- [x] A behavioral expected-red matrix is recorded on exact PR #68 before any
  product edit, using only public seams that already exist on that base.
- [x] The focused Package B matrix passes on real public production seams.
- [x] The current complete Lua inventory passes `243/243` with the single explicit
  manual SavedVariables skip.
- [x] Parse, integration, module contracts, upvalue, workflow policy, Release
  Policy, security, artifact, and diff checks pass.
- [x] No rejected-candidate implementation is imported and no protected path is
  modified.
- [x] `MASTER-RC-006` passes its `11/11` work-frontier matrix, including both
  fail-capability controls, maximum-root, copy-frontier, persistent-index, and
  protected-commit proofs.
- [ ] Final exact-head Fast and Full on the frozen candidate.
- [ ] Independent review of the frozen candidate.

## Evidence

- path: .vibe/EVIDENCE.md
- Governing packet:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-1-amendment-13.json`,
  SHA-256 `292d3258f86986297b8eb55c6f9223010bc2bfdb4e4c4ffdf49b99337ab031b4`.
- Takeover receipt:
  `C:\T3\BN\receipts\wave1\CODEX_TAKEOVER_BLOCKED_2026-09-07.md`.
- Coordinator closure ruling: 18 roots CLOSED, 0 IN PROGRESS, and only
  `MASTER-RC-006` NOT STARTED.
- Behavioral expected red on exact PR #68: `ENV-01`, `ENV-02`, `ENV-03`,
  `READ-01`, `SNAP-01`, and `TOMB-01` all fail on the base for their stated
  behavioral reasons, and the run proves product bytes unchanged.
- Rejected candidate `8b8718eb0a487cd1f806b5150abea39a17f91850` was inspected as
  diagnostic evidence only. An added-line comparison over `core/BuildCatalog.lua`
  shares `9` long lines out of `2455`; `8` are already present in the exact base
  file and the ninth is a two-field assignment of base-existing summary fields.

## Work log

- Reconciled the repository, exact PR #68 head, the accepted architecture
  commit, issue #22 scope, existing worktrees, and rejected-candidate
  preservation before any mutation.
- Bound a manual immutable task packet at
  `C:\T3\BN\task-packets\catalog-authority-22.json` with SHA-256
  `654c56284a36af51561daf4c8251d1f8ddaaf6978ecaf34a57e97bd61cc7c51a`. It records
  one branch-name exception: the suggested branch name is occupied by the
  preserved rejected-candidate worktree.
- Recorded the Package B case matrix red on exact PR #68, then added six
  behavioral oracles because most matrix cases fail at absent authority exports
  rather than at behavior.
- Implemented the authority owner in `core/BuildCatalog.lua` and drove the
  focused matrix to `68/68` green.
- Reconciled Package A consumers. The dominant causes were fixtures that seeded
  raw SavedVariables after binding, fixtures above the issue #22 semantic
  envelope, assertions expecting a remote delete to erase the raw row, and
  one-call collection reads above the bounded limit.
- Repair Wave 1 closed `MASTER-RC-001` through `MASTER-RC-019` except
  `MASTER-RC-006`; the current working inventory is 143 paths, all inside
  Amendment 13, with zero protected paths.
- User authorized temporary Codex implementation takeover after Claude reported
  `You've hit your weekly limit · resets Sep 12, 1pm (America/New_York)`.
- User then authorized this Vibe-state reconciliation and continuation of
  `MASTER-RC-006`.
- Implemented `MASTER-RC-006` with one V1 admission slice per public call,
  persistent admission and cursor frontiers, precomputed ordered vectors, a
  bounded defensive-copy frontier, fixed protected-commit work, and scoped
  bootstrap allowance accounting.
- Repaired all 16 affected fixture oracles. Their replay passes `16/16`; the
  current Lua inventory passes `243/243`; Fast passes with 223 checks, no
  failures or unavailable checks, and one expected no-`BaseRef` skip.
- Current inventory is 147 tracked modifications plus 14 untracked files, 161
  total. Amendment 13 covers 160. The user's prospective workflow
  reconciliation authority covers `.vibe/CONTEXT.md`. Combined scope has zero
  outside paths and zero protected changes.

## Workflow state

- [ ] RUN_STOPPED
- [ ] RUN_CONTEXT_CAPTURE
- [x] STAGE_DESIGNED
- [x] MAINTENANCE_CYCLE_DONE
- [ ] RETROSPECTIVE_DONE
- [ ] PROCESS_IMPROVEMENTS_DONE

## Active issues

- `MASTER-RC-006` implementation is complete. Candidate freeze, exact-head
  validation, and fresh independent acceptance review remain.

## Blockers

- None for the authorized RC-006 implementation role. Independent review remains
  a later acceptance gate after candidate freeze.

## Deferred work

- Publication of this candidate. No push, pull request, or GitHub change is
  authorized by this task.
- Native WoW, addon packaging, and live SavedVariables validation remain outside
  this task.
- PR #59 / issue #40 typed digest, PR #60 reconstruction, ChatThrottleLib audit,
  SyncTransport migration, WP8, and native Test 19 remain out of scope.

## Decisions

- The accepted architecture commit `3b5de54f56f1c27678e53b1dd7e1de742de820af` is
  design authority only. It is never merged or cherry-picked into the product
  range.
- `Nexus.LoadoutEvidence.SemanticLimits` owns the issue #22 envelope of 79
  ordinary, 6 locked, and 85 total copies. That semantic bound is separate from
  the 256-entry parser ceiling.
- The admitted canonical snapshot contains known fields only; the raw row stays
  the durable owner of unknown row and tuple scope.
- A delete is one atomic row-to-tombstone transaction over an exact admitted
  row. Exact replay is a no-op and a delete over a never-admitted row refuses.
- Retention and compaction run inside one maintenance transaction bound to the
  exact database, and only the commit publishes a replacement root.

## Last completed loop

- `MASTER-RC-006` implementation at HEAD
  `e69497d248875d4b2ff69a658ca478247a0ea02b`, tree
  `2e2abfee55d741cd80b5ba82d13bca7b50a89d7e`: 161 changed paths,
  zero outside the combined authorized scope, zero protected, focused proof
  `11/11`, affected replay `16/16`, complete Lua inventory `243/243`, and Fast
  223 passed with one expected no-`BaseRef` skip.

## Recommended next action

- Freeze exactly one candidate commit. Record its parent, commit, tree, and exact
  path inventory. Then run exact-head Fast and Full before dispatching fresh
  independent SPEC, STANDARDS, and ADVERSARIAL reviewers.
