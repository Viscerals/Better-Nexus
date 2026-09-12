# PLAN

## Stage 50 â€” Sync Trust package partition

- Goal: publish Package A as a small reviewable trust boundary, then stop before
  the separately designed Package B catalog-authority state machine.
- Decision: Package A owns issues #24, #27, and #31 only.
- Decision: Package B owns issue #22 and every catalog admission, tombstone,
  retention, compaction, semantic-envelope, and rollback authority change.

### 50.1 â€” Publish Package A (#24, #27, #31)

- Status: `BLOCKED`
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

### 50.3 â€” Implement Package B catalog authority (#22)

depends_on: [50.2]

- Status: `IN_REVIEW`
- Objective:
  - Complete the second and final aggregated repair wave for `MASTER-RC-002`,
    `MASTER-RC-006`, `MASTER-RC-007`, `MASTER-RC-012`, and `MASTER-RC-017`, then
    stop at one coherent frozen candidate for exact-head validation and fresh
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
  - Stable typed winner selection across removal, reinsertion, and reload.
  - Persistent metered finalization and read paths with no public max-root scan.
  - Detached copy-on-write mutation targets and exact rollback identities.
  - Exact bounded nested-graph witness drift detection.
  - Centralized overflow-safe durable and session counter increments.
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
  - [x] Wave 1 exact-head Fast and Full pass on the frozen candidate.
  - [x] Wave 1 independent review completes and rejects the candidate with five
    confirmed repair roots.
  - [x] Fail-capable expected-red regressions cover all five Wave 2 roots.
  - [x] All five coupled Wave 2 repairs and affected invariants pass.
  - [x] One coherent Wave 2 freeze commit records exact identity and paths.
  - [ ] Wave 2 exact-head Fast and Full pass on the frozen candidate.
  - [ ] Fresh independent Wave 2 MASTER accepts the frozen candidate.
- Evidence:
  - `.vibe/EVIDENCE.md` Stage 50.3 implementation receipts.
  - Prospective Wave 2 Amendment 2 opens only `core/Store.lua` and
    `tests/run_catalog_authority_bootstrap.lua` for RC-006, RC-002, and RC-007.
    Packet SHA-256: `0e3cc02a266cc650d3a907750e34b71e2ac50f0a962e48f080035f3f528ff567`.
    Authorization: `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT2_AUTHORIZATION_2026-09-09.md`.
  - `C:\T3\BN\receipts\wave1\CLOSURE_RULINGS_2026-09-06.md`.
  - `C:\T3\BN\receipts\wave1\CODEX_TAKEOVER_BLOCKED_2026-09-07.md`.
  - `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2.json`, SHA-256
    `bed73f70161a5ca5f6ca14511dc2a4883eb09003a4915542dfdc32f94a9b1878`.
  - `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AUTHORIZATION_AND_COUNTER_2026-09-08.md`,
    SHA-256 `747837538db0dd27fe5a4324abc957b97b3781197eca3b72da9a16443e1ab9f3`.
  - `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-1.json`,
    SHA-256 `be779cd2470c2db319282d84feb2ad42008475fdc9dc8526fbbb6bd9c0310ed1`.
  - `C:\T3\BN\receipts\wave2\CODEX_WAVE2_SCOPE_CONFLICT_2026-09-08.md`,
    SHA-256 `88f5b73a1914951a6b26ad7d61815bf873f02b8f0d29572d30d0391db7130baa`.
  - `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT1_SCOPE_CONFLICT_2026-09-08.md`,
    SHA-256 `4247b989472ca8f41cd35f84a78d6eeefa6599ec61dbcd908b60c94d37a239bd`.
  - Governing Amendment 13 SHA-256
    `292d3258f86986297b8eb55c6f9223010bc2bfdb4e4c4ffdf49b99337ab031b4`.
- Current executable chain:
  - Valid prospective Amendment 9 and its authorization receipt are immutable
    before all nine requested-path edits -> strict validation and actual
    implementation dispatch -> bounded terminal-owner fixture repairs -> focused
    affected invariants and correct-environment isolated-tree proofs -> current
    complete inventory -> Fast with BaseRef -> one freeze -> exact-head Fast/Full
    -> fresh isolated SPEC/STANDARDS/ADVERSARIAL -> separate MASTER -> conditional
    local package and recoverable installation -> stop at the human checkpoint
    before live WoW testing.
  - Prospective Amendment 3 adds exactly the seven tests in its pathToRoots map.
    Packet SHA-256 0080c1f1847d653c24680d66c8695de7aa149b91827a0b51bff8654e33ebfc09;
    authorization SHA-256 e8e8d19e494006b73470d999ae1a37497d2ef9a2a355eeacbb12a146c246bb74.
  - Local diagnostic archive verified 99/99 files with originals retained.
    Amendment 3 and settings issues are resolved; actual current-turn high is verified.
  - Repair/evidence counters remain 2/2 and 1/1. No acceptance condition changed.
  - Separate current-settings receipt SHA-256 240aacdc2115a9e50ccac12eae911140f2d0af875d43d7d8e3b04a497ea22a07; prior medium-turn evidence and immutable Amendment 3 remain unchanged.
  - New scope boundary: CODEX_WAVE2_POST_A3_SCOPE_BOUNDARY_2026-09-10.json,
    SHA-256 f5b3759dc06f4712f4f78a335072dc52652c068c0a5d226706d449ecec08115d.
    One existing evidence owner and fifteen existing offline tests require
    prospective scope. Current work budget remains red at WB-19/WB-20.
  - Direct authority resolved that boundary before any added-path edit.
    Prospective Amendment 4 SHA-256
    9870cd7356b5d99ade5a93ee7b625c3ebebbe70c03a9fc4fd22bd582a17dea8b;
    authorization receipt SHA-256
    a0e820e967c7121f2856092fd8e4528e7f43095a2acbefa9744fff972961c505.
    This existing task is authorized as sole writer on gpt-5.6-sol/max.
  - Current dirty Fast completed in 5047.359s with 105 passed, 4 failed, 1
    nonblocking no-BaseRef skip, and 0 unavailable. The artifact-path failure is
    corrected. Three unchanged original tests require terminal pending-ticket
    fixture handling. Archived manifest SHA-256:
    05f3232736dec93bd9330d170762ebfc3201ff2c3c81377499756d2f92adcb96.
  - Exact prospective Amendment 5 packet SHA-256:
    97e9748b9b96573f4e15f729657c362253d237a4690450ff0cb9e6a33a27b2d9.
    Authorization receipt SHA-256:
    e794c7b8e2c99a0050c99c47e1af966d871cbada93e6f7aeef5492a4f1e0be68.
    It names only three existing tests and maps them only to MASTER-RC-006.
    Both artifacts preceded every target edit.
  - Amendment 8 is the valid prospective pre-edit successor for exactly
    `tests/run_candidate_revision_scope.lua`, mapped only to `MASTER-RC-006`.
    Packet SHA-256:
    da1d269326a7f66bb4536ec75acb38b78a2d8e47104081162e93fee9965082ee.
    Authorization receipt SHA-256:
    3d14ef7b5116025d09f17c4b0c7edd731acc7ecbfd08b7213e429610d313547a.
    Flawed Amendment 6 and incomplete Amendment 7 remain preserved and
    unconsumed. This prospective replacement is not an evidence-only correction.
  - Amendment 8 implementation passes 30 checks. A later complete current
    inventory passed 232/243 with one explicit manual SavedVariables skip. The
    preserved log SHA-256 is
    b6c0878d894ff7161346c9350b613e15c5196e442d931f63cc79414cc9e1d8e6.
    Two isolated-tree failures are invalid because Git safe-directory injection
    was omitted. Nine unchanged fixtures observe catalog state before bounded
    terminal publication.
  - Prospective Amendment 9 adds exactly those nine existing offline tests,
    mapped only to `MASTER-RC-006`, and no production path. Packet SHA-256:
    1777dba0a396770c3f45051cf9188d96668794fd4c991e74120f4a25245c56d8.
    Authorization receipt SHA-256:
    c232df236846039e9245143d4074801ea422c6997616a8eb117ab236a5f92720.
    All nine paths matched `HEAD` through packet and receipt creation.
  - Final implementation proof passes 46/46 modified focused tests, the current
    Lua inventory 243/243, and pre-freeze Fast 230/230. Fast has zero failed,
    unavailable, or skipped checks. Exact scope accounting is 62/62 with zero
    protected or outside path. Ordinal LF path-list SHA-256:
    fe67a7868304a03bb23114ba784d5d95412489d48de78dc73beadf97dea396ee.
  - Scoped GitHub and CI writes are authorized by separate receipt SHA-256
    e5f5df8c45abeac2cf58d92e8361e9be4ed3e10d272ae154f04f1c50794a8ab9.
    This does not alter exact-head, independent acceptance, or live-test gates.
  - Standing automation receipt SHA-256:
    7bb84443ac2b912fd2a5d32d11b0612f3919a92d83d19e16ca57cc3e334c5b11.
    Routine work remains automatic through package and recoverable installation;
    live WoW testing remains a human checkpoint.
  - Separate conditional local package/install/native-test authority receipt
    SHA-256:
    3510642c806ea6755d2cad923bd6311a023c035fecb1ee4ab8a9c60b26e6d981.
    Scoped task-branch, task-PR, relevant CI, and accepted tester/prerelease
    GitHub writes are governed by the separate GitHub/CI authority receipt.
    Merge, protected/default-branch push, and force-push remain prohibited.
