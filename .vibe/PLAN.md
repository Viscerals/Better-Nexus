# PLAN

## Stage 50 â€” Sync Trust package partition

- Goal: publish Package A as a small reviewable trust boundary, then stop before
  the separately designed Package B catalog-authority state machine.
- Decision: Package A owns issues #24, #27, and #31 only.
- Decision: Package B owns issue #22 and every catalog admission, tombstone,
  retention, compaction, semantic-envelope, and rollback authority change.

### 50.1 â€” Publish Package A (#24, #27, #31)

- Status: `IN_PROGRESS`
- Objective:
  - Publish one clean draft PR directly atop exact PR #67.
- Deliverables:
  - Reversible inert presentation for untrusted remote text.
  - No unsolicited remote developer-status reply.
  - Peer versions retained as bounded observations without release authority.
  - Focused regressions, exact-head local gates, and exact-head GitHub CI.
- Acceptance:
  - [x] Raw storage and evidence remain lossless and separate from display text.
  - [x] Rich-text and focused EditBox sinks receive inert projections.
  - [x] Remote WLRQ handling is inert without rejection spam or pending state.
  - [x] Peer observations cannot create or preserve authoritative update notices.
  - [x] Package B and typed-digest owners remain outside the diff.
  - [x] Independent Spec and Standards reviews pass.
  - [ ] Final exact-head Fast and Full pass.
  - [ ] Draft PR and required exact-head CI pass.
- Evidence:
  - `.vibe/EVIDENCE.md` Stage 50.1 reconstruction and review receipt.

### 50.2 â€” Define Package B catalog authority (#22)

depends_on: [50.1]

- Status: `DONE`
- Objective:
  - Define one architecture-approved catalog-authority state machine before any
    Package B implementation.
- Acceptance:
  - [x] Master review supplies the authority model and bounded implementation
    contract after Package A publication.
  - [x] No Package B product, test, branch, or worktree work starts early.
- Evidence:
  - Accepted architecture commit `3b5de54f56f1c27678e53b1dd7e1de742de820af`
    supplies `docs/SYNC_TRUST_PACKAGE_PARTITION_AUDIT.md` and
    `docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md` as design authority
    only; neither is merged nor cherry-picked into the product range.

### 50.3 - Implement Package B catalog authority (#22)

depends_on: [50.2]

- Status: `IN_PROGRESS`
- Objective:
  - Complete the third and final bounded repair wave for `MASTER-W2-001`
    through `MASTER-W2-011`, mapped only to `MASTER-RC-002`,
    `MASTER-RC-006`, `MASTER-RC-007`, and `MASTER-RC-017`.
  - Freeze one coherent candidate for exact-head validation and one fresh
    independent acceptance campaign.
- Deliverables:
  - One complete root with adjacent protected durable-bundle and serving-root
    publication.
  - Detached retention and compaction candidates with exact old bytes and
    identities on pending, refusal, cancellation, drift, and fault.
  - One atomic imported public row plus saved-source backlink mutation.
  - Persistent metered mutation, maintenance, evidence, copy, witness, index,
    and consumer cursor frontiers.
  - Strict one-call collection refusal independent of match density.
  - Exact saved-import cleanup ownership through every removal settlement.
  - One retained inbound Sync mutation and one terminal bookkeeping route.
  - Complete receipt-range and external-owner counter exhaustion preflight.
  - EvidenceCoordinator identity and evidence append/removal revision binding.
  - Lua 5.1, WoW 3.3.5a, protocol 7, Package A, typed-ID, future-schema,
    unknown-field, mixed-peer, and locked-evidence compatibility.
- Acceptance:
  - [x] A genuine expected-red matrix was recorded on exact PR #68 before the
    original Package B product edit.
  - [x] Wave 1 implementation, freeze, exact-head validation, and independent
    rejection evidence remain preserved.
  - [x] Wave 2 implementation froze at
    `66e175b6296606e39bbec45ac30a109e21ab0ea9`, tree
    `fd2041bf2b9a7f6da3bdbb2716303ee4f99fb305`.
  - [x] Wave 2 exact-head Fast passed 230/230, Full passed 18 checks with one
    explicit manual SavedVariables skip, and Lua passed 243/243.
  - [x] Fresh independent Wave 2 MASTER completed and rejected the candidate
    with `MASTER-W2-001` through `MASTER-W2-011`.
  - [x] Direct Wave 3 authority, exact paths, current route, and counter
    transition were recorded before the first tracked Wave 3 edit.
  - [x] Fail-capable expected-red probes reproduce all eleven findings on the
    exact rejected bytes.
  - [x] All eleven shared mechanism repairs pass their focused and affected
    subsystem controls.
  - [x] The complete integrated inventory, policy, security, artifact, module,
    upvalue, parse, integration, path, and diff checks pass on coherent bytes.
  - [x] One coherent Wave 3 freeze commit records commit, tree, parent, and
    exact path inventory (parent
    `66e175b6296606e39bbec45ac30a109e21ab0ea9`; the commit and tree hashes are bound by
    the external exact-head receipts).
  - [ ] Exact-head Fast and one Full pass on that frozen clean commit.
  - [ ] Fresh isolated SPEC, STANDARDS, and ADVERSARIAL lanes finish, followed
    by a separate fresh MASTER acceptance.
- Evidence:
  - `.vibe/EVIDENCE.md` Stage 50.3 Wave 3 receipts.
  - Canonical packet:
    `C:\T3\BN\task-packets\catalog-authority-22-repair-wave-3.json`,
    SHA-256
    `760864fe79c3ca2962e8d7ff8610443e5a1f1e992113ec1734ecb86666b9d984`.
  - Pre-edit receipt:
    `C:\T3\BN\receipts\wave3\CODEX_WAVE3_PREEDIT_AUTHORIZATION_2026-09-12.md`,
    SHA-256
    `0a62bee967aeabfabe9ea31ed38072bf6e1fbd1c570d572a09c7df9111c9e1e0`.
  - Direct authorization attachment SHA-256
    `1f86ed284803d4b5e61c9fd102dac4be5d07b40df112396b541b085d024d64ad`.
  - Rejected Wave 2 MASTER SHA-256
    `e7af6424053f68bd25b66ff36bfdbb6fd5a537c8b33b933f67017a2c78223e72`.
  - Wave 2 MASTER completion receipt SHA-256
    `ac7db486b69c861f5a9d3fde6b19f77fa63a6b7cb7fad35933bc7b057fe4b626`.
  - Governing Amendment 13 lineage SHA-256
    `292d3258f86986297b8eb55c6f9223010bc2bfdb4e4c4ffdf49b99337ab031b4`.
  - Wave 3 successor amendments (existing offline tests only, zero
    production paths): Amendment 1 SHA-256
    `66233393c3c1fc7c60d5fd9ba48fb91ad48afcde21a68f8da3b3c1cc50cfb8d2`,
    Amendment 2 SHA-256
    `a129f3e520e97c6da4d9592286771f2c3e9db48a06048a032ce8b28f0bdfedde`,
    Amendment 3 SHA-256
    `4b9af123b57b2fe0ba7efcf5427c0dd0d353d3f84e23ab27123b3abfc87bdf6c`,
    Amendment 4 SHA-256
    `4ad87f459e9bd84f1882dd40bdb7eff348c537582d54de53bdc43e86699056b3`,
    Amendment 5 SHA-256
    `5dec00acce983cc241f4358a25f007b5c583452489164c1f5ac99b9d14f220ea`.
- Resolved dispatch authority:
  - Direct attachment SHA-256
    `9fb425396620360bbccaa1bb84587621dd714ddc618128fb4dfc4f1c9e0746ab`
    authorizes one normal installed VibeRun `next` submission for this bounded
    Wave 3. Its immutable receipt SHA-256 is
    `15cbfaa5539ee4a65945542c8a776a95e70098815b0eb8f8d24fed8dc0e6f3e7`.
- Current executable chain:
  - Strict Vibe validation -> actual
    `implement / prompt.checkpoint_implementation` dispatch -> expected red
    on exact rejected bytes -> shared mechanism repairs -> focused and subsystem
    green -> complete integrated validation -> exact path reconciliation -> one
    freeze -> exact-head Fast -> one exact-head Full -> fresh independent SPEC,
    STANDARDS, and ADVERSARIAL -> separate MASTER.
  - If the frozen gate or independent review has a blocking failure, preserve
    the evidence and stop:
    `HANDOFF_REQUIRED - WAVE 3 COMPLETE, NO FURTHER REPAIR AUTHORIZED`.
  - If MASTER accepts, stop:
    `PACKAGE B WAVE 3 ACCEPTED - PACKAGING AND NATIVE VALIDATION AUTHORIZATION REQUIRED`.
  - Packaging, publication, installation, native WoW testing, and live
    SavedVariables access are not authorized by this wave.
  - Repair counters are now 3 used / maximum 3 / remaining 0. Evidence-only
    corrections remain 1 used / maximum 1 / remaining 0.
