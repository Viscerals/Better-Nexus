# STATE

- Schema version: 1.0
- Vibe package version: 0.1.0+codex.20260812081901
- Prompt catalog version: 1.1.0

## Current focus

- Stage: 50
- Checkpoint: 50.1
- Status: IN_REVIEW
- Branch: `bugfix/test19-wp6-build-hash-buckets-erase-build-id-type-and-can-r`
- Starting head: exact accepted WP5 handoff head `8f5d28008935cef2d973b800167695ab50e0f70b`
- Worktree: `.test19-wp4-worktree`
- Base: exact accepted WP5 handoff head `8f5d28008935cef2d973b800167695ab50e0f70b`

## Objective (current checkpoint)

Preserve typed build identity in Sync's canonical build and tombstone bucket-hash material without changing the deterministic eight-bucket reconciliation design.

## Deliverables (current checkpoint)

- Focused expected-red typed build/tombstone, reconciliation, delta/legacy, invalidation, and ordering coverage.
- Typed canonical build and tombstone entry material in `core/BuildHashCache.lua`.
- Explicit mixed old/new digest compatibility behavior preventing permanent false equality.

## Acceptance (current checkpoint)

- [ ] Numeric `1` and string `"1"` hash differently for builds and tombstones; equal typed states remain equal.
- [ ] Numeric/string peer mismatch cannot skip reconciliation.
- [ ] Both typed IDs hash deterministically across iteration order and rebuild paths.
- [ ] Delta and legacy modes preserve typed identity and ordinary strings remain deterministic.
- [ ] Mixed old/new behavior prevents permanent protocol-compatible false equality.
- [ ] Blocking focused, mapped, Fast, Full, Lua, parse, integration, policy, and diff checks pass.
- [ ] Nonblocking manual SavedVariables/native validation remains explicitly unverified.

## Evidence

- path: .vibe/EVIDENCE.md
- Issue #40 expected red failed at `numeric and string build IDs share one bucket hash`; typed build/tombstone, mixed old/new, ordering, candidate-token, cache invalidation, and baseline-delta focused runners now pass.
- Fast passed `20/20` blocking checks with Lua 5.1 parse, Sync mapped tests, integration `70/70`, policy, metadata, release, security, and diff checks; zero failed, skipped, or unavailable checks.
- Controller repair excludes labels, category, resemblance, and temporal metadata from equal-DPS ties through an explicit projection allowlist; retention resolves the accepted pair through preserved source references. Expected-red reproduced both findings, focused paired/retention/board/Leaderboard/view tests pass, and Fast passes `43/43`.
- WP5 implementation candidate separates historical locked snapshots from exact current/build copy authority and centralizes verified-owner + ordinary + locked/full-combat real-pair metrics across Community eligibility/averages, Leaderboard sync/resumable projections, retention, and DPS sorting. Focused authority/pairing matrices pass; Fast passes `37/37`; final Full passes `18` blocking checks with Lua `221/221`, parse `294/294`, integration `70/70`, zero failed/unavailable checks, and one explicit manual SavedVariables skip.
- Stage 49 test-gap analysis prioritized five risk-backed matrices: `[MAJOR]` immutable historical snapshots versus exact later copy authority; `[MAJOR]` verified-owner + ordinary + locked/full-combat pair compatibility; `[MAJOR]` Community/Leaderboard/sort parity from one metric; `[MODERATE]` category/timestamp permutation invariance; `[MODERATE]` reload/restart/Sync convergence with preserved conflict evidence.
- Exact-head review of `432e2ed` found and repaired catalog-owner drift, semantic target-cache staleness, row-order replacement identity, malformed/overflow locked evidence in Main/HUD and other consumers, and nested provenance aliasing. The affected matrix passes with locked totals `65`, controller `54`, AutoLock `105`, active bridge `19`, and exact-base Fast `45/45`; strict Vibe and diff checks pass.
- Standards re-review of `94610e3` found and repaired direct admission-output aliasing plus duplicated/drifted Policy locked validation. `logic/Model.lua` is now the single pure locked-evidence admission owner, TargetMapEntries returns defensive values/catalog rows, locked totals pass `66`, Policy scenarios pass `54`, and exact-base Fast remains `45/45`.
- Standards review of `04729be` found and repaired Policy's final raw-versus-normalized spell-map merge. Policy now consumes the full shared projection; lone string keys normalize to numeric exact authority, aliases still fail closed, and exact-base Fast remains `45/45`.
- Adversarial review of `ade58ba` found and repaired the last catalog-admission bypass in persisted editor reopen/commit planning. Mixed known/unknown maps now reopen and commit nothing; locked totals pass `68`, controller `55`, and exact-base Fast remains `45/45`.
- Adversarial review of `cb3f875` found and repaired malformed/catalog-disagreeing target-row quality plus EBH1 nonfinite formatting. Reopen, fulfilled export, and encode probes pass; locked totals advance to `80` and exact-base Fast remains `45/45`.
- Review of `16df8d8` aligned EBH1 encode/decode tuple and aggregate bounds and repaired the assembled Stage 32 fixture's missing family projection. Locked totals pass `85`, assembled Stage 32 passes `47`, integration remains `70/70`, and exact-base Fast remains `45/45`.
- Final independent Spec, Standards, and adversarial reviews PASS on exact clean product/test head `38d148e4034efde735ea346f7a6c3cc72b074560`. The combined focused matrices cover `21`/`9`/`17` runners; no actionable WP4 finding remains. Native WoW remains unverified.
- Cumulative independent review rejected `7cff7e7` and drove five focused WP4 repairs: true total-minus-locked derivation, counted lock-target continuity, exact-spell automation matching, synced-only Policy authority, and exact renderer selection keys. All deterministic red probes are now green; 19 focused runners and exact-base Fast `39/39` pass on the repaired working candidate.
- #35 checkpoint review found and repaired a same-family automation omission: locked sibling tiers and extra locked copies now extend an automation-only exact target without mutating the server Wishlist. The expected-red failed twice, the repaired Stage 32 fixture passes 65 checks, and exact-base Fast passes `35/35` with zero failed/unavailable/skipped checks.
- #35 expected-red failed twice at `wrong-quality family ownership marked the exact Rare overlay row complete`; the green public runner proves exact Common/Rare separation, duplicate locked quota grouping, role-specific ownership, locked-only refresh, HUD/automation parity, and exact recovery.
- `Model.WishlistEntryProgress` is the pure exact `(role, spellId)` progress owner. Overlay and editor consume it directly; MainViewModel consumes it for explicit-role Wishlists while retaining deterministic legacy behavior for role-unrepresented inputs. Exact-base Fast passes `34/34` with zero failed/unavailable/skipped checks.
- #20 checkpoint review passed with two coherent envelope probes: exact 78 ordinary + seven locked and exact 80 ordinary + five locked both remain unavailable, while restored 79+6 recovers. The strengthened runner passes 16 checks and exact-base Fast remains `26/26` with zero failed/unavailable/skipped checks.
- #20 expected-red failed twice at `exact active/associated mirror remained evidence-pending`; the green public GameAdapter runner passes 13 checks across exact 79+6 derivation, same-tier overlap, sibling quality preservation, mismatch/partial/underflow refusal, reload convergence, and source/SavedVariables immutability.
- The bridge is active-slot-only and requires a verified active total, aggregated exact spell/copy identity, CandidateEvidence's six-copy envelope, and synchronized exact `LockedOwned.bySpell` agreement; inline role booleans are not authority.
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

## Archived Stage 48/49 work detail

- WP5 implementation completed issues #23/#26 on one coherent candidate: copy paths require exact build-bound locked authority; historical category rows remain preserved for display; one deterministic real-pair owner feeds qualification, Community averages, Leaderboard, retention, and sorting. Final Fast `37/37` and Full `18/18` pass.
- Stage 49 maintenance test-gap analysis selected five non-duplicative expected-red matrices covering immutable history, exact copy authority, real-pair identity, cross-surface parity, ordering, and persistence/Sync convergence.
- Stage 48 retrospective completed with five WP5 actions: one DPS authority verdict, adversarial immutable-history coverage, read-only copy resolution, shared projection parity, and pre-Full reload/Sync matrices.
- Review wave 2 at `432e2ed` centralized catalog-bound target admission, canonicalized semantic target identity, made target/provenance results cycle-safe defensive copies, and atomically rejected malformed or seven-copy locked evidence across GameAdapter, controller/export/renderer, Main/HUD, Policy, and AutoLock. Focused probes and exact-base Fast `45/45` pass; a new exact local commit and three fresh independent reviews remain before Full.
- Standards review at `94610e3` closed the prior catalog boundary and exposed the last two owner-consistency gaps. Direct admitted values/catalog rows are now defensive, and Policy plus every Wishlist consumer shares `Model.LockedProjection`; focused tests and Fast `45/45` pass. A new exact local commit and all three fresh reviews remain before Full.
- Independent re-review closed the prior five repairs and found six further exactness gaps at `1afec7d`. Versioned counted-target validation, copy-based capacity/deficit admission, aggregation-stable identity, synced defensive renderer/export projections, and exact guaranteed-queue matching now pass 20 focused runners and exact-base Fast `41/41`.
- Exact-head audit before accepting `72355cb` found and repaired one remaining persisted-record identity mismatch plus duplicate-validator drift: WishlistModel now solely validates finite version-1 records and requires every dense row to name the containing exact spell. All 20 focused runners pass, including locked totals 29 checks, AutoLock 71, and integration `70/70`; exact-base Fast passes `43/43` with zero failed/unavailable/skipped checks.
- Paused review at `ce6433f` found and repaired unsupported scalar target authority and distinct-ID Locked-strip occupancy. Only legacy `true` and positive finite integer replacement IDs remain compatible; six physical UI slots now represent six copies, not spell identities. Locked totals pass 36 checks, AutoLock 85, all 20 focused runners and exact-base Fast `43/43` pass.
- Paused review at `64a27ee` found and repaired two final validator-consumer leaks: MainViewModel progress/Tome projections now omit invalid persisted targets, and exact-key/type validation precedes every replacement side effect. Locked totals pass 38 checks, exact projection probes pass, all 20 focused runners and exact-base Fast `43/43` pass.
- Paused review at `826d3a9` found and repaired invalid containing map-key coercion. The validator now rejects fractional, nonfinite, zero, and negative expected spell IDs before every scalar/table branch; commit, progress/Tome, and AutoLock probes pass. Locked totals pass 43 checks, AutoLock 87, the affected matrix and exact-base Fast `43/43` pass.
- Paused review at `55804dd` found and repaired mixed-map AutoLock admission plus nonfinite locked-evidence IDs. Any invalid target key rejects the whole AutoLock descriptor map; controller/export/renderer and Policy reject nonfinite locked spell IDs. AutoLock 87, controller 50, renderer/Policy probes, the affected matrix, and exact-base Fast `43/43` pass.
- Final review of `f7c8c45` found and repaired atomic target-map admission, the six-copy aggregate envelope, coherent locked family derivation, canonical aliases, exact multi-replacement convergence, nonfinite ordinary identity, exact typed editor reopen, and unknown target-envelope continuity. Locked totals 57, controller 51, active bridge 19, AutoLock 105, the complete affected matrix, integration `70/70`, module contracts with zero unmapped surfaces, and exact-base Fast `44/44` pass. A new local commit and three exact-head independent re-reviews remain before Full.
- Cumulative WP4 independent review found five valid Spec/Standards/adversarial gaps at `7cff7e7`; all were repaired with public counterexamples and focused/Fast revalidation. The repaired candidate is ready for all three independent reviews to repeat before Full.
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

## Work log

- Checkpoint 50.1 preserves typed build/tombstone identity in cached and fallback delta/legacy digest material plus resumable reconciliation tokens; focused tests pass and Fast passes 20/20.
- Stage 49 retrospective completed with five lessons on shared semantic projections, adversarial state matrices, bounded async work, source/display separation, and checkpoint scope.
- Stage 50 design confirmed checkpoint 50.1 as the single bounded issue #40 implementation seam in BuildHashCache with focused Sync compatibility coverage.
- Stage 50 documentation gap scan found no WP6-scoped documentation change; typed digest identity remains a source-and-regression-test contract.
- Stage 50 designed one bounded issue #40 checkpoint and archived completed WP5 detail.
- Stage 49 completed with accepted review, hygiene, Fast, and Full receipts.

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

- WP4 remains frozen; WP5 is authorized only in `.test19-wp4-worktree` on the reconciled WP5 branch, with no push, PR/issue mutation, publication, install, native WoW, or live SavedVariables work.
- Treat the master-chat order as authoritative: WP2 is #28/#41/#42, WP3 is #30/#37 then #19 acceptance, WP4 is #43/#44/#20/#35, and WP5 is #23/#26.
- Preserve every independently owned worktree and the frozen WP2/PR #53 and WP3/PR #54 boundaries; only `.test19-wp4-worktree` owns this local WP4 range.
- Exact canonical identity owns durable authority; ambiguous and future-owned evidence remains preserved, non-authoritative, and fail-closed.
- Exact `spellId` owns ordinary Wishlist row identity when trustworthy; family is grouping metadata only. Locked roles require exact counted authority and ordinary roles are derived read-only by exact total-minus-locked subtraction.

## Last completed loop

- Checkpoint 49.2 hygiene CLEAN at receipt head `fd4b6f6` for reviewed product/test head `de04122`: the prohibited tie-input and retention-source repairs pass focused paired DPS, retention, board, Leaderboard, and view tests; Fast passes `43/43`; the exact-head Full receipt remains `18` blocking passes with Lua `221/221`, Lua 5.1 parse `294/294`, integration `70/70`, and one explicit nonblocking manual SavedVariables skip. No checkpoint-hygiene signal was identified; native WoW remains unverified.

## Recommended next action

- Return the clean local WP5 receipt commit to the controller-owned independent review; do not begin another design cycle or publish from this worker.


## Archived session detail
- Stage 50 design added one bounded issue #40 checkpoint for typed build/tombstone hash identity, reconciliation, invalidation, delta/legacy determinism, and mixed-client compatibility.
- Checkpoint 49.2 prohibited-tie/retention-source hygiene CLEAN: bounded repaired surface has no correctness, security, duplication, or safe high-ROI cleanup signal; Full was not repeated.
- Review PASS at exact head de04122: Full 18 blocking passes; Lua 221/221, parse 294/294, integration 70/70; one nonblocking manual SavedVariables skip remains unverified
- Repair prohibited DPS tie inputs and preserve retention pair sources
- Controller review repair: SPEC-PROHIBITED-TIE-INPUTS; SPEC-RETENTION-PAIR-REFERENCE-LOSS; VIBE-CHECKPOINT-CONTRADICTION
- Checkpoint 49.2 recency-tie hygiene CLEAN: bounded CandidateEvidence/test/state surface has no safe high-ROI cleanup or actionable debt; Full was not repeated.
- Review PASS at exact head 3c2c932: Full 18 blocking passes; one nonblocking manual SavedVariables skip remains unverified.
- Clock-neutral equal-DPS pair ties preserve source history; focused parity and Fast 43/43 pass.
- Controller review repair: SPEC-PAIR-TIE-RECENCY-LEAK; VIBE-CHECKPOINT-SEMANTIC-MISMATCH
- Checkpoint 49.2 hygiene CLEAN: no product/test byte changed after Full; bounded repaired surface has no correctness, security, or high-ROI cleanup signal.
- Review PASS at exact product/test head d5b8cc0: Full 18 blocking passes, Lua 221/221, parse 294/294, integration 70/70; one nonblocking manual skip remains unverified.
- Full-discovered work-budget and exact-empty fixture repairs pass affected runners and Fast 43/43.
- Review FAIL: live projection tie exceeded comparison budget; legacy exact-empty fixture lacked lockedAuthorityProven.
- WP5 review repairs require explicit empty authority, finite overflow-safe pair averages, and deterministic output-relevant ties; focused and Fast 43/43 pass.
- Controller review FAIL: SPEC-EMPTY-COPY-AUTHORITY; ADV-PAIR-AVERAGE-OVERFLOW; SPEC-PAIR-TIE-NOT-TOTAL
- Controller receipt reconciliation aligned PLAN checkpoints 49.1 and 49.2 with verified review PASS and hygiene receipts.
- Review PASS at exact product/test head 47c3a3b: Full 18 blocking passes, Lua 221/221, parse 294/294, integration 70/70; one nonblocking manual skip remains unverified.
- Full-discovered durable ordinary-evidence fixtures repaired; five focused runners and Fast 43/43 pass.
- Review FAIL: Full exact head f615b78 exposed five legacy fixtures without verified ordinary Echo evidence.
- WP5 review repairs validate ordinary evidence, total pair ties, and fully bounded pair pumps; focused and Fast 43/43 pass.
- Controller review repair: VALIDATION-EXACT-HEAD-MISMATCH; VIBE-CHECKPOINT-CONTRADICTION; SPEC-ORDINARY-FINGERPRINT-CLAIM; SPEC-PAIR-TIE-NONDETERMINISM; STANDARDS-UNBOUNDED-PAIR-PUMP
- Checkpoint 49.2 hygiene CLEAN: bounded product/test surface had no safe high-ROI cleanup, actionable debt, or correctness/security finding; no product/test byte changed and Full was not repeated.
- Fast 43/43 confirms deterministic real-pair authority and projection parity
- Controller repair alignment: SPEC-PAIR-ASYNC-DIVERGENCE; SPEC-EMPTY-COPY-AUTHORITY; ADV-NONFINITE-PAIR; VALIDATION-MIXED-STATE-GAP; VIBE-CHECKPOINT-CONTRADICTION
- Mechanical PASS recovery advanced the reviewed 49.1 pointer to 49.2.
- Exact-head Full passed 18 checks; bounded real-pair and copy-authority repairs accepted
- Bounded shared real-pair cursor passes focused work-budget and Fast 43/43
- Full found unbounded real-pair selector work in active Sync projection pump
- WP5 review repairs validated: async parity, empty authority, finite DPS, and mixed-state coverage
- Controller review repair: SPEC-PAIR-ASYNC-DIVERGENCE; SPEC-EMPTY-COPY-AUTHORITY; ADV-NONFINITE-PAIR; VALIDATION-MIXED-STATE-GAP; VIBE-CHECKPOINT-CONTRADICTION


## Work log (current session)
- WP6 typed cache matrix and exact-head Fast/Full validation pass; native WoW remains unverified
- Controller review repair: VALIDATION-EXACT-HEAD-AND-FULL-MISSING; SPEC-TYPED-CACHE-INVALIDATION-COVERAGE
