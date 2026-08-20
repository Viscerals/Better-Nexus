# HISTORY

This file is non-authoritative. Archive completed checkpoints, resolved issues, and consolidation notes here.

## Completed checkpoints

- Stage 38 established reproducible tracked Lua 5.1 tooling, deterministic Fast/Full/Package/Security profiles, VibeRun role/state integration, staged-artifact/static/security policy, exact-head GitHub Actions, and clean local review/publication receipts.
- Stage 39 reconciled PR #13 onto PR #10 base `d0681b6`, hardened current-base routing/diff/manual-smoke boundaries, and completed exact-head local review without product changes.
- Stage 40 refreshed the draft infrastructure branch, repaired cross-platform workflow policy defects found by CI, and stopped at green exact-head Quality Gate/Release Policy with zero reviews or threads.
- Stage 41 repaired rename/copy and policy routing (41.1), staged-artifact Git-path safety (41.2), and fail-closed summaries plus required Package CI (41.3). Focused reviews and bounded hygiene passed at each checkpoint.
- Stage 42 replaced count-only PSScriptAnalyzer allowances with six exact reviewed owner/rule/message records (four inherited, two improvements) and hardened ZIP/tar/Python bootstrap integrity with exact layouts, executables, wheel hashes, and failure-safe cleanup. Focused reviews and bounded hygiene passed at both checkpoints.

## Resolved issues

- ISSUE-183 / Stage 46.1 independent review: late current-state backfill, unproven completed-v1 references, and shared keyed-alias transforms were resolved by preserving historical rows whenever the durable schema cannot prove provenance; expected-red, adversarial preservation, interruption/idempotence, Fast, and Full evidence are recorded in checkpoint 46.1.
- ISSUE-46-1-D: Interrupted restart now restores `lockedMigrationSource` before legacy reconciliation can inspect partial live rows; the regression proves zero partial-row evidence touches and a revision advance for represented restoration.
- ISSUE-46-1-E: Unsynced restart now restores and retires `lockedMigrationSource` before readiness gating; partial rows are never reconciled, the version stamp remains delayed, and the authoritative retry is idempotent.
- ISSUE-45: One shared pre-use download-URI validator now rejects unsafe tool and PSScriptAnalyzer URL metadata; expected-red, focused-green, Fast, Security, PSScriptAnalyzer, and Gitleaks evidence is recorded in checkpoint 45.1.
- Git rename/copy discovery and workflow classification now use one NUL-safe record model and preserve both owners.
- Policy/legal/security Markdown no longer inherits ordinary-documentation routing.
- Staged/all-tracked artifact discovery no longer consumes Git-quoted lines and shares one fail-closed policy with Fast.
- Blocking skipped/malformed results fail aggregate validation, and Package is a required exact-base non-publishing CI job.
- Static-analysis owner replacement no longer hides behind rule counts; exact duplicates and removed findings remain distinguishable.
- Security bootstrap rejects hostile roots, traversal, case conflicts, links, and recursive decoys; pip accepts only the reviewed hash-locked distribution set.
- ISSUE-44-1-A: Quality preflight path classification again receives immutable `github.event_name`; the focused assertion, actionlint, and exact-base Fast gate pass.

## Process notes

- Initialized by Vibe package 0.1.0+codex.20260812081901 using state schema 1.0.
- Stage 41 consolidation corrected stale PLAN status for reviewed checkpoint 41.1, pruned the hot work log to eight receipts, and retained only Stages 42–43 in active PLAN.
- Stage 42 corrected its completed-marker placement after the dispatcher exposed an auxiliary ready-list mismatch, preserving dispatcher ownership instead of forcing a route.
