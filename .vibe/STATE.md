# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 48
- Checkpoint: 48.4
- Status: DONE
- Branch: `bugfix/test19-wp4-exact-wishlist-evidence`
- Starting head: exact accepted WP3 publication head `e674f033cc51494a382191b987c9a99cb6827f4a`
- Worktree: `.test19-wp4-worktree`
- Base: exact accepted WP3 publication head `e674f033cc51494a382191b987c9a99cb6827f4a`

## Objective (current checkpoint)

Make overlay, HUD, model, editor, and automation progress consume the same exact tier and role evidence.

## Deliverables (current checkpoint)

- One exact-spell/tier progress boundary shared by `ui/WishlistOverlay.lua`, the model, editor, and automation consumers.
- Focused sibling-tier, per-tier quota, locked-role, refresh, and parity coverage.
- Removal of family-level satisfaction as an authority decision.

## Acceptance (current checkpoint)

- [x] A lower-quality sibling never satisfies a higher-quality target.
- [x] Each exact tier reports its own owned copies, target quota, and completion state.
- [x] Ordinary and locked progress consume their correct evidence roles.
- [x] Overlay, HUD, model, and editor agree before and after refresh/reload.
- [x] Focused overlay/parity tests, mapped tests, Fast, checkpoint review, and diff checks pass; cumulative independent review and Full remain the frozen WP4 gates.

## Evidence

- path: .vibe/EVIDENCE.md
- #35 checkpoint review found and repaired a same-family automation omission: locked sibling tiers and extra locked copies now extend an automation-only exact target without mutating the server Wishlist. The expected-red failed twice, the repaired Stage 32 fixture passes 65 checks, and exact-base Fast passes `35/35` with zero failed/unavailable/skipped checks.
- #35 expected-red failed twice at `wrong-quality family ownership marked the exact Rare overlay row complete`; the green public runner proves exact Common/Rare separation, duplicate locked quota grouping, role-specific ownership, locked-only refresh, HUD/automation parity, and exact recovery.
- `Model.WishlistEntryProgress` is the pure exact `(role, spellId)` progress owner. Overlay and editor consume it directly; MainViewModel consumes it for explicit-role Wishlists while retaining deterministic legacy behavior for role-unrepresented inputs. Exact-base Fast passes `34/34` with zero failed/unavailable/skipped checks.
- #20 checkpoint review passed with two coherent envelope probes: exact 78 ordinary + seven locked and exact 80 ordinary + five locked both remain unavailable, while restored 79+6 recovers. The strengthened runner passes 16 checks and exact-base Fast remains `26/26` with zero failed/unavailable/skipped checks.
- #20 expected-red failed twice at `exact active/associated mirror remained evidence-pending`; the green public GameAdapter runner passes 13 checks across exact 79+6 derivation, same-tier overlap, sibling quality preservation, mismatch/partial/underflow refusal, reload convergence, and source/SavedVariables immutability.
- The bridge is active-slot-only and requires verified/complete active booleans, exact sorted spell/stack identity, CandidateEvidence's six-copy envelope, and exact `LockedOwned.bySpell` agreement. Exact-base Fast passes `26/26` with integration `70/70` and zero failed/unavailable/skipped checks.
- #44 checkpoint review passed at repaired product/test head `b23259d`: immutable bound future/provenance evidence and exact Dummy/LK quality disagreement are now covered in addition to the original copy-total matrix; focused runners and exact-base Fast `24/24` pass.
- #44 expected-red failed twice at `valid duplicate exact rows did not survive candidate normalization`; the green public runner passes 16 checks across 2+2+2, one-by-six, seven-copy, malformed, provenance/future-field, draft-budget, and EBH1 round-trip cases.
- CandidateEvidence now owns the six-copy envelope; Wishlist draft budgeting and EBH1 locked-role import/export consume exact stack totals without changing the separate ordinary 79-copy contract.
- Focused CandidateEvidence, locked-only, assembled Leaderboard/editor, Wishlist model/controller/tier, EBH1 integrity, and module-contract runners pass. Exact-base Fast passes `24/24` with zero failed, unavailable, or skipped checks.
- #43 review PASS at implementation head `6ab0eff`: public model/controller/renderer action probes, exact transfer/reload, ambiguous compatibility, exact 79-copy boundary, Fast `17/17`, integration `70/70`, strict Vibe, and clean diff all passed.
- #43 expected-red failed twice at `same-family exact tiers collided during draft normalization`; the green public model/controller/renderer runner passes 13 checks including no-op, action isolation, transfer/reload, ambiguous compatibility, and 79-copy limits.
- All 20 Wishlist/model/controller/renderer/import/association mapped runners pass; integration remains `70/70` through Fast.
- Exact-base Fast passes `17/17` with zero failed, unavailable, or skipped checks after advancing the enumerated normal Lua runner guard from `215` to `216`.
- Stage 47 / WP3 completed at frozen product-test candidate `915a313`: cumulative Spec, Standards, and adversarial review passed; final Full passed all `18` blocking checks with Lua `215/215`, parse `288/288`, integration `70/70`, and one explicit nonblocking manual SavedVariables skip.
- Stage 47 hygiene was CLEAN across the bounded 30-path WP3 surface; product/test/workflow/contract bytes did not change after Full.
- Stage 48.1 is pointer-only and `NOT_STARTED`; no WP4 design or implementation occurred during consolidation.

## Work log

- Checkpoint 48.4 hygiene was clean across the exact progress projection, its presentation consumers, and automation-only locked-target merger; no safe quick win or evidence-backed debt justified churn.
- Checkpoint 48.4 review repaired same-family locked-target augmentation, then passed exact tier/role presentation and automation acceptance without entering Stage 49.
- Checkpoint 48.4 implements exact role-qualified Wishlist progress across Model, overlay, editor status, MainViewModel, and AutomationRuntime; duplicate exact rows share an order-independent quota and locked revisions participate in overlay invalidation.
- Checkpoint 48.3 hygiene was clean across the private active-role bridge, its three public read call sites, public boundary fixture, and adjacent contract text; no behavior-preserving quick win or evidence-backed debt justified churn.
- Checkpoint 48.3 review passed with no product repair: the exact active-slot bridge remains read-only, active-only, exact-tier/count-bound, and fail-closed at both coherent envelope boundaries. Stage 48 auto-advanced to 48.4.
- Checkpoint 48.3 implements a read-only exact active-total/locked-count bridge across `Wishlist`, `GetLoadoutWishlist`, and `GetLoadoutWishlistState`; no association, server mirror, Snapshot, Designed, or historical evidence is rewritten.
- Checkpoint 48.2 hygiene was clean across CandidateEvidence normalization/snapshot binding, Wishlist counted budgeting/export, Codec locked-role decoding, and the focused runner; no redundant owner, stale marker, or behavior-preserving quick win justified churn.
- Checkpoint 48.2 review initially falsified bound-snapshot immutability and exact category-quality agreement, repaired both at CandidateEvidence, reran focused checks and Fast, then passed and auto-advanced to 48.3.
- Checkpoint 48.1 hygiene was clean across the exact-key model/controller/renderer surface; no redundant branch, correctness defect, safe quick win, or evidence-backed debt item justified post-review churn.
- Checkpoint 48.1 review passed with no actionable correctness, security, scope, or hygiene finding and auto-advanced within Stage 48 to checkpoint 48.2 `NOT_STARTED`.
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

- Checkpoint 48.4 hygiene was clean at repaired product/test head `0d3386d`; no product/test byte changed after focused checks and exact-base Fast `35/35` passed.

## Recommended next action

- Freeze WP4 for the requested final independent Spec/Standards/adversarial reviews and one final Full gate; do not dispatch consolidation or enter Stage 49/WP5.
