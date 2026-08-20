# CONTEXT

## Architecture

- Repository `Viscerals/Better-Nexus`; isolated infrastructure worktree `.infra-viberun-quality-gate-worktree` on `infra/viberun-quality-gate`.
- Integration base is `origin/refactor/nexus-1.20-test17` at `d0681b6a885db447c94a75f40df7e81f60b74c55`; draft PR #13 targets draft PR #10's branch.
- Runtime addon identity is `Nexus`, WoW target is 3.3.5a, and sources/tests parse as Lua 5.1.
- `Invoke-QualityGate.ps1` owns Fast, Full, Package, and Security; successful summaries are compact and detailed logs remain ignored.
- Production Lua, runtime-test Lua, `Nexus.toc`, schemas, wire/gameplay/UI behavior, bundled data, version/protocol/author, and test.17 are immutable in this infrastructure workflow.

## Key Decisions (2026-08-16)

- Git change discovery uses one raw NUL-delimited record model; rename/copy source and destination ownership are unioned.
- Fast and staged/all-tracked scans share one fail-closed artifact path/content policy.
- Only blocking `pass` succeeds; Package is a required exact-base, non-publishing CI job with failure-log-only evidence.
- PSScriptAnalyzer inherits only six reviewed owner/rule/message records; the current four findings are inherited and two removals report as improvements.
- Security bootstrap validates ZIP/tar entries and exact executable paths before extraction, accepts only hash-locked wheels, and removes bootstrap/download/extraction roots on success or failure.
- Stage 43 commits the formal candidate before Full, runs Full locally exactly once, proves a disposable fresh checkout, then refreshes PR #13/issue #12 and stops without merge.

## Key Decisions (2026-08-20)

- WP1 treats inline and referenced locked evidence as content integrity only, because current-state backfill can attach both after the historical pull; the durable schema has no provenance bridge that authorizes subtraction or completed-v1 reversal.
- A surviving `lockedMigrationSource` is restored and retired before readiness gating or legacy reconciliation. The v1 completion stamp still waits for authoritative locked readiness; represented restoration alone owns its revision advance.

## Gotchas

- Windows Git cannot represent tab/newline index names; use raw-byte parser fixtures locally and real disposable index fixtures on supporting platforms.
- LuaLS, Luacheck, and StyLua may remain advisory-unavailable; never report unavailable checks as passing.
- Use the exact PR #10 BaseRef for full-branch gates and the checkpoint parent for bounded checkpoint review.
- Vibe flags and routing are dispatcher-owned; maintenance scans must not move the product checkpoint pointer.
- Schema-valid state can still be semantically stale; verify status beneath the exact checkpoint heading and confirm fresh-checkout dispatcher truth at Stage 43.
- A commit cannot contain its own SHA; terminal Vibe truth names branch `HEAD` plus the exact base, then a fresh checkout verifies the resolved SHA and stop route without an ignored receipt.
- Do not mutate the formal candidate's code/tooling bytes after its single local Full; later Vibe/GitHub receipts must remain documentation/state-only and receive their own exact-head CI.
- For locked migration, checking readiness before rollback restoration exposes partial rows to later init/getter work even if the migration function itself returns. Source-first means before readiness and before any legacy/evidence/hash/backfill path.

## Hot Files

- Completed formal candidate: `tools/Invoke-QualityGate.ps1`, `tools/Bootstrap-QualityTools.ps1`, validation/security/package tests, `.pre-commit-config.yaml`, and exact-base Git scope commands.
- Terminal review boundary: `.vibe/STATE.md`, `.vibe/PLAN.md`, `.vibe/CONTEXT.md`, `.vibe/EVIDENCE.md`, PR #13, issue #12, and exact-head workflow/review state.
- Workflow/gate: `.github/workflows/quality-gate.yml`, `tools/Invoke-QualityGate.ps1`, `tools/Write-ValidationSummary.js`.
- Path policy: `tools/GitPathRecords.ps1`, `tools/ArtifactPathPolicy.ps1`, `tools/Get-ChangedTestPlan.ps1`, `tools/Test-StagedArtifacts.ps1`.
- Vibe authority: `AGENTS.md`, `.vibe/STATE.md`, active `.vibe/PLAN.md`, this file, and append-only `.vibe/EVIDENCE.md`.
- Stage 46 WP1: `core/DpsCapture.lua`, `tests/run_locked_migration_authority.lua`, and `tests/run_migration_owned_lifecycle.lua`.

## Agent Notes

- Root, `.lag-hotfix-worktree`, and authoritative product worktree are independently owned and read-only for this task; preserve their existing status.
- PR #13 and issue #12 remain open; do not submit another `@codex review` because the prior request hit the account usage limit.
- Expected red must demonstrate the actual missing capability; use disposable repositories/archives and never place hostile fixtures in the real worktree.
- No addon install, WoW launch, live SavedVariables access, package retention/upload, rebase, force-push, merge, tag, release, publication, deployment, or settings change is authorized.
- Final offline/CI evidence does not prove native WoW behavior; stop at the refreshed independent-review boundary.
- Formal candidate `4c1002e` passed the single local Full; later receipt-only heads received exact-head CI. Do not repeat local Full or mutate candidate code/tooling bytes.

## Stage Retrospective Notes

- Keep checkpoint-range and current-base Fast evidence separate; preserve a base-wide failure as the next checkpoint's red boundary when ownership is explicit.
- Pair raw-byte path fixtures with real disposable Git index fixtures where the platform supports hostile names.
- Centralize a shared security policy before updating callers so false positives and bypasses cannot drift.
- Test local summary semantics and GitHub aggregate conditions in the same fail-closed checkpoint.
- After each Vibe transition, verify the status beneath the exact checkpoint heading rather than relying only on schema validation.
- Stage 42 took 10 loops from design through consolidation, with one implementation/review/hygiene cycle per checkpoint and no repeat review, split, skip, blocker, or decision-required issue.
- For baseline migrations like 42.1, reconstruct the reviewed head's exact findings before editing and retain resolved entries as improvements; never bless the current output wholesale.
- For archive bootstrap like 42.2, encode the real Windows and Linux layouts in metadata, then test both synthetic hostile archives and the pinned cross-platform assets through the same resolver.
- Treat the first real bootstrap failure as cleanup evidence too: verify the outer temporary root disappears before repairing the parsing defect.
- Completed PLAN markers are parser contracts: place `(DONE)` before the checkpoint ID and inspect both the dispatcher role and auxiliary ready list after transition.
