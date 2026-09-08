# CONTEXT

## Authority

- Work only in `C:\T3\BN\catalog-authority-22-wave1` on
  `bugfix/test19-catalog-authority-22-wave1`.
- Wave starting HEAD is `e69497d248875d4b2ff69a658ca478247a0ea02b`.
- Exact PR #68 base is `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f`.
- Accepted architecture is
  `3b5de54f56f1c27678e53b1dd7e1de742de820af`; it is design authority only.
- Governing packet is
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-1-amendment-13.json`,
  SHA-256 `292d3258f86986297b8eb55c6f9223010bc2bfdb4e4c4ffdf49b99337ab031b4`.
- Amendment 9 changes the PR #68 locked-payload old-side outcome to documented
  characterization while preserving continued exact new-side emission.
- The user authorized temporary Codex implementation takeover and then stated:
  `Authorize the Vibe-state reconciliation and continue RC-006.`

## Current State

- Coordinator tally before this implementation: 18 CLOSED, 0 IN PROGRESS, 1
  NOT STARTED (`MASTER-RC-006`). All 19 roots are now implementation-complete;
  RC-006 still needs frozen-candidate validation and independent acceptance.
- Fresh takeover suite: `Lua suite: 242/242 passed`, `SUITE_EXIT_CODE=0`, with
  the single authorized manual SavedVariables skip.
- Working inventory after RC-006: 147 tracked modifications plus 14 untracked
  files, 161 total. Amendment 13 covers 160 paths. The user's prospective Vibe
  reconciliation authorization covers `.vibe/CONTEXT.md`; combined scope has
  zero outside paths and zero protected changes.
- HEAD and tree remain
  `e69497d248875d4b2ff69a658ca478247a0ea02b` /
  `2e2abfee55d741cd80b5ba82d13bca7b50a89d7e`.
- `postExpiry=3` remains unchanged. `SRP-STORE-STATE-01` passes its two-direction
  proof.
- RC-006 work-frontier proof passes `11/11`, including both fail-capability
  controls. All 16 affected fixture oracles pass. The current Lua inventory
  passes `243/243`; Fast passes 223 checks with no failure or unavailable check
  and one expected committed-range skip because no `BaseRef` was supplied.

## RC-006 Contract

- Root: public admission, readmission, cursor, and commit paths bypass the
  bounded V1 work frontier.
- Required result: move continued work to the coordinator/scheduler. Precompute
  ordered vectors, winner replacement, and copy frontiers outside protected
  commit.
- Required proof: one slice per public admission call, constant-work Begin,
  bounded Next and `COPY_PENDING`, persistent `nextIndex`, maximum-root work, and
  zero variable scans inside protected commit.
- Authorized production paths: `core/BuildCatalog.lua`,
  `core/DataCompaction.lua`, `core/DataRetention.lua`,
  `core/CommunityController.lua`, and `core/SyncCompatibility.lua`.
- Authorized supporting paths include `tests/**` only when explicitly listed in
  Amendment 13 and `CONTRACTS.md`. Check membership before every new path edit.
- Amendment 7 opens thirteen frontier fixtures. Amendment 12 opens
  `tests/run_leaderboard_refresh_budget.lua` and
  `tests/run_stage24_share_convergence_characterization.lua` for bounded
  drive-to-admission migration.

## Safety Boundaries

- Never edit a protected path. The surviving protected set includes
  `core/MainCommands.lua`, `core/SyncDiagnostics.lua`,
  `core/SyncTransport.lua`, `data/**`, `docs/**`, `logic/**`, `package.json`,
  `package-lock.json`, and `tools/**`.
- An existing test path not explicitly present in Amendment 13 needs an immutable
  successor amendment before edit. Never authorize it retroactively.
- Preserve Lua 5.1, WoW 3.3.5a, protocol 7, exact 79/6/85 semantics, expected
  counts, and all closed-root behavior.
- Do not access live SavedVariables, package, install, run native validation,
  publish, push, modify a PR, merge, force-push, start Wave 2, or delete history.
- Claude remains the normal writer. Verify `claude auth status` and one real tool
  execution before handback. Finish only the current atomic edit or running
  validation before stopping for handback.

## Validation and Review Boundary

- Use focused RC-006 proof during implementation, then affected subsystem
  matrices, Fast, exact path accounting, residual reconciliation, and a current
  complete Lua inventory.
- After all 19 roots are complete, create exactly one candidate freeze commit.
  Record commit, tree, parent, and exact path inventory. Make no later commit.
- Run exact-head Fast and Full on the frozen candidate. Read the exact N/N result
  and scan for genuine failures.
- This writer never performs acceptance review. Fresh independent Codex sessions
  perform SPEC, STANDARDS, and ADVERSARIAL review. A separate fresh Codex session
  performs MASTER aggregation.
