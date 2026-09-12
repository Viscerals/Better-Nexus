# CONTEXT

## Authority

- Work only in `C:\T3\BN\catalog-authority-22-wave2` on
  `refactor/test19-catalog-authority-22-wave2`.
- Wave 2 starts from rejected Wave 1 commit
  `22c1553a018af9543c9b596d49cf5a9e7d776ffd`, tree
  `b0225f21853ba04023fc42bdd7a018da23cfd87c`.
- Exact PR #68 base is `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f`.
- Accepted architecture is
  `3b5de54f56f1c27678e53b1dd7e1de742de820af`; it is design authority only.
- Governing packet is
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2.json`, SHA-256
  `bed73f70161a5ca5f6ca14511dc2a4883eb09003a4915542dfdc32f94a9b1878`.
- Prospective successor packet Amendment 1 is
  `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-2-amendment-1.json`,
  SHA-256 `be779cd2470c2db319282d84feb2ad42008475fdc9dc8526fbbb6bd9c0310ed1`.
  It adds exactly seven existing production owner/scheduler paths and seven
  matching existing offline tests. It maps them only to the five authorized
  MASTER roots.
- Prospective Amendment 2 adds only `core/Store.lua` and
  `tests/run_catalog_authority_bootstrap.lua`, mapped to RC-006, RC-002, and RC-007.
  Packet SHA-256: `0e3cc02a266cc650d3a907750e34b71e2ac50f0a962e48f080035f3f528ff567`.
  Its authorization receipt SHA-256 is
  `21407b2299d9e34ffa112d57aeefb213b372cddcbb8ac4aaf2e1a4b2dc17a2a1`.
- Amendment 9 changes the PR #68 locked-payload old-side outcome to documented
  characterization while preserving continued exact new-side emission.
- The user authorized the second and final repair wave for exactly
  `MASTER-RC-002`, `MASTER-RC-006`, `MASTER-RC-007`, `MASTER-RC-012`, and
  `MASTER-RC-017`. Live SavedVariables access, game restart/reload, and
  legacy-campaign mutation remain unauthorized.
  Separate direct authority permits a clean local tester package, installation,
  and safe native WoW testing only after exact-head validation and valid
  independent acceptance. Receipt SHA-256:
  `3510642c806ea6755d2cad923bd6311a023c035fecb1ee4ab8a9c60b26e6d981`.
- Prospective Amendment 4 adds exactly `core/LoadoutEvidence.lua` for
  RC-006/002 and the fifteen existing offline tests in its pathPermissions map
  for RC-006 only. Packet SHA-256:
  `9870cd7356b5d99ade5a93ee7b625c3ebebbe70c03a9fc4fd22bd582a17dea8b`.
  Authorization receipt SHA-256:
  `a0e820e967c7121f2856092fd8e4528e7f43095a2acbefa9744fff972961c505`.
- Prospective Amendment 5 adds exactly three existing offline tests for
  `MASTER-RC-006`. Packet SHA-256:
  `97e9748b9b96573f4e15f729657c362253d237a4690450ff0cb9e6a33a27b2d9`.
  Authorization receipt SHA-256:
  `e794c7b8e2c99a0050c99c47e1af966d871cbada93e6f7aeef5492a4f1e0be68`.
  Both were created before any target test edit.
- Prospective Amendment 8 adds exactly
  `tests/run_candidate_revision_scope.lua`, mapped only to `MASTER-RC-006`.
  Packet SHA-256:
  `da1d269326a7f66bb4536ec75acb38b78a2d8e47104081162e93fee9965082ee`.
  Authorization receipt SHA-256:
  `3d14ef7b5116025d09f17c4b0c7edd731acc7ecbfd08b7213e429610d313547a`.
  The target retained its bound pre-edit hash through both artifacts. Flawed
  Amendment 6 and incomplete Amendment 7 remain immutable and unconsumed.
- Prospective Wave 2 Amendment 9 adds exactly nine existing offline fixtures,
  all mapped only to `MASTER-RC-006`, and no production path. Packet SHA-256:
  `1777dba0a396770c3f45051cf9188d96668794fd4c991e74120f4a25245c56d8`.
  Authorization receipt SHA-256:
  `c232df236846039e9245143d4074801ea422c6997616a8eb117ab236a5f92720`.
  All nine targets matched `HEAD` through both artifacts.
- Standing automation authority through accepted package and recoverable local
  installation is recorded by receipt SHA-256
  `7bb84443ac2b912fd2a5d32d11b0612f3919a92d83d19e16ca57cc3e334c5b11`.
  Stop and notify the user before live WoW testing.
- Later direct user authority permits scoped GitHub and CI writes for this task.
  Receipt SHA-256:
  `e5f5df8c45abeac2cf58d92e8361e9be4ed3e10d272ae154f04f1c50794a8ab9`.
  Merge, protected/default-branch push, force-push, and unrelated work remain
  outside that authority.

## Current State

- Stage 50 checkpoint 50.3 remains incomplete. The seven-test scope issue is now
  resolved by direct user approval and prospective immutable Amendment 3. Packet:
  C:/T3/BN/task-packets/catalog-authority-22-repair-wave-2-amendment-3.json,
  SHA-256 0080c1f1847d653c24680d66c8695de7aa149b91827a0b51bff8654e33ebfc09.
- Authorization receipt: C:/T3/BN/receipts/wave2/CODEX_WAVE2_AMENDMENT3_AUTHORIZATION_2026-09-10.md,
  SHA-256 e8e8d19e494006b73470d999ae1a37497d2ef9a2a355eeacbb12a146c246bb74.
  All seven tests matched their bound hashes before edits. Terminal-work waits
  are now implemented; all 530 original assertions remain.
- The approved local archive preserves 99 files from build/verify and
  build/wave2-successor-final-checks. Every destination and original hash matched.
  Archive: C:/T3/BN/receipts/wave2/CODEX_SUCCESSOR_FAST_DIAGNOSTIC_2026-09-10.
  MANIFEST.json SHA-256 5cab452dd9d3f35c127bafea58dcd3a03e3de55adcbcee7d4a672236560418dc.
  Originals remain intact. No logs were published to GitHub; no raw Claude output.
- ISSUE-W2-REASONING-SETTING is now resolved. Same writer thread
  01a0895c-84ed-72e3-96b8-27573a831e91 has verified openai/gpt-6-astra/high in
  current turn 01a08c89-34fa-70e3-8000-852b5efb3909 at 2026-09-10T18:16:38.806Z.
  Separate receipt: C:/T3/BN/receipts/wave2/CODEX_WAVE2_HIGH_REASONING_VERIFIED_2026-09-10.json,
  SHA-256 240aacdc2115a9e50ccac12eae911140f2d0af875d43d7d8e3b04a497ea22a07.
  Prior medium-turn metadata and immutable A3 remain unchanged. No product/test
  edit precedes strict validation and actual implementation dispatch.
- Preserve repair waves used=2/max=2/remaining=0 and evidence corrections
  used=1/max=1/remaining=0. Preserve every legitimate historical acceptance flag.
- HEAD remains `22c1553a018af9543c9b596d49cf5a9e7d776ffd` at the
  pre-freeze implementation boundary. The inventory is exactly 62 tracked
  modified paths with zero staged or untracked paths. It equals the valid
  parent plus Amendments 1, 2, 3, 4, 5, 8, and 9 path union. The ordinal LF
  path-list SHA-256 is
  `fe67a7868304a03bb23114ba784d5d95412489d48de78dc73beadf97dea396ee`.
- All 46 modified focused tests pass. The complete current Lua inventory passes
  `243/243` with the single explicit manual SavedVariables runner skipped. Its
  log SHA-256 is
  `12edc2500a6444e50618fac24107f08cbf24a66c893ca92cf6dc6304336fde2d`.
- Pre-freeze Fast passes `230/230` in `4851.799s`, with zero failed,
  unavailable, or skipped checks. Its summary SHA-256 is
  `2a453b5d5d15e8d532de21e1b57799f3d140e55826cc9fb703c7c174a1839d5d`.
  The refined scan found zero failure markers across all non-parse logs.
- The source-stable inventory passed admission 24/24, maintenance 10/10,
  cursor 6/6, read purity 8/8, tombstones 28/28, navigation, mixed-client 14/14,
  and Sync semantic-envelope 23/23. All 530 original A3 assertions remain.
  ADM-08 retains its original oracle. postExpiry=3 and both Store directions pass.
- ISSUE-W2-EVIDENCE-FIXTURE-SCOPE is resolved by direct approval and
  prospective Amendment 4. Its final boundary is
  C:/T3/BN/receipts/wave2/CODEX_WAVE2_POST_A3_SCOPE_BOUNDARY_2026-09-10.json,
  SHA-256 f5b3759dc06f4712f4f78a335072dc52652c068c0a5d226706d449ecec08115d.
  All sixteen pre-edit hashes and byte counts matched. The boundary supersedes
  the earlier partial fifteen-path request without changing that receipt.
- ISSUE-W2-AMENDMENT5-FIXTURE-SCOPE is resolved by direct user approval and
  prospective immutable Amendment 5. Current dirty
  Fast completed in 5047.359 seconds with 105 passed, 4 failed, 1 nonblocking
  no-BaseRef skip, and 0 unavailable. The artifact-path failure is corrected;
  a direct policy probe passes all 49 paths. The other three failures are stale
  synchronous fixture assumptions in unchanged tests. Their exact scope request
  is `C:/T3/BN/receipts/wave2/CODEX_WAVE2_AMENDMENT5_SCOPE_REQUEST_2026-09-11.md`,
  SHA-256 ad5271c5ea4c8756c9f5f90449a58be8549d4494e5c665bae4a7ffff9c5f91b5.
  Direct authority is bound by the Amendment 5 packet and authorization receipt
  listed above. The three target tests remained unchanged through their creation.
- ISSUE-W2-AMENDMENT8-FIXTURE-SCOPE is resolved prospectively. The one unchanged
  target still expects four `Catalog.Put` calls to complete synchronously. Valid
  Amendment 8 authorizes a bounded exact-ticket terminal fixture helper without
  changing production semantics or assertions. Its reconciliation is a
  prospective pre-edit packet replacement, not an evidence-only correction.
- Amendment 8 implementation is complete and its focused and affected invariant
  proofs pass. ISSUE-W2-AMENDMENT9-FIXTURE-SCOPE is resolved prospectively for
  the nine unchanged tests exposed by the later complete inventory. Amendment 9
  adds no production path and maps every target only to `MASTER-RC-006`.
- The failed Fast evidence is preserved byte-exact under
  `C:/T3/BN/receipts/wave2/CODEX_WAVE2_DIRTY_FAST_2026-09-11`.
  MANIFEST.json SHA-256:
  05f3232736dec93bd9330d170762ebfc3201ff2c3c81377499756d2f92adcb96.
- The same sole-writer task is now authorized on openai/gpt-5.6-sol/max by the
  bounded provider-routing exception, SHA-256
  d5d64daca37e436910f21d1edb33cbb8d80335281afc6acf8c909233e1aedd4e.
  Current turn 01a091b6-0728-7c42-9980-65d64f01763d verifies that route at
  2026-09-11T18:23:40.935Z.
  Prior medium and Astra/high evidence remains unchanged.
- Local copies of 22 completed current diagnostic logs are verified; originals
  remain intact. Archive MANIFEST.json SHA-256
  5cd622dd1adcd3751ccc37f3067404d28b405e9ad7e3b256ae04dbc75b3f752f in
  C:/T3/BN/receipts/wave2/CODEX_WAVE2_A3_HIGH_DIAGNOSTICS_2026-09-10.
- Historical 242/242 and earlier 243/243 suites remain old baselines. The
  separate current 243/243 and Fast 230/230 proofs bind the final working bytes.
  The installed dispatcher selected actual
  `implement / prompt.checkpoint_implementation`, and the tracked workflow is
  now `IN_REVIEW`. This tracked state forms the one-commit freeze boundary.
  The exact commit identity will be recorded in the external Wave 2 freeze
  receipt immediately after commit.

## Five-root Repair Contract

- `MASTER-RC-012`: use typed identity comparison for exact-candidate ties and
  prove stable numeric/string winners after removal, reinsertion, and reload.
- `MASTER-RC-006`: make finalization, witness, replacement maps, session
  registries, and ordinary reads persistent and metered. Prove maximum-root
  bounds and keep raw diagnostic verification scheduler-only.
- `MASTER-RC-002`: detach every target slot, verdict, and barrier before mutation.
  Prove failed commits preserve old rows, slots, barriers, indexes, counts,
  vectors, and object identities.
- `MASTER-RC-017`: detect nested in-place graph mutation under the same row
  identity with bounded exact witness accounting.
- `MASTER-RC-007`: centralize every durable and session increment, preflight
  batches, and prove refusal at `MAX-1`, `MAX`, and multi-item boundaries.

## Safety Boundaries

- Never edit a protected path. The surviving protected set includes
  `core/MainCommands.lua`, `core/SyncDiagnostics.lua`,
  `core/SyncTransport.lua`, `data/**`, `docs/**`, `logic/**`, `package.json`,
  `package-lock.json`, and `tools/**`.
- Edit only paths mapped by the immutable Wave 2 packet and valid prospective
  Amendments 1, 2, 3, 4, 5, 8, and 9. Amendments 6 and 7 grant no edit authority.
  Any further production or test path requires a
  necessary exact prospective immutable successor before its first edit under
  the standing authority.
- Preserve Lua 5.1, WoW 3.3.5a, protocol 7, exact 79/6/85 semantics, expected
  counts, and all closed-root behavior.
- Do not access live SavedVariables, restart/reload the game, merge, push a
  protected/default branch, force-push, alter a stable release, mutate the
  legacy campaign, or delete history. Scoped task-branch, task-PR, relevant CI,
  and post-acceptance tester/prerelease GitHub writes are separately authorized
  after exact target verification.
- After exact-head validation and valid independent MASTER acceptance, current
  authority permits a clean local tester package and installation with a
  recoverable addon backup. Stop and notify the user before live WoW testing.
  Scoped GitHub delivery also requires all existing acceptance conditions.
- The bounded provider exception makes this existing gpt-5.6-sol/max task the
  sole writer for Amendment 4 implementation, local validation, and final
  candidate preparation. Claude restoration or handback is not a prerequisite.

## Validation and Review Boundary

- Record fail-capable expected red for all five roots before production repair.
  Then run mapped focused and affected-invariant tests, Fast, exact path
  accounting, residual reconciliation, and a current complete Lua inventory.
- Create exactly one coherent Wave 2 freeze commit. Record commit, tree, parent,
  and exact path inventory. Do not start a third repair wave.
- Run exact-head Fast and Full on the frozen candidate. Read the exact N/N result
  and scan for genuine failures.
- This writer never performs acceptance review. Fresh isolated Codex sessions
  perform SPEC, STANDARDS, and ADVERSARIAL review. A separate fresh Codex session
  performs MASTER aggregation. The current bounded exception requires
  `gpt-5.6-sol` with reasoning `max` for bookkeeping, implementation,
  supervision, and final candidate preparation.
- Sole successor writer: Codex thread `01a0895c-84ed-72e3-96b8-27573a831e91`.
  The prior implementation turn verified `openai`/`gpt-6-astra`/`high`.
  Current continuation turn `01a091b6-0728-7c42-9980-65d64f01763d` verifies
  `openai`/`gpt-5.6-sol`/`max` under the explicit provider exception. The prior
  medium and Astra/high records remain
  preserved. Subscription billing and native T3 successor ID are unverified.
  The exact handoff and prior identities are preserved in external Wave 2 receipts.
  The installed dispatcher abandons the old interrupted triage timing sample on
  session change and retains historical timing. No human wait is implementation.
