# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 50
- Checkpoint: 50.3
- Status: IN_REVIEW
- Branch: `bugfix/test19-catalog-authority-22-impl`
- Starting head: exact PR #68 head `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f`
- Worktree: `C:\T3\BN\catalog-authority-22`
- Base: exact PR #68 head `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f`

## Objective (current checkpoint)

Implement the accepted Package B catalog authority state machine for issue #22
directly on exact PR #68 and stop at one clean, locally validated candidate that
is ready for later independent review.

## Deliverables (current checkpoint)

- Generation-bound resumable bounded admission publishing one root.
- Collision-free typed identity and explicit authority-state transitions.
- Strict future-schema read-only isolation and unknown-field preservation.
- Atomic tombstone replacement with deny-only reservations and a private
  one-shot readmission claim.
- Bounded identity/fingerprint indexes, cursors, and status accounting.
- Retention and compaction as transactions bound to the exact database.
- Rollback/restart, mixed-client, protocol-7, and Package A compatibility.

## Acceptance (current checkpoint)

- [x] A behavioral expected-red matrix is recorded on exact PR #68 before any
  product edit, using only public seams that already exist on that base.
- [x] The focused Package B matrix passes on real public production seams.
- [x] The complete Lua inventory passes `229/229` with the single explicit
  manual SavedVariables skip.
- [x] Parse, integration, module contracts, upvalue, workflow policy, Release
  Policy, security, artifact, and diff checks pass.
- [x] No rejected-candidate implementation is imported and no protected path is
  modified.
- [ ] Final exact-head Fast and Full on the frozen candidate.
- [ ] Independent review of the frozen candidate.

## Evidence

- path: `.vibe/EVIDENCE.md`
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

## Workflow state

- [ ] RUN_STOPPED
- [ ] RUN_CONTEXT_CAPTURE
- [x] STAGE_DESIGNED
- [x] MAINTENANCE_CYCLE_DONE
- [ ] RETROSPECTIVE_DONE
- [ ] PROCESS_IMPROVEMENTS_DONE

## Active issues

- None known inside Package B after the complete Lua inventory reached
  `229/229`.

## Blockers

- Independent review of the frozen candidate is required before any acceptance.

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

- Complete Lua inventory `229/229`, Lua 5.1 parse `303/303`, integration
  `70/70`, module contracts `11/217/165/0`, upvalue boundary `0` violations,
  workflow policy, Release Policy, security policy, artifact and diff checks,
  and Fast `120/120` with the single manual SavedVariables skip.

## Recommended next action

- Freeze one clean local commit, run the exact-head Fast and Full gates on that
  frozen candidate, and stop for independent review without publishing.
