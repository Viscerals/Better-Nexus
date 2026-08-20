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

### 45.1 — Validate every security-manifest download URI before use

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
