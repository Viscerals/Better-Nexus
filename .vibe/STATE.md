# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 50
- Checkpoint: 50.3
- Status: IN_REVIEW
- Branch: `refactor/test19-catalog-authority-22-wave2`
- Starting head: rejected Wave 1 candidate `22c1553a018af9543c9b596d49cf5a9e7d776ffd`
- Worktree: `C:\T3\BN\catalog-authority-22-wave2`
- Base: exact PR #68 head `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f`

## Objective (current checkpoint)

Complete the second and final aggregated repair wave for `MASTER-RC-002`,
`MASTER-RC-006`, `MASTER-RC-007`, `MASTER-RC-012`, and `MASTER-RC-017` from the
rejected Wave 1 MASTER result. Then freeze one coherent candidate for exact-head
validation and fresh independent review.

## Deliverables (current checkpoint)

- Generation-bound resumable bounded admission publishing one root.
- Collision-free typed identity and explicit authority-state transitions.
- Strict future-schema read-only isolation and unknown-field preservation.
- Atomic tombstone replacement with deny-only reservations and a private
  one-shot readmission claim.
- Bounded identity/fingerprint indexes, cursors, and status accounting.
- Retention and compaction as transactions bound to the exact database.
- Rollback/restart, mixed-client, protocol-7, and Package A compatibility.
- Stable typed winner selection across removal, reinsertion, and reconstruction.
- Persistent metered finalization, witness, replacement, registry, and read paths.
- Detached copy-on-write mutation targets with exact rollback identities.
- Exact bounded nested-graph drift detection.
- Centralized overflow-safe durable and session counter increments.

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
- [x] Wave 1 exact-head Fast and Full passed on the frozen candidate.
- [x] Fresh Wave 1 independent review completed and rejected that candidate with
  five confirmed repair roots.
- [x] Fail-capable expected-red regressions cover all five Wave 2 roots.
- [x] All five coupled repairs and affected original-root invariants pass.
- [x] One coherent Wave 2 freeze commit records its exact identity and paths.
- [ ] Wave 2 exact-head Fast and Full pass on the frozen candidate.
- [ ] Fresh independent Wave 2 MASTER accepts the frozen candidate.

## Evidence

- path: .vibe/EVIDENCE.md
- Amendment 2 and successor-writer authority were recorded before this reconciliation:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-2.json`,
  SHA-256 `0e3cc02a266cc650d3a907750e34b71e2ac50f0a962e48f080035f3f528ff567`;
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT2_AUTHORIZATION_2026-09-09.md`,
  SHA-256 `21407b2299d9e34ffa112d57aeefb213b372cddcbb8ac4aaf2e1a4b2dc17a2a1`.
- Prospective Amendment 4 and its direct authorization receipt were recorded
  before any added-path edit:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-4.json`,
  SHA-256 `9870cd7356b5d99ade5a93ee7b625c3ebebbe70c03a9fc4fd22bd582a17dea8b`;
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT4_AUTHORIZATION_2026-09-10.md`,
  SHA-256 `a0e820e967c7121f2856092fd8e4528e7f43095a2acbefa9744fff972961c505`.
- Current failed Fast evidence is preserved under
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_DIRTY_FAST_2026-09-11`, manifest
  SHA-256 `05f3232736dec93bd9330d170762ebfc3201ff2c3c81377499756d2f92adcb96`.
- Prospective Amendment 5 and its authorization receipt were recorded before
  any added-path edit:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-5.json`,
  SHA-256 `97e9748b9b96573f4e15f729657c362253d237a4690450ff0cb9e6a33a27b2d9`;
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT5_AUTHORIZATION_2026-09-11.md`,
  SHA-256 `e794c7b8e2c99a0050c99c47e1af966d871cbada93e6f7aeef5492a4f1e0be68`.
- Valid prospective Amendment 8 and its authorization receipt were recorded
  before `tests/run_candidate_revision_scope.lua` changed:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-8.json`,
  SHA-256 `da1d269326a7f66bb4536ec75acb38b78a2d8e47104081162e93fee9965082ee`;
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT8_AUTHORIZATION_2026-09-11.md`,
  SHA-256 `3d14ef7b5116025d09f17c4b0c7edd731acc7ecbfd08b7213e429610d313547a`.
  Flawed Amendment 6 and incomplete Amendment 7 remain immutable and
  unconsumed; neither grants edit authority.
- Valid prospective Amendment 9 and its authorization receipt were recorded
  before any of its nine target tests changed:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-9.json`,
  SHA-256 `1777dba0a396770c3f45051cf9188d96668794fd4c991e74120f4a25245c56d8`;
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT9_AUTHORIZATION_2026-09-11.md`,
  SHA-256 `c232df236846039e9245143d4074801ea422c6997616a8eb117ab236a5f92720`.
  It adds zero production paths and exactly nine unchanged offline tests mapped
  only to `MASTER-RC-006`.
- The failed 232/243 inventory is preserved byte-exact under
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_A8_DIRTY_LUA_INVENTORY_2026-09-11`.
  Its log SHA-256 is
  `b6c0878d894ff7161346c9350b613e15c5196e442d931f63cc79414cc9e1d8e6`;
  its manifest SHA-256 is
  `e3322c323a8122776963df3f6b181f26c1030bd66dc5af4570735ca8fe99996b`.
- Later direct user authority permits scoped GitHub and CI writes for this task.
  Separate receipt:
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_GITHUB_CI_AUTHORIZATION_2026-09-11.md`,
  SHA-256 `e5f5df8c45abeac2cf58d92e8361e9be4ed3e10d272ae154f04f1c50794a8ab9`.
  Immutable earlier packets remain unchanged.
- Standing automation authority through clean package and recoverable local
  installation is recorded at
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_STANDING_AUTOMATION_AUTHORIZATION_2026-09-11.md`,
  SHA-256 `7bb84443ac2b912fd2a5d32d11b0612f3919a92d83d19e16ca57cc3e334c5b11`.
  Live WoW testing remains a human checkpoint.
- Conditional local delivery authority:
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_LOCAL_DELIVERY_AUTHORIZATION_2026-09-11.md`,
  SHA-256 `3510642c806ea6755d2cad923bd6311a023c035fecb1ee4ab8a9c60b26e6d981`.
- Governing packet:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2.json`,
  SHA-256 `bed73f70161a5ca5f6ca14511dc2a4883eb09003a4915542dfdc32f94a9b1878`.
- Prospective successor packet:
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-1.json`,
  SHA-256 `be779cd2470c2db319282d84feb2ad42008475fdc9dc8526fbbb6bd9c0310ed1`.
- Amendment 1 successor-scope conflict:
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AMENDMENT1_SCOPE_CONFLICT_2026-09-08.md`,
  SHA-256 `4247b989472ca8f41cd35f84a78d6eeefa6599ec61dbcd908b60c94d37a239bd`.
- Resolved scope-conflict receipt:
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_SCOPE_CONFLICT_2026-09-08.md`,
  SHA-256 `88f5b73a1914951a6b26ad7d61815bf873f02b8f0d29572d30d0391db7130baa`.
- Wave 2 authorization receipt:
  `C:\T3\BN\receipts\wave2\CODEX_WAVE2_AUTHORIZATION_AND_COUNTER_2026-09-08.md`,
  SHA-256 `747837538db0dd27fe5a4324abc957b97b3781197eca3b72da9a16443e1ab9f3`.
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
  `You've hit your weekly limit Ã‚Â· resets Sep 12, 1pm (America/New_York)`.
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
- Wave 1 exact-head Fast and Full passed. Fresh independent MASTER rejected the
  candidate with exactly five confirmed repair roots. The user authorized the
  second and final aggregated repair wave and conditional post-acceptance
  packaging, publication, and installation.
- Created the immutable Wave 2 packet and authorization receipt before changing
  this copied workflow. The Wave 2 start is clean at commit
  `22c1553a018af9543c9b596d49cf5a9e7d776ffd`, tree
  `b0225f21853ba04023fc42bdd7a018da23cfd87c`.
- A bounded max-root mutation required explicit pending acknowledgements in six
  existing owners and one scheduler pump. The writer stopped before those
  paths, recorded the conflict, received direct authority for exactly seven
  production and seven test paths, and created immutable Wave 2 successor
  packet Amendment 1 before any newly authorized path edit.
- Current dirty Fast completed in `5047.359s`: 105 passed, 4 failed, 1
  nonblocking no-BaseRef skip, and 0 unavailable. The artifact-path failure is
  locally corrected and a direct path-policy probe passes 49 paths with zero
  violations. Three unchanged original tests still treat
  `ROOT_MUTATION_PENDING` as terminal. They require prospective scope before a
  fixture edit; changing production to make their work synchronous would violate
  `MASTER-RC-006`.
- The user approved the exact three-test Amendment 5 request. The prospective
  immutable packet and durable authorization receipt were created and hashed
  before any target edit. The later standing instruction authorizes routine
  work through accepted packaging and recoverable installation without repeat
  approval. It does not authorize live WoW action.
- The three Amendment 5 fixture repairs and their current focused proofs pass.
  A later affected-root run exposed one unchanged synchronous `Catalog.Put`
  assumption in `tests/run_candidate_revision_scope.lua`. Amendment 8 grants
  prospective authority for that one test only, mapped only to `MASTER-RC-006`.
- The Amendment 8 candidate-revision fixture now passes 30 checks with its four
  direct writes routed through one strict terminal owner. A complete current
  inventory then passed 232/243. Two isolated-tree results are invalid because
  the run omitted Git safe-directory injection. The other nine failures are
  unchanged fixtures that observe bounded catalog work before terminal state;
  Amendment 9 now grants exact prospective authority for those nine tests.
- Strict installed validation and actual
  `implement / prompt.checkpoint_implementation` dispatch preceded every
  Amendment 9 edit. All nine fixtures now await the same exact terminal ticket
  and retain their original assertions, byte checks, refusal cases, and mixed-
  peer oracles.
- The 46-test modified-path batch passes 46/46. The complete current Lua
  inventory passes 243/243 with the single explicit manual SavedVariables
  runner skipped. The pre-freeze Fast gate passes 230/230 in 4851.799 seconds
  with zero failed, unavailable, or skipped checks.
- The final pre-freeze inventory is exactly 62 tracked paths. It equals the
  valid parent plus Amendments 1, 2, 3, 4, 5, 8, and 9 path union. It has zero
  staged, untracked, protected, or outside paths. Its ordinal LF path-list
  SHA-256 is
  `fe67a7868304a03bb23114ba784d5d95412489d48de78dc73beadf97dea396ee`.

## Workflow state

- [ ] RUN_STOPPED
- [ ] RUN_CONTEXT_CAPTURE
- [x] STAGE_DESIGNED
- [x] MAINTENANCE_CYCLE_DONE
- [ ] RETROSPECTIVE_DONE
- [ ] PROCESS_IMPROVEMENTS_DONE

## Resolved scope issues

- [x] ISSUE-W2-STORE-PENDING: Prospective Store pending-owner repair scope
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: agent
  - Unblock Condition: Satisfied by the direct replacement-writer handoff and prospective Amendment 2.
  - Evidence Needed: Verified Amendment 2 and authorization receipt above; both added files still match their pre-edit hashes.
  - Notes: Scope issue only is resolved. The Store early acknowledgement defect remains an incomplete Wave 2 implementation item. No repair or acceptance is claimed.

- [x] ISSUE-W2-TEST-PENDING: Prospective seven-test pending-owner fixture scope
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: human
  - Unblock Condition: Direct user approval for the exact seven existing tests in the successor scope boundary receipt, then a prospective immutable amendment and authorization receipt before any added path edit.
  - Evidence Needed: CODEX_WAVE2_SUCCESSOR_SCOPE_BOUNDARY_2026-09-10.md, SHA-256 45bef93cb111a53cb0ab504089c39ebab44974d475892707d26b1047f39cd343.
  - Notes: Automatic review rejected the attempted Amendment 3. No amendment exists and no proposed path changed. Seven failed fixture commands remain unresolved. No third wave, new root, production path, architecture semantic, evidence correction, or delivery authority is proposed.
  - Resolution: Direct seven-test approval recorded prospectively in Amendment 3 and authorization receipt before any test edit. Local diagnostic archive has 99 verified files; originals retained. This resolves scope only, not fixture failures.

- [x] ISSUE-W2-REASONING-SETTING: Verify required high reasoning for the same writer
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: human
  - Unblock Condition: This same Codex chat reports gpt-6-astra and high reasoning in actual current-turn metadata before product/test edits.
  - Evidence Needed: turn_context for the next execution turn; current turn 01a08c6b-6bd8-7b02-b05b-59fb337cefa9 reports medium at 2026-09-10T17:44:06.680Z.
  - Notes: No scope approval remains pending. The user explicitly requires high. No tool to change active reasoning was found. No new writer or product/test edit was started at medium. Administrative packet and local-log preservation are complete.
  - Resolution: Current turn 01a08c89-34fa-70e3-8000-852b5efb3909 verifies openai/gpt-6-astra/high at 2026-09-10T18:16:38.806Z. Separate immutable current-settings receipt SHA-256 240aacdc2115a9e50ccac12eae911140f2d0af875d43d7d8e3b04a497ea22a07. Prior medium metadata remains unchanged. The later bounded provider-routing exception, SHA-256 d5d64daca37e436910f21d1edb33cbb8d80335281afc6acf8c909233e1aedd4e, prospectively authorizes this same task on openai/gpt-5.6-sol/max. Current turn 01a091b6-0728-7c42-9980-65d64f01763d verifies that route at 2026-09-11T18:23:40.935Z.

- [x] ISSUE-W2-EVIDENCE-FIXTURE-SCOPE: Prospective evidence-owner and fifteen-test scope
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: human
  - Unblock Condition: Direct approval for exactly the sixteen existing paths and mappings in CODEX_WAVE2_POST_A3_SCOPE_BOUNDARY_2026-09-10.json, followed by a prospective immutable Amendment 4 and durable authorization receipt before any added-path edit.
  - Evidence Needed: Boundary SHA-256 f5b3759dc06f4712f4f78a335072dc52652c068c0a5d226706d449ecec08115d; complete inventory 228/243, exit 1; current work budget 18/20 with WB-19/WB-20 red.
  - Notes: core/LoadoutEvidence.lua maps only to MASTER-RC-006/002; fifteen existing offline tests map only to MASTER-RC-006. No new wave, root, architecture semantic, evidence correction, protected path, or delivery authority is granted.
  - Resolution: Direct scope and gpt-5.6-sol/max provider-exception authority were recorded prospectively in Amendment 4 and its authorization receipt. All sixteen pre-edit hashes and byte counts matched the approved boundary. This resolves scope and routing only; implementation and validation remain incomplete.

- [x] ISSUE-W2-AMENDMENT5-FIXTURE-SCOPE: Prospective three-test terminal-owner fixture scope
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: human
  - Unblock Condition: Direct user approval for exactly the three existing tests in `CODEX_WAVE2_AMENDMENT5_SCOPE_REQUEST_2026-09-11.md`, mapped only to `MASTER-RC-006`, followed by a prospective immutable Amendment 5 packet and durable authorization receipt before the first requested-path edit.
  - Evidence Needed: Amendment 5 packet SHA-256 `97e9748b9b96573f4e15f729657c362253d237a4690450ff0cb9e6a33a27b2d9`; authorization receipt SHA-256 `e794c7b8e2c99a0050c99c47e1af966d871cbada93e6f7aeef5492a4f1e0be68`; scope request SHA-256 `ad5271c5ea4c8756c9f5f90449a58be8549d4494e5c665bae4a7ffff9c5f91b5`.
  - Notes: All three tests still matched their bound pre-edit hashes when the packet and receipt were created. No production path, root, architecture semantic, third wave, counter reset, evidence correction, or relaxed gate was added.
  - Resolution: The exact direct answer `yes` and the standing automation instruction are bound prospectively. Implementation remains incomplete and requires supported Vibe resume, strict validation, and actual implementation dispatch.

- [x] ISSUE-W2-AMENDMENT8-FIXTURE-SCOPE: Prospective candidate-revision fixture scope
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: agent
  - Unblock Condition: Create one valid prospective immutable packet and authorization receipt for exactly `tests/run_candidate_revision_scope.lua`, mapped only to `MASTER-RC-006`, before its first edit.
  - Evidence Needed: Amendment 8 packet SHA-256 `da1d269326a7f66bb4536ec75acb38b78a2d8e47104081162e93fee9965082ee`; authorization receipt SHA-256 `3d14ef7b5116025d09f17c4b0c7edd731acc7ecbfd08b7213e429610d313547a`; pre-edit test SHA-256 `5f8d837b0053565014fd8a2ef401c07370e0dc624f51fd65ecd5741af6493beb`.
  - Notes: Amendment 6 has an incorrect Amendment 5 receipt digest and remains unconsumed. Amendment 7 is incomplete JSON and grants no authority. No target edit used either artifact.
  - Resolution: Amendment 8 records a prospective pre-edit packet replacement. It is not an evidence-only correction and does not change the 1/1/0 evidence-correction counter. Strict validation and actual implementation dispatch preceded the target edit; its focused proof now passes 30 checks.

- [x] ISSUE-W2-AMENDMENT9-FIXTURE-SCOPE: Prospective nine-test terminal-owner fixture scope
  - Impact: BLOCKER
  - Status: RESOLVED
  - Owner: agent
  - Unblock Condition: Create one valid prospective immutable packet and authorization receipt for the nine unchanged tests named by the preserved 232/243 inventory, mapped only to `MASTER-RC-006`, before their first edit.
  - Evidence Needed: Amendment 9 packet SHA-256 `1777dba0a396770c3f45051cf9188d96668794fd4c991e74120f4a25245c56d8`; authorization receipt SHA-256 `c232df236846039e9245143d4074801ea422c6997616a8eb117ab236a5f92720`; preserved log SHA-256 `b6c0878d894ff7161346c9350b613e15c5196e442d931f63cc79414cc9e1d8e6`.
  - Notes: All nine targets matched `HEAD` through packet and receipt creation. This adds zero production paths and no new root, semantic, repair wave, counter change, evidence correction, or relaxed gate.
  - Resolution: Standing automation authority created exact prospective Amendment 9 before any target edit. Strict Vibe validation and actual implementation dispatch preceded implementation. All nine focused fixtures and the complete current suite now pass.

## Active issues

- None.

## Blockers

- None.

## Deferred work

- Local packaging and recoverable installation are authorized only after
  exact-head validation and valid independent MASTER acceptance. Stop and notify
  the user before live WoW testing.
- Scoped task-branch, pull request, relevant CI, and accepted tester/prerelease
  GitHub writes are authorized by the separate 2026-09-11 receipt. Verify the
  exact repository, remote, branch, workflow, and publication target first.
  Merge, protected/default-branch push, force-push, history deletion, unrelated
  PR #59 work, production deployment, paid-service mutation, live SavedVariables
  access, game restart/reload, and legacy-campaign mutation remain unauthorized.
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

- The final implementation loop passes the 46 modified focused tests, all
  243 current Lua programs, and pre-freeze Fast 230/230. Exact path accounting
  is 62/62 with zero protected or outside path. Flawed Amendments 6 and 7 remain
  preserved and unconsumed. The candidate is ready for exact-head review.

## Recommended next action

- Strictly validate this `IN_REVIEW` state, create the single coherent Wave 2
  freeze commit, and record its commit, tree, parent, and exact 62-path inventory
  in `C:/T3/BN/receipts/wave2/CODEX_WAVE2_FREEZE_2026-09-12.md`. Then run Fast
  and one Full gate on that exact clean commit before fresh isolated SPEC,
  STANDARDS, ADVERSARIAL, and separate MASTER review.
