# CONTEXT

## Architecture

- WP6 runs on `bugfix/test19-wp6-build-hash-buckets-erase-build-id-type-and-can-r` from accepted WP5 head `8f5d28008935cef2d973b800167695ab50e0f70b`.
- `core/BuildCatalog.lua` preserves exact typed build IDs. `core/BuildHashCache.lua` owns the eight-bucket delta and legacy canonical build/tombstone material consumed by Sync compatibility hashes.
- `core/SyncCompatibility.lua`, `core/SyncReconciler.lua`, and `core/Sync.lua` decide whether matching bucket hashes can skip reconciliation.
- Runtime targets WoW 3.3.5a and Lua 5.1. `tools/Invoke-QualityGate.ps1` owns Fast/Full/Package/Security validation.

## Key Decisions (2026-08-22)

- Encode raw ID type at the existing BuildHashCache canonical-material boundary; do not coerce BuildCatalog identities or change the eight-bucket layout.
- Apply one typed identity rule to build and tombstone entries in both delta and legacy modes.
- Prove deterministic ordering, targeted/full invalidation, reconciliation, and mixed-client behavior before accepting the candidate.
- Preserve protocol, release metadata, Test 18, and accepted WP5 behavior.

## Gotchas

- `BuildEntry`, `TombstoneEntry`, and cache entry keys currently use `tostring(id)`; numeric `1` and string `"1"` can collide even though Lua tables and BuildCatalog distinguish them.
- Delta and legacy caches share helpers, and targeted invalidation must update both without a full collection walk.
- A digest change can affect mixed-version peers. Compatibility must prevent permanent false equality without widening the wire/protocol scope unnecessarily.
- Root and `.lag-hotfix-worktree` contain unrelated user changes. Earlier WP2/WP3 worktrees are frozen and must not be edited, rebased, cleaned, stashed, or deleted.
- LuaLS, Luacheck, and StyLua may remain advisory-unavailable and must not be reported as passes. Offline checks do not prove native WoW behavior.

## Hot Files

- Product seam: `core/BuildHashCache.lua`; compatibility consumers: `core/SyncCompatibility.lua`, `core/SyncReconciler.lua`, `core/Sync.lua`.
- Focused coverage: `tests/run_sync_hash_cache.lua`, `tests/run_sync_baseline_delta.lua`, `tests/run_sync_compatibility_parity.lua`.
- Validation: `tests/validation-map.json`, `tools/Invoke-QualityGate.ps1`, and `build/verify/summary.json`.
- Workflow: `AGENTS.md`, `.vibe/STATE.md`, `.vibe/PLAN.md`, this file, and append-only `.vibe/EVIDENCE.md`.

## Agent Notes

- Current state: Stage 50 checkpoint 50.1 is `NOT_STARTED`; retrospective, design, and the scheduled documentation scan are complete.
- Next action: use Caveman expected-red discipline to reproduce typed build/tombstone hash collisions, then implement the smallest coherent BuildHashCache change and focused tests.
- One clean local WP6 commit is authorized after focused and Fast validation. The controller owns independent review; no push, PR mutation, package/install, native WoW, or SavedVariables work is authorized.

## Stage Retrospective Notes

- Stage 49 checkpoint 49.1 needed repeated implement-review repairs because equal-DPS tie inputs and copy authority differed across consumers; define one explicit semantic projection and make all consumers share it before widening callers.
- Stage 49 review found async, empty-authority, nonfinite, and mixed-state gaps after focused success; include sync/async, empty, malformed, and partially migrated states in the expected-red matrix before the first product edit.
- Stage 49 Full exposed unbounded real-pair work in the active Sync projection pump; test bounded work budgets on the production async path before freezing bytes for Full.
- Stage 49 checkpoint 49.2 showed retention needed preserved source references while presentation needed a narrow allowlist; keep source identity separate from display metadata and test permutation invariance explicitly.
- Stage 49 completed without checkpoint splits, skipped work, or decision blockers; retaining one bounded authority checkpoint plus a separate hygiene pass kept repairs scoped despite multiple review cycles.
