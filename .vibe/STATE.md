# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 46
- Checkpoint: 46.1
- Status: DONE
- Branch: `bugfix/test19-wp1-issue39`
- Candidate head: reviewed implementation `981a2572a5678d19896c1110e3d83af3ec43e423` plus local receipt-only Vibe head; all changes remain unpushed
- Worktree: `.wp1-issue39-worktree`
- Base: `origin/refactor/nexus-1.20-test17` at `3965b107574d4a394e0672cb130eab7e4694e7b5`

## Objective (current checkpoint)

Prevent locked-baseline migration from applying unproven evidence to historical DPS rows, including across interrupted-restart ordering.

## Deliverables (current checkpoint)

- Focused `tests/run_locked_migration_authority.lua` coverage for preservation, login order, restart, future-schema, and no-churn behavior.
- `tests/run_migration_owned_lifecycle.lua` retained for authoritative wait, immutable interruption source, retry, and idempotence without current-character guessing.
- One fail-closed `core/DpsCapture.lua` migration owner that restores an immutable interrupted source before any side-effecting migration work and otherwise preserves historical rows.
- Focused mapped DPS tests plus Lua 5.1 parse, Fast, required Full, diff/scope review, and explicitly staged local follow-up commits.

## Acceptance (current checkpoint)

- [x] Expected red proves a remote row loses a locally locked ordinary Echo under the old lifecycle.
- [x] Pre-v1 and interrupted migration preserve every historical row, restoring and retiring a surviving immutable source before readiness gating or any partial live row side effect.
- [x] Completed-v1 rows remain unchanged because direct references and strict-subset relationships prove content consistency, not historical association.
- [x] Login order, late current-state backfill, restart/retry/idempotence, future-schema/read-only, no-lock, and Sync fingerprint stability regressions pass.
- [x] Mapped DPS tests, related board/evidence/migration tests, Lua 5.1 parse, Fast, required Full, and `git diff --check` pass on exact final repaired code/test bytes.
- [x] Reviewed WP1 paths are staged explicitly into local repair commit(s); no GitHub, package, install, Test18, live addon, or SavedVariables mutation occurs.

## Evidence

- path: .vibe/EVIDENCE.md
- Stage 42.1: four exact inherited findings remain advisory; owner/message drift, duplicates, stale entries, and improvements are distinguished; focused policy and Fast `15/15` pass.
- Stage 42.2: ZIP/tar layout validation, exact executable selection, hash-locked Python wheels, and failure-safe cleanup pass; Security `12` blocking checks and Fast `15/15` pass.
- Stage 43 maintenance: fresh-checkout Linux bootstrap/Fast and receipt-independent Vibe terminal probes remain the highest-impact gaps and are already acceptance-owned by 43.1/43.2.
- Stage 43.1: candidate `4c1002e` passed Full `18/18` with one explicit manual skip, Package `10/10`, Security 12 blocking passes / 3 advisory-unavailable, focused/hooks/scope checks, and fresh-checkout bootstrap/Fast/Vibe proof.
- Stage 44.1 expected-red: workflow lacked candidate owner, sanitized hostile paths returned 5/7 violations, case-distinct owners shared occurrence state, and manifest resolver was absent; all four failed for the intended reason.
- Stage 44.1 focused green: workflow, artifact 7/4, case-distinct analyzer, manifest containment, combined security policy, and quality self-tests pass.
- Stage 44.1 Fast: exact base `d0681b6`, `15/15` blocking checks passed in 37.924 seconds with zero failed/skipped/unavailable checks.
- Stage 44.1 formal: candidate `cc3c995` passed the single local Full `18/18` plus one manual skip, Package `10/10`, Security 12 blocking / 3 advisory-unavailable, and dependency-clean bootstrap/Fast/Vibe proof.
- Stage 44.1 exact-head candidate: `d3973ff` passed Quality `31975606558` and Release `31975606507`; all seven source jobs selected/asserted that SHA and both artifact inventories are empty.
- Stage 45.1 starting review: exact head `4197ed9` is green but the resolver accepts `file:`, relative, and plain-HTTP `psscriptanalyzer.url` metadata before bootstrap use.
- Stage 45.1 expected-red/green: three unsafe PSScriptAnalyzer URLs were accepted before repair; one shared owner now rejects 19 hostile variants for both download paths while current/safe HTTPS manifests pass.
- Stage 45.1 local gates: focused security/bootstrap regressions pass; Fast `15/15`; Security 12 blocking pass / 3 advisory-unavailable; PSScriptAnalyzer 0 blocking / 4 inherited / 0 new / 2 improvements; Gitleaks no leaks.
- Stage 45.1 reviewed repair CI: exact head `3432fd6` passed Quality `31978682635` and Release `31978682532`; all seven source-job logs select/assert the full SHA and both artifact inventories are empty.
- Stage 45.1 terminal reconciliation: PR #13 body and issue #12 comment `5310228999` carry the repair/CI receipt; supported `vibe stop` reports `stopped: true`, Stage 45.1 `DONE`, dispatcher `stop`, and no prompt.
- Stage 46.1 repair: public-lifecycle, conflicting-evidence, completed-v1, interrupted-source, and shared-keyed-alias regressions pass; mapped tests pass; Fast passed `19/19`; the single Full passed `18` blocking checks with `209/209` Lua and `282/282` Lua 5.1 parse plus one explicit manual SavedVariables skip.
- Stage 46.1 final restart-order candidate: focused/mapped tests pass, Fast passed `19/19`, and replacement Full passed `18` blocking checks with `209/209` Lua and `282/282` Lua 5.1 parse plus the explicit manual SavedVariables skip.
- Stage 46.1 final unsynced-restart candidate: both focused runners and Fast `19/19` pass; final Full passed `18` blocking checks with Lua `209/209`, Lua 5.1 parse `282/282`, and the explicit manual SavedVariables skip.

## Work log

- Stage 46.1 final checkpoint hygiene CLEAN: bounded review of `core/DpsCapture.lua` and the two repaired migration runners found no redundant policy owner, unsafe compatibility branch, speculative abstraction, correctness/security issue, or actionable deferred debt; product/test bytes remain frozen at `981a257`.
- Stage 46.1 final review PASS: independent Spec and Standards axes accepted source-first unsynced rollback, fail-closed preservation, readiness retry, revision ownership, validation, and Vibe truth with no remaining finding or hygiene signal.
- Stage 46.1 final source-first implementation restores/retires rollback before readiness, leaves only the version stamp gated, preserves authoritative retry/reload behavior, and froze the final validated bytes for review.
- Stage 46.1 unsynced-restart triage resolved the final blocker: rollback now restores and retires the source before readiness, the version stamp still waits, and the authoritative retry/reload remains idempotent.
- Stage 46.1 follow-up review FAIL: source restoration still followed the locked-readiness return, so an unsynced restart could expose partial rows to `DPS.Init` legacy reconciliation. The checkpoint returned to implementation.
- Stage 46.1 final implementation restored surviving source stores before legacy reconciliation, removed the obsolete new-source snapshot cycle, proved zero partial-row evidence touches plus represented revision advance, and froze replacement code/test bytes for review.
- Stage 46.1 issue triage resolved the restart-order blocker: a tagged partial row failed red when evidence touched it, then passed after source restoration moved ahead of legacy reconciliation; represented restoration still advances the DPS revision.
- Stage 46.1 final review FAIL: interrupted restart still ran `MigrateLegacyLeaderboard` over partial live stores before restoring `lockedMigrationSource`, allowing orphan evidence and revision side effects. The checkpoint returned to implementation.
- Stage 46.1 implementation removed the unprovable subtraction/recovery paths, retained authoritative readiness plus exact interrupted-source restoration/versioning, expanded adversarial preservation coverage, and froze the repaired code/test bytes for review.
- Stage 46.1 independent review FAIL: a public lifecycle probe proves late current-state backfill becomes destructive historical authority; separate standards/spec reviews also found conflicting inline/reference authority, unproven completed-v1 pre-state association, and shared keyed-store alias corruption. The checkpoint returned to implementation.
- Stage 46.1 checkpoint hygiene CLEAN: bounded review found one direct-reference resolver, one exact subtraction helper, one transform path per store shape, and no safe duplication removal, speculative abstraction, correctness issue, security issue, or actionable deferred debt; product/test bytes remain frozen.
- Stage 46.1 review PASS: exact row authority prevents global current-login subtraction, bounded completed-v1 recovery requires direct pre-state plus exact row baseline, Fast passed `19/19`, Full passed `18` with the complete `209/209` Lua suite and one explicit manual SavedVariables skip, and no correctness/security or hygiene signal remains.
- New human direction resumed the completed Stage 45 terminal state, reconciled PR #10 at exact head `3965b107` and issue #39, preserved every existing worktree, and selected isolated Stage 46.1 for Test19 WP1 only.
- Checkpoint 45.1 implementation replaced the inline tool-asset URI check with one strict shared resolver used by both tool assets and PSScriptAnalyzer, added network-free hostile/safe fixtures, and passed focused/Fast/Security/static validation without workflow or protected-runtime changes.
- Checkpoint 45.1 adversarial review passed at exact repair commit `3432fd6`: focused demos, Fast, Security, pre-use/no-mutation ownership, exact-base scope, seven source-job SHA logs, and empty artifact inventories are green; no correctness, security, or checkpoint-hygiene signal remains.
- Checkpoint 45.1 bounded hygiene found one shared URI owner, direct owner-count coverage, no compatibility branch, no duplicate validation path, and no actionable debt; implementation bytes remain unchanged.
- Plan exhaustion returned stage design; the explicit terminal mission used the supported stop operation instead of inventing Stage 46 work. The resulting receipt-only head must receive a second exact-head CI pair before external metadata is finalized.
- Independent final review at starting head `4197ed9` found one remaining merge-blocking gap: ordinary tool asset URLs are validated, but `psscriptanalyzer.url` reaches `Invoke-WebRequest` without the shared fail-closed URI contract. Supported VibeRun resume selected Stage 45 design for one bounded repair checkpoint.
- Independent review falsified the Stage 43 terminal acceptance premise: Quality `31959113599` and Release `31959113603` checked out synthetic merge `bab79a6`, not reviewed head `87204ab`, and exposed four merge-blocking infrastructure findings.
- The supported VibeRun resume operation cleared `RUN_STOPPED`; the dispatcher selected stage design, which bounded all four repairs and final exact-head reconciliation into checkpoint 44.1.
- Checkpoint 44.1 implemented explicit immutable candidate/base ownership and checkout assertions, path-before-fixture artifact enforcement, ordinal analyzer maps, and pre-use manifest containment; focused and Fast gates pass and the checkpoint is ready for formal review.
- Stage 44.1 review found one directly related fallback regression: `Classify reviewed paths` still reads `EVENT_NAME`, but its workflow env binding was removed, so push/manual full-forcing is not auditable. The checkpoint returned to implementation before terminal signoff.
- Stage 44.1 repair pass restored the immutable event-name binding and added a policy fixture that failed red before the fix; workflow policy, actionlint, and exact-base Fast `15/15` pass.
- Stage 44.1 replacement review passed at `d3973ff`: exact-head Quality/Release are green with per-job checkout/assertion audit, PR #13 and issue #12 carry the synthetic-merge correction, scope is 48 infrastructure paths / 0 protected paths, and no checkpoint-hygiene signal remains.
- Stage 44.1 checkpoint hygiene found one owner per candidate/base, artifact exception, ordinal map, and manifest validator; no stale branch, duplicate proof surface, safe quick win, or actionable debt remained, so implementation bytes were unchanged.
- After hygiene, plan exhaustion returned stage design rather than stop; the explicit user terminal condition was honored through the supported `vibe stop` operation, which set `RUN_STOPPED` and made dispatcher preview return `stop` with no prompt.
- Stage 43 maintenance test-gap scan selected fresh-checkout Linux bootstrap/Fast and ignored-receipt-independent Vibe terminal validation; both are already bounded by 43.1/43.2, so no new checkpoint was added.
- Checkpoint 43.1 froze the formal candidate as branch `HEAD` against exact base `d0681b6`; code and tooling bytes must remain unchanged after the single local Full.
- Checkpoint 43.1 clean bootstrap correctly rejected an incomplete PSScriptAnalyzer top-level allowlist; the exact checksum-matching package layout was reconciled and the replacement clean bootstrap passed before Full.
- Checkpoint 43.1 formal candidate `4c1002e` passed the single local Full plus Package/Security/focused/hooks/scope gates; a detached dependency-clean checkout passed tracked bootstrap, Fast, and receipt-independent Vibe status before complete cleanup.
- Checkpoint 43.1 formal review confirmed the post-Full delta is only three Vibe receipt files, Fast passes `15/15` at receipt head `49801d5`, exact-base scope remains 47 infrastructure paths / 0 protected paths, and Full was not repeated.
- Checkpoint 43.1 hygiene found no duplicate proof owner, stale marker, unnecessary abstraction, or actionable debt in the receipt-only delta; code, tooling, workflow, and test bytes remain unchanged.
- Checkpoint 43.2 normally published receipt head `8c4d977`: Quality Gate `31957168510` passed every required job with zero artifacts, while Release Policy `31957168563` exposed a LuaJIT-only nondeterministic runtime-test failure outside this infrastructure ownership.
- Checkpoint 43.2 replacement head `bc0b61a` passed Quality Gate `31957769884` and Release Policy `31957769870` with zero artifacts; PR #13 and issue #12 now carry the exact repair, scope, validation, and disclosed flake status.
- Checkpoint 43.2 formal review passed at receipt head `767cfd8`: exact-head Quality `31958348931` and Release `31958348943` passed, local/remote heads matched, scope remained 47/7/0/0, and plan exhaustion establishes the terminal stop route.
- Checkpoint 43.2 hygiene found no duplicate truth owner, stale marker, unnecessary abstraction, or actionable debt in the terminal Vibe/GitHub receipt surface; final stop was restored through the actual Vibe operation.

## Workflow state

- [x] RUN_STOPPED
- [ ] RUN_CONTEXT_CAPTURE
- [x] STAGE_DESIGNED
- [x] MAINTENANCE_CYCLE_DONE
- [x] RETROSPECTIVE_DONE
- [x] PROCESS_IMPROVEMENTS_DONE

## Active issues

- None.

## Blockers

- None.

## Deferred work

- LuaLS, Luacheck, and StyLua remain advisory-unavailable and are not represented as passes.
- Native test.17 and all install/live/release activity remain outside this infrastructure workflow.
- Release Policy run `31957168563` failed once at `tests/run_startup_catalog_cost.lua:103` before unchanged product/runtime-test bytes passed replacement run `31957769870`; the nondeterministic LuaJIT result remains disclosed for independent review.

## Decisions

- Inline and referenced locked evidence prove content integrity but not historical provenance because current-state backfill can create both; absent a durable provenance bridge, automatic subtraction is forbidden.
- An interrupted migration restores `lockedMigrationSource` exactly before completing the fail-closed version stamp; completed-v1 rows are not automatically reversed from direct references or subset relationships.
- Source restoration and rollback-source retirement precede both readiness gating and `MigrateLegacyLeaderboard` so partial live rows cannot leak evidence or revision side effects.
- Preserve ambiguous evidence in place, preserve future-schema/read-only storage, avoid a new durable audit schema, and do not broaden Stage 46 beyond WP1/#39.
- Reuse one shared strict download-URI validator for ordinary tool assets and PSScriptAnalyzer; do not add a second validation path.
- Keep Stage 45 to checkpoint 45.1; because CI evidence must be committed into terminal Vibe truth, use the authorized two-cycle flow and require replacement Quality and Release on the receipt-only final head.
- Treat runs `31959113599` and `31959113603` as green synthetic-merge runs, not exact-head evidence; preserve them only as corrected historical receipts.
- Use exactly one Stage 44 repair checkpoint and one frozen candidate so terminal Vibe truth can receive CI at the same final head.
- Keep existing PR #13 draft against the current PR #10 branch and refresh it only after exact-head validation.
- Keep VibeRun authoritative and retain compact summaries rather than successful log dumps.
- Stop at exact-head CI/review boundary without merge.

## Last completed loop

- Stage 46.1 final adversarial review passed `981a257`; the plan is exhausted at the requested local WP1 conclusion.

## Recommended next action

- Stop at the clean local WP1 independent-review conclusion; do not publish or advance to WP2 without new authorization.
