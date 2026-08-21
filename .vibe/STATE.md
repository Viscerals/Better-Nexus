# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 48
- Checkpoint: 48.1
- Status: IN_REVIEW
- Branch: `bugfix/test19-wp4-exact-wishlist-evidence`
- Starting head: exact accepted WP3 publication head `e674f033cc51494a382191b987c9a99cb6827f4a`
- Worktree: `.test19-wp4-worktree`
- Base: exact accepted WP3 publication head `e674f033cc51494a382191b987c9a99cb6827f4a`

## Objective (current checkpoint)

Make editor open/edit/save and row actions round-trip every ordinary quality tier independently.

## Deliverables (current checkpoint)

- Exact-tier draft/model identity with deterministic fail-closed resolution for compatibility callers lacking an exact row handle.
- Exact-row `+`, `-`, selection, and remove behavior.
- Multi-tier family round-trip and 79-copy total coverage.

## Acceptance (current checkpoint)

- [x] Common, Uncommon, and Rare rows in one family survive a no-op round-trip unchanged.
- [x] Editing or removing one exact tier cannot modify a sibling tier.
- [x] Ordinary total validation counts stack copies across every exact row and enforces 79.
- [x] Locked intent remains outside the ordinary editor-row identity.
- [x] Existing single-tier and compatibility-row behavior remains deterministic.
- [ ] Focused Wishlist model/editor tests, mapped tests, Fast, required review/Full, and diff checks pass.

## Evidence

- path: .vibe/EVIDENCE.md
- #43 expected-red failed twice at `same-family exact tiers collided during draft normalization`; the green public model/controller/renderer runner passes 13 checks including no-op, action isolation, transfer/reload, ambiguous compatibility, and 79-copy limits.
- All 20 Wishlist/model/controller/renderer/import/association mapped runners pass; integration remains `70/70` through Fast.
- Exact-base Fast passes `17/17` with zero failed, unavailable, or skipped checks after advancing the enumerated normal Lua runner guard from `215` to `216`.
- Stage 47 / WP3 completed at frozen product-test candidate `915a313`: cumulative Spec, Standards, and adversarial review passed; final Full passed all `18` blocking checks with Lua `215/215`, parse `288/288`, integration `70/70`, and one explicit nonblocking manual SavedVariables skip.
- Stage 47 hygiene was CLEAN across the bounded 30-path WP3 surface; product/test/workflow/contract bytes did not change after Full.
- Stage 48.1 is pointer-only and `NOT_STARTED`; no WP4 design or implementation occurred during consolidation.

## Work log

- Checkpoint 48.1 implements exact ordinary draft keys from trustworthy spell IDs, collision-safe single-tier compatibility resolution, exact controller/renderer action handles, same-family tier transfer/reload coverage, and the preserved 79-copy budget.
- Stage 48 maintenance-scan hygiene was clean: no product surface was delivered, the selected precursor is already the single high-ROI bounded action, and adding further helpers or debt entries before its implementation would be speculative churn.
- Stage 48 maintenance scan review passed: the selected row-key precursor is bounded and behavior-preserving, downstream semantic candidates remain in dependency order, and no product acceptance was claimed. Per repository routing rules, the product pointer remains 48.1 `NOT_STARTED`.
- Stage 48 maintenance scan selected one behavior-preserving precursor: `[MODERATE]` make the ordinary draft row key explicit across WishlistModel/controller actions before #43 changes its authority from family to exact spell identity. Existing public model/editor tests prove equivalence; exact-tier expected-red remains the next product step.
- Stage 48 design reconciled #43 -> #44 -> #20 -> #35 against the accepted issue comments and corrected checkpoint 48.3 to read-time exact multiset subtraction without source mutation.
- Stage 47 retrospective completed with five lessons on compatibility inventory, shared authority normalization, adversarial preservation coverage, public-surface parity, and reserving Full for accepted bytes.
- Stage 47 consolidation archived the completed WP3 plan surface, moved the pointer from 47.5 `DONE` to 48.1 `NOT_STARTED`, and retained the exact review/Full/hygiene receipt without starting WP4.

## Workflow state

- [ ] RUN_STOPPED
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

- #49 remains the next narrow prerelease blocker after the already-proven Test19 correctness/data/migration/Sync package sequence; its future scope is a fail-closed OrbService guard only, never Orb automation.
- #50 remains a later Snapshot/Designed contract audit; it is not permission to manufacture a code change when current behavior is already correct.
- LuaLS, Luacheck, and StyLua remain advisory-unavailable and are not represented as passes.
- Native test.17 and all install/live/release activity remain outside this infrastructure workflow.

## Decisions

- WP3 remains frozen; WP4 is authorized only in `.test19-wp4-worktree` through a validated local checkpoint, with no push, PR/issue mutation, publication, install, native WoW, live SavedVariables, or WP5 work.
- Treat the master-chat order as authoritative: WP2 is #28/#41/#42, WP3 is #30/#37 then #19 acceptance, WP4 is #43/#44/#20/#35, and WP5 is #23/#26.
- Preserve every independently owned worktree and the frozen WP2/PR #53 and WP3/PR #54 boundaries; only `.test19-wp4-worktree` owns this local WP4 range.
- Exact canonical identity owns durable authority; ambiguous and future-owned evidence remains preserved, non-authoritative, and fail-closed.
- Exact `spellId` owns ordinary Wishlist row identity when trustworthy; family is grouping metadata only. Locked roles require exact counted authority and ordinary roles are derived read-only by exact total-minus-locked subtraction.

## Last completed loop

- Checkpoint 48.1 implementation is ready for review after deterministic expected-red, 20/20 mapped Wishlist runners, Lua 5.1 changed-file parsing, integration 70/70, workflow policy, release policy, diff checks, and exact-base Fast 17/17.

## Recommended next action

- Review checkpoint 48.1 against exact sibling-tier round-trip, action isolation, compatibility ambiguity, transfer/reload, UI projection, and the 79-copy budget before advancing to #44.
