# PLAN

## Stage 43 — Exact-head terminal reconciliation and publication

- Goal: prove all eight repairs together, reconcile committed Vibe truth without ignored receipts, refresh PR #13, and stop for independent merge review.
- Decision: represent the candidate as branch `HEAD` plus an exact resolved receipt to avoid an impossible self-referential commit SHA; set the terminal stop only after formal review/hygiene is complete.

### (DONE) 43.1 — Formal cross-finding review and fresh-checkout proof

- Status: `DONE`
- Objective:
  - Validate the unchanged committed repair candidate end-to-end and prove fresh-checkout Vibe and quality behavior before publication.
- Deliverables:
  - Full exactly once plus Package, Security, policy, pre-commit, and scope receipts.
  - Cross-finding adversarial review and directly related repairs only.
  - Disposable clean bootstrap/Fast and Vibe status/dispatcher proof.
  - Exact current-base PR-only path and protected-runtime blob proof.
- Acceptance:
  - [x] Full, Package, Security, release policy, applicable hooks, and all required tools pass; advisory tools remain honestly unavailable when absent.
  - [x] Fresh checkout bootstraps and passes Fast with no ignored dependency assumption.
  - [x] Fresh checkout Vibe validates the committed checkpoint/head/base without ignored LOOP_RESULT state.
  - [x] PR-only range remains infrastructure-only with zero protected runtime/TOC/runtime-test/artifact paths.
  - [x] All temporary package, archive, log, and checkout output is removed.
- Demo commands:
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `git diff --check d0681b6a885db447c94a75f40df7e81f60b74c55...HEAD`
- Evidence:
  - Compact exact-head summaries, fresh-checkout receipts, and protected-scope proof.

### (DONE) 43.2 — Refresh PR #13 and stop at independent review

depends_on: [43.1]

- Status: `DONE`
- Objective:
  - Publish the reviewed repair head normally, record exact CI/review truth, and leave Vibe at a clean terminal external-review boundary.
- Deliverables:
  - Truthful committed terminal STATE/PLAN/CONTEXT/EVIDENCE without ignored receipt dependency.
  - Normal non-force push and exact local/remote head equality.
  - PR #13 body and issue #12 repair/validation updates.
  - Replacement Quality Gate, Release Policy, artifact, mergeability, review, and thread inspection.
- Acceptance:
- [x] Committed STATE identifies branch `HEAD`, exact base, checkpoint DONE, completed acceptance, and next role stop.
- [x] Fresh checkout dispatcher preview agrees with committed terminal state.
- [x] PR #13 remains open/draft/unmerged and exact-head required workflows pass with local/CI parity.
- [x] Issue #12 remains open with the exact final repair/CI status.
- [x] Review/thread counts and all independently owned worktree statuses are unchanged except authorized PR/issue updates.
- [x] No additional Codex review request, merge, release, install, live, or settings action occurs.
- Demo commands:
  - `git push origin infra/viberun-quality-gate`
  - `python <installed-vibe>/scripts/vibe.py --repo-root . status`
  - `git diff --check d0681b6a885db447c94a75f40df7e81f60b74c55...HEAD`
- Evidence:
  - Final SHA, workflow run IDs/conclusions, PR/issue URLs, review/thread state, terminal Vibe status, and boundary recheck.

## Stage 44 — Exact-head CI and fail-closed infrastructure repair

- Goal: repair the four independent-review findings, replace the false synthetic-merge CI premise with auditable exact-head validation, and stop at one truthful final PR head.
- Decision: use one bounded checkpoint because the four changes share the same infrastructure candidate, formal gate, publication, and terminal exact-head acceptance boundary.

### (DONE) 44.1 — Repair the independent-review findings and re-establish terminal truth

- Status: `DONE`
- Objective:
  - Make PR #13's workflow, artifact, analyzer-baseline, and security-bootstrap policies fail closed, then prove every required GitHub job validated the exact final PR head.
- Deliverables:
  - Event-aware immutable candidate/base resolution, explicit checkout refs, blocking HEAD assertions, and workflow-policy fixtures for Quality and Release.
  - Forbidden artifact paths evaluated before narrow sanitized-fixture content exceptions, with staged/all-tracked hostile fixtures.
  - Ordinal PSScriptAnalyzer owner/fingerprint collections with case-distinct and duplicate fixtures.
  - One pre-use security-manifest metadata validator covering executable, version, requirements, archive, and install path fields with hostile fixtures.
  - Append-only correction/formal evidence, normal publication, exact-head per-job CI receipts, and final dispatcher-owned stop state.
- Acceptance:
  - [x] All four pre-repair expected-red probes fail for the intended reason and their focused regression suites pass after repair.
  - [x] Every Quality and Release source checkout selects and asserts the immutable candidate SHA while range gates retain the immutable PR base SHA.
  - [x] Fast, Full, Package, and Security pass on one frozen local candidate; advisory-unavailable and manual SavedVariables limits remain explicit.
  - [x] Exact-base scope remains infrastructure-only, all diff/artifact checks pass, and a dependency-clean disposable checkout passes bootstrap/Fast/Vibe validation.
  - [x] Replacement Quality and Release jobs are green at the exact final PR head with audited job IDs/checkout SHAs and zero successful artifacts.
  - [x] PR #13, issue #12, and committed Vibe truth correct the superseded synthetic-merge claims and end at `DONE` / `RUN_STOPPED=true` / dispatcher `stop`.
- Demo commands:
  - `node tests/run-quality-workflow-policy.js && node tests/run-quality-gate-self-tests.js && node tests/run-security-policy.js`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Package -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
- Evidence:
  - Four expected-red/green receipts, one formal local candidate summary, and exact-head GitHub job/terminal Vibe receipts.

## Stage 45 — Close the remaining manifest download-URI gap

- Goal: make every manifest-controlled security download URI pass one shared fail-closed policy before use, then re-establish exact-head PR evidence.
- Decision: use one checkpoint because the defect, fixtures, local security gates, publication, and terminal CI reconciliation form one bounded repair.

### (DONE) 45.1 — Validate every security-manifest download URI before use

- Status: `DONE`
- Objective:
  - Reject unsafe `psscriptanalyzer.url` metadata through the same URI-validation owner used by ordinary tool assets, without changing product/runtime behavior.
- Deliverables:
  - One shared strict download-URI validator used by all current security-manifest download fields.
  - Expected-red and focused-green PSScriptAnalyzer/tool-asset URI fixtures with no network access.
  - Append-only finding, validation, publication, exact-head CI, and terminal Vibe receipts.
- Acceptance:
  - [x] The pre-repair resolver accepts `file:`, relative, and plain-HTTP PSScriptAnalyzer URLs for the intended expected-red reason.
  - [x] The shared validator accepts current/safe absolute HTTPS URLs and rejects unsafe URI/path/control-character variants for both download owners.
  - [x] Manifest validation completes before any manifest-controlled download or filesystem mutation, while archive/hash/path/cleanup regressions remain green.
  - [x] Focused security tests, Fast, Security, PSScriptAnalyzer, Gitleaks, and diff/scope checks pass without workflow or protected-runtime changes.
  - [x] The reviewed repair head passes replacement Quality and Release workflows; all seven source jobs assert that SHA and both artifact inventories are empty.
  - [x] PR #13 and issue #12 carry the reviewed repair receipt, and the committed terminal Vibe state returns `DONE` / `RUN_STOPPED=true` / dispatcher `stop`; the resulting receipt head must receive its own replacement CI before final completion.
- Demo commands:
  - `pwsh -NoProfile -File tests/Test-SecurityBootstrapPolicy.ps1`
  - `node tests/run-security-policy.js`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Security -BaseRef d0681b6a885db447c94a75f40df7e81f60b74c55`
- Evidence:
  - Expected-red/green URI matrix, compact local gate summaries, and exact-head GitHub/Vibe receipts.

## Stage 46 — Test19 WP1 locked-migration authority

- Goal: prevent issue #39 corruption by preserving historical rows whenever the durable schema cannot prove provenance.
- Decision: inline and referenced row evidence can be attached by current-state backfill and therefore cannot authorize pre-v1 correction.
- Decision: restore an interrupted immutable source before any legacy migration or other side effect; preserve completed-v1 rows without a durable historical-association bridge.
- Decision: orphan evidence, similarity, current identity, and present ownership never authorize reconstruction; future-owned storage remains read-only.

### (DONE) 46.1 — Fail closed when historical provenance is unavailable

- Status: `DONE`
- Objective:
  - Make locked-baseline migration preserve every historical DPS row because the current durable schema cannot distinguish capture-time history from later current-state backfill.
- Deliverables:
  - New `tests/run_locked_migration_authority.lua` matrix covering remote/local/build rows, ambiguous authority, completed-v1 preservation, orphan evidence, login order, future fields, and no Sync churn.
  - Rewritten lifecycle expectations in `tests/run_migration_owned_lifecycle.lua` preserving authoritative wait, immutable source restore, retry, and idempotence.
  - Minimal `core/DpsCapture.lua` fail-closed migration logic with no transport, identity, qualification, Wishlist, Orb, or UI redesign.
  - Concise `.vibe/EVIDENCE.md` receipts and explicitly staged local follow-up commits.
- Acceptance:
  - [x] The new runner fails on exact starting head because a local lock removes an ordinary Echo from a verified remote row, then passes after repair.
  - [x] Remote, global build, other-account-character, exact-owner-but-unknown-history, completed-v1 ambiguous, orphan-evidence, and no-lock rows remain byte-for-byte stable.
  - [x] Inline/reference equality is not treated as historical provenance; an interrupted source is restored and retired before readiness gating or any side effect; completed-v1 preservation is deterministic and idempotent.
  - [x] DPS/category/duration/owner/future fields, fingerprints, hashes, and Sync-visible row identities remain unchanged.
  - [x] Lua 5.1 parse, mapped DPS/Sync tests, related board/evidence/migration tests, Fast, required Full, and `git diff --check` pass on exact final repaired code/test bytes.
  - [x] Final status contains local WP1 follow-up repair commit(s) and no remote, package, install, Test18, live addon, or SavedVariables change.
- Demo commands:
  - `luajit tests/run_locked_migration_authority.lua && luajit tests/run_migration_owned_lifecycle.lua`
  - `pwsh -NoProfile -File tools/Get-ChangedTestPlan.ps1 -BaseRef 3965b107574d4a394e0672cb130eab7e4694e7b5`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 3965b107574d4a394e0672cb130eab7e4694e7b5`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Full -BaseRef 3965b107574d4a394e0672cb130eab7e4694e7b5`
- Evidence:
  - Expected-red/focused-green authority matrix, compact Fast/Full summaries, independent Spec/Standards PASS, and final exact-scope/commit receipt.

## Stage 47 — Canonical ownership and realm-qualified persistence

- Goal: establish one fail-closed canonical owner authority, make every WP2 consumer use it, and preserve realm-qualified local and public identity without claiming ambiguous legacy evidence.
- Decision: transport-envelope equality, presentation-name equality, durable ownership, and legacy-evidence preservation remain separate contracts.
- Decision: implement the authority owner before its Community, Saved Build, persistence, migration, and public-presentation consumers.

### (DONE) 47.1 — Establish the canonical durable-owner bridge (#28)

- Status: `DONE`
- Objective:
  - Make durable owner claims require an exact realm-qualified transport identity while retaining separate envelope and presentation comparators.
- Deliverables:
  - One canonical-owner API in `core/Identity.lua` with explicit verified/unverified results.
  - Sync ingress/egress adoption at durable ownership boundaries without changing protocol 7.
  - A focused authority matrix covering same-name cross-realm, realm-less, reload, relay, and owner-action behavior.
  - Concise expected-red, green, Fast, review, and exact-scope evidence.
- Acceptance:
  - [x] An exact `name@realm` sender can establish only that canonical owner.
  - [x] A same-name sender from another realm cannot claim, edit, delete, relay as owner, or replace that record.
  - [x] Realm-less transport remains unverified and never becomes durable ownership through `SamePlayer()`.
  - [x] `SameTransportSender()` remains the envelope anti-spoofing owner and `SamePlayer()` remains presentation-only.
  - [x] Two verified same-name/different-realm records coexist across reload without ownership drift.
  - [x] Focused owner/transport tests, mapped tests, Lua 5.1 parse, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_sync_owner_claims.lua && luajit tests/run_sync_transport_owner.lua`
  - `luajit tests/run_canonical_owner_authority.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Expected-red/green authority matrix, compact gate summaries, and independent Spec/Standards review.

### (DONE) 47.2 — Make DPS-to-Community ownership authority-first (#41)

depends_on: [47.1]

- Status: `DONE`
- Objective:
  - Prevent DPS-derived Community builds from acquiring local ownership through short-name resemblance or unverified metadata.
- Deliverables:
  - Verified-record authority consumption in the DPS-to-Community synthesis path.
  - Focused local, remote, realm-less, cross-realm, and later-authoritative-promotion coverage.
  - Preservation of current-session local capture and non-owner public visibility.
- Acceptance:
  - [x] Synthesized `ownerKey` and `isMine` originate only from verified canonical record authority.
  - [x] Realm-less and same-short-name remote records receive no owner actions.
  - [x] Later promotion occurs only through the checkpoint 47.1 authority bridge.
  - [x] Current-session local capture and ordinary public display remain functional.
  - [x] Focused Community/DPS tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_community_dps_eligibility.lua && luajit tests/run_record_identity_integrity.lua`
  - `luajit tests/run_community_owner_authority.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Consumer expected-red/green matrix, compact gates, and independent review receipt.

### (DONE) 47.3 — Revalidate Saved Build related-record ownership (#42)

depends_on: [47.1]

- Status: `DONE`
- Objective:
  - Require verified canonical owner equality before any fingerprint, title, subset, or stale persisted-ID relationship may enrich a Saved Build.
- Deliverables:
  - One authority-first related-record resolver in the Saved Build/Community owner.
  - Revalidation of persisted related IDs before class, DPS, or relationship metadata is reused.
  - Focused exact-owner, cross-realm, stale-ID, collision, reload, and valid-local coverage.
- Acceptance:
  - [x] Exact verified owner equality precedes all content-similarity scoring.
  - [x] Cross-realm and unverified candidates cannot contribute class, DPS, ownership, or related IDs.
  - [x] Persisted relationships are cleared or ignored when authority no longer validates.
  - [x] Valid exact-owner relationships and current-session local capture remain functional.
  - [x] Focused association/identity tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_snapshot_wishlist_association.lua && luajit tests/run_record_identity_integrity.lua`
  - `luajit tests/run_saved_build_related_owner.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Stale/collision expected-red matrix, focused green, and independent review receipt.

### 47.4 — Qualify mutable character state and preserve ambiguous legacy evidence (#30, #37)

depends_on: [47.1]

- Status: `NOT_STARTED`
- Objective:
  - Key mutable character state by canonical `name@realm` and make every registration/migration path preserve ambiguous short-name and `@unknown` evidence.
- Deliverables:
  - Realm-qualified `Store.State` and current-character registration ownership.
  - Coordinated conservative handling in `core/Store.lua` and `core/LegacyDataMigration.lua`.
  - Focused realm-unavailable, two-realm, login-order, canonical-wins, ambiguous-legacy, and reload coverage.
- Acceptance:
  - [ ] RealmA and RealmB mutable state remain independent under the same short name.
  - [ ] Realm-unavailable startup creates no durable `name@unknown` mutable key.
  - [ ] Existing canonical state wins without deleting or absorbing ambiguous legacy evidence.
  - [ ] Both registration and legacy migration preserve `@unknown`/short-key evidence regardless of login order.
  - [ ] Focused Store/migration tests, mapped tests, Lua 5.1 parse, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_store_legacy_retirement.lua && luajit tests/run_legacy_data_migration.lua`
  - `luajit tests/run_realm_qualified_state.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Realm/login-order expected-red matrix, focused green, and independent review receipt.

### 47.5 — Reconcile public same-name evidence without erasure (#19)

depends_on: [47.2, 47.3, 47.4]

- Status: `NOT_STARTED`
- Objective:
  - Present and reconcile public records by proven canonical identity while retaining distinguishable ambiguous legacy and better historical evidence.
- Deliverables:
  - One shared public identity presentation/reconciliation policy for Leaderboard Dummy, LK, Combined, and Community surfaces.
  - Focused verified-same, verified-different-realm, ambiguous-legacy, reload, and Sync reintroduction coverage.
  - No destructive historical-DPS cleanup for visual convenience.
- Acceptance:
  - [ ] The same proven canonical identity may reconcile deterministically.
  - [ ] Proven different realms remain separate and visibly distinguishable.
  - [ ] Verified and ambiguous legacy evidence never render as indistinguishable duplicate rows.
  - [ ] Better historical DPS is preserved when authority is insufficient to merge or discard it.
  - [ ] Dummy, LK, Combined, Community, reload, and Sync use one identity policy.
  - [ ] Focused UI/board tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_dps_boards.lua && luajit tests/run_leaderboard_ui.lua`
  - `luajit tests/run_public_identity_presentation.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Public-identity expected-red/green matrix, compact gate summaries, and independent review receipt.

## Stage 48 — Exact Wishlist tiers and locked-role evidence

- Goal: preserve exact ordinary tier rows, exact locked copy counts, authoritative lock mirroring, and exact-quality progress across the complete Wishlist pipeline.
- Decision: exact `spellId` is the ordinary row identity when trustworthy; family remains grouping metadata and never satisfies or edits a sibling tier.
- Decision: ordinary, locked, and active-loadout evidence remain separate roles with separate limits and authority.

### 48.1 — Preserve exact ordinary tier rows (#43)

- Status: `NOT_STARTED`
- Objective:
  - Make editor open/edit/save and row actions round-trip every ordinary quality tier independently.
- Deliverables:
  - Exact-tier draft/model identity with deterministic fallback for compatibility rows lacking trustworthy `spellId`.
  - Exact-row `+`, `-`, selection, and remove behavior.
  - Multi-tier family round-trip and 79-copy total coverage.
- Acceptance:
  - [ ] Common, Uncommon, and Rare rows in one family survive a no-op round-trip unchanged.
  - [ ] Editing or removing one exact tier cannot modify a sibling tier.
  - [ ] Ordinary total validation counts stack copies across every exact row and enforces 79.
  - [ ] Locked intent remains outside the ordinary editor-row identity.
  - [ ] Existing single-tier and compatibility-row behavior remains deterministic.
  - [ ] Focused Wishlist model/editor tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_wishlist_editor.lua && luajit tests/run_wishlist_model_parity.lua`
  - `luajit tests/run_wishlist_tier_roundtrip.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Multi-tier expected-red/green matrix, compact gates, and independent review receipt.

### 48.2 — Preserve and validate exact locked copy totals (#44)

depends_on: [48.1]

- Status: `NOT_STARTED`
- Objective:
  - Validate locked evidence by copy total and preserve valid stack counts through candidate, draft, and export boundaries.
- Deliverables:
  - One locked-role copy-total owner enforcing `sum(stacks) <= 6` without row-count shortcuts.
  - Candidate-to-draft-to-export stack preservation.
  - Focused valid duplicate, six-copy, seven-copy, malformed, overflow, and ordinary/locked-role coverage.
- Acceptance:
  - [ ] Six locked copies are accepted whether represented by one or several exact rows.
  - [ ] Seven locked copies and malformed/overflow stacks are rejected rather than clamped.
  - [ ] A valid `stacks=N` value never silently becomes one during conversion or export.
  - [ ] Ordinary copies and locked copies retain separate roles and limits.
  - [ ] Focused CandidateEvidence/Wishlist tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_stage35_candidate_evidence.lua && luajit tests/run_locked_only_loadout_characterization.lua`
  - `luajit tests/run_locked_copy_totals.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Copy-total expected-red/green matrix, focused gate summaries, and independent review receipt.

### 48.3 — Bridge only verified active locks into the designed mirror (#20)

depends_on: [48.2]

- Status: `NOT_STARTED`
- Objective:
  - Mirror locked intent only from an exact verified active-loadout association, without treating current resemblance as historical or designed authority.
- Deliverables:
  - One exact active-to-designed association bridge consuming checkpoint 48.2 locked evidence.
  - Focused exact-match, subset/collision, stale association, cross-owner, reload, and no-authority coverage.
  - Preservation of independent Snapshot and Designed roles.
- Acceptance:
  - [ ] Only an exact verified active-loadout association can update the designed mirror's locked role.
  - [ ] Short-name, family, subset, title, and stale-ID resemblance never authorizes the bridge.
  - [ ] Cross-owner and unverified associations preserve existing data without promotion.
  - [ ] Exact verified updates preserve every locked stack and the six-copy limit.
  - [ ] Focused association tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_snapshot_wishlist_association.lua && luajit tests/run_locked_evidence_resolver.lua`
  - `luajit tests/run_active_wishlist_lock_bridge.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Authority/collision expected-red matrix, focused green, and independent review receipt.

### 48.4 — Report exact-tier Wishlist progress (#35)

depends_on: [48.1, 48.2, 48.3]

- Status: `NOT_STARTED`
- Objective:
  - Make overlay, HUD, model, and editor progress consume the same exact tier and role evidence.
- Deliverables:
  - Exact-spell/tier ownership projection in `ui/WishlistOverlay.lua` and its shared model boundary.
  - Focused sibling-tier, per-tier quota, locked-role, refresh, and parity coverage.
  - Removal of family-level satisfaction as an authority decision.
- Acceptance:
  - [ ] A lower-quality sibling never satisfies a higher-quality target.
  - [ ] Each exact tier reports its own owned copies, target quota, and completion state.
  - [ ] Ordinary and locked progress consume their correct evidence roles.
  - [ ] Overlay, HUD, model, and editor agree before and after refresh/reload.
  - [ ] Focused overlay/parity tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_wishlist_overlay.lua && luajit tests/run_wishlist_renderer_parity.lua`
  - `luajit tests/run_wishlist_exact_progress.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Sibling-tier expected-red/green matrix, parity gates, and independent review receipt.

## Stage 49 — Historical DPS authority and real paired summaries

- Goal: keep historical locked snapshots immutable and make every Dummy/LK average represent one real authority-compatible pair rather than independently selected category maxima.
- Decision: historical snapshot evidence and current/build copy authority are separate; neither timestamp nor category winner alone may rewrite the other.
- Decision: category bests may remain useful independently, but Average is unavailable unless a real pair shares canonical owner, ordinary fingerprint, and locked/full-combat identity.

### 49.1 — Separate historical locked snapshots from copy authority (#23)

- Status: `NOT_STARTED`
- Objective:
  - Preserve capture-time locked evidence while resolving current copy authority only through a stronger exact association.
- Deliverables:
  - Explicit historical-snapshot versus current/build-authority roles in locked evidence resolution.
  - Focused later-current-state, category-order, timestamp-order, exact-authority, conflict, reload, and Sync coverage.
  - Immutable historical DPS rows when exact copy authority is absent.
- Acceptance:
  - [ ] Later current/build state cannot rewrite a historical locked snapshot by resemblance or recency.
  - [ ] Category winner and timestamp order never select copy authority by themselves.
  - [ ] Stronger exact current authority may resolve a copy operation without mutating historical evidence.
  - [ ] Conflicting or incomplete authority preserves history and reports unavailable/conflict explicitly.
  - [ ] Focused locked-evidence/DPS tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_locked_evidence_resolver.lua && luajit tests/run_stage32_leaderboard_locked_fidelity.lua`
  - `luajit tests/run_historical_locked_authority.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Historical/current expected-red matrix, focused green, and independent review receipt.

### 49.2 — Compute Average only from a real compatible Dummy/LK pair (#26)

depends_on: [49.1]

- Status: `NOT_STARTED`
- Objective:
  - Select the best real Dummy/LK pair sharing verified owner and exact ordinary plus locked/full-combat identity, or expose Average as unavailable.
- Deliverables:
  - One pair-compatibility predicate and deterministic best-real-pair selector in the DPS projection owner.
  - Focused mixed-owner, mixed-ordinary, mixed-locked, multiple-valid-pair, missing-authority, ordering, and reload coverage.
  - Preservation of independently useful category bests without synthesizing their mean.
- Acceptance:
  - [ ] Every displayed Average comes from two actual records with the same verified canonical owner.
  - [ ] The pair shares the same ordinary fingerprint and locked fingerprint/full-combat identity.
  - [ ] Mixed owners or incompatible builds never produce an Average even when each is a category best.
  - [ ] Multiple valid pairs choose the deterministic best real pair; no valid pair reports Average unavailable.
  - [ ] Dummy and LK category bests remain independently available without implying a pair.
  - [ ] Focused DPS/board/UI tests, mapped tests, Fast, required review/Full, and diff checks pass.
- Demo commands:
  - `luajit tests/run_dps_boards.lua && luajit tests/run_leaderboard_ui.lua`
  - `luajit tests/run_paired_dps_summary.lua`
  - `pwsh -NoProfile -File tools/Invoke-QualityGate.ps1 -Mode Fast -BaseRef 03870e75254848c941dcd3534a9c79a90a644fe3`
- Evidence:
  - Pairing expected-red/green matrix, exact summary receipts, and independent Spec/Standards review.
