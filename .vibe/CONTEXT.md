# CONTEXT

## Architecture

- WP5 runs on `bugfix/test19-wp5-historical-dps-authority-and-real-paired-summari` from accepted WP4 handoff `e70de8a7582d0146cc6746677084b3f4a270290b`; Stage 48 product/test bytes are frozen.
- Historical DPS capture and locked evidence flow through `core/DpsCapture.lua` and `core/CandidateEvidence.lua`; current/build relation and copy decisions cross `core/CommunityController.lua` and Community/Sync ingress.
- DPS qualification and summary consumers span `core/CommunityController.lua`, `core/CommunityProjection.lua`, `core/DataRetention.lua`, `ui/Leaderboard.lua`, and view/DPS-board runners. WP5 must centralize the real-pair metric.
- WP4 is isolated in `.test19-wp4-worktree` on `bugfix/test19-wp4-exact-wishlist-evidence`, based exactly on frozen WP3 head `e674f033cc51494a382191b987c9a99cb6827f4a`.
- Wishlist draft flow is `core/WishlistModel.lua` -> `core/WishlistController.lua` -> `ui/WishlistEditor.lua` / `ui/WishlistRenderer.lua`; EBH1 transfer passes through `core/Codec.lua`.
- Typed record evidence is owned by `core/CandidateEvidence.lua`; live active/locked reads and Wishlist association are behind `core/GameAdapter.lua` and `core/LoadoutEvidence.lua`.
- Progress and automation decisions flow through `logic/Model.lua` -> `logic/Policy.lua` -> `logic/Ratchet.lua` -> GameAdapter; `ui/WishlistOverlay.lua` must consume the same exact progress authority.
- Runtime targets WoW 3.3.5a and Lua 5.1. `tools/Invoke-QualityGate.ps1` owns Fast/Full/Package/Security validation.

## Key Decisions (2026-08-21)

- WP5 decision (2026-08-22): capture-time Dummy/LK locked snapshots are immutable history; exact independently proven current/build association alone grants copy authority.
- WP5 decision (2026-08-22): a paired Average requires verified canonical owner, ordinary fingerprint, and locked full-combat identity equality; independent category bests remain available without a pair.
- WP5 decision (2026-08-22): category, timestamp, recency, title, short name, and resemblance are never authority or tie-break inputs; one deterministic real-pair metric feeds Community, Leaderboard, retention, and sorting.
- Execute WP4 in order: #43 exact ordinary draft identity -> #44 counted locked evidence -> #20 read-time role derivation -> #35 exact progress.
- Trustworthy exact `spellId` owns ordinary draft rows. Family is display/search grouping only; compatibility rows need deterministic collision-safe fallback identity.
- Locked validation uses total copies `sum(stacks) <= 6`, preserving exact tier, count, provenance, and unknown fields; ordinary and locked limits remain separate.
- #20 derives `exact active total - authoritative exact locked counts = exact ordinary counts` without rewriting active, Snapshot, Designed, or historical evidence. Partial, stale, ambiguous, or underflow inputs fail closed.
- #35 must share one exact-tier progress boundary across model, policy/ratchet, editor, HUD, and overlay; family possession never satisfies a sibling tier.
- Freeze product/test/workflow bytes, complete independent Spec/Standards/adversarial review, then run one final Full. Any governed-byte repair after Full requires another Full.

## Gotchas

- Existing average semantics occur in `CommunityController`, `DataRetention`, and view projection paths; changing only the visible Leaderboard leaves qualification, retention, or sorting inconsistent.
- WP5 must not globally change the ordinary fingerprint; pair identity adds verified owner and locked/full-combat equality at the DPS boundary.
- Preserve original historical tables and nested locked rows across missing/conflicting authority, reload, restart, and Sync. Unavailable copy authority must not mark an uncertain Echo locked.
- Root and `.lag-hotfix-worktree` contain unrelated user changes. Earlier WP2/WP3 worktrees are frozen and must not be edited, rebased, cleaned, stashed, or deleted.
- Vibe flags and routing are dispatcher-owned. The Stage 48 maintenance scan/review/hygiene is complete and deliberately left product checkpoint 48.1 `NOT_STARTED`.
- Current draft code repeatedly uses `family` as the map/action handle; change the handle explicitly before switching ordinary identity so sibling actions cannot alias.
- CandidateEvidence currently limits locked row count and rejects duplicate spell identities; WP4 must validate counted copies and preserve legitimate exact counted evidence instead.
- GameAdapter locked reads already produce `bySpell` counts. Do not infer count one from row presence or derive roles from title, short hash/name, family, slot proximity, or approximate similarity.
- LuaLS, Luacheck, and StyLua may remain advisory-unavailable and must not be reported as passes. Offline checks do not prove native WoW behavior.

## Hot Files

- WP5 #23: `core/CandidateEvidence.lua`, `core/DpsCapture.lua`, `core/CommunityController.lua`, `core/CommunityProjection.lua`, Sync relation paths, `tests/run_locked_evidence_resolver.lua`, and `tests/run_stage32_leaderboard_locked_fidelity.lua`.
- WP5 #26: the shared DPS projection owner, `core/CommunityController.lua`, `core/DataRetention.lua`, `ui/Leaderboard.lua`, `tests/run_dps_boards.lua`, `tests/run_view_projections.lua`, and `tests/run_leaderboard_ui.lua`.
- #43: `core/WishlistModel.lua`, `core/WishlistController.lua`, `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua`, `core/Codec.lua`, and Wishlist model/editor/controller/import tests.
- #44: `core/CandidateEvidence.lua`, `core/WishlistModel.lua`, `core/GameAdapter.lua`, `core/LoadoutEvidence.lua`, and CandidateEvidence/locked-loadout tests.
- #20: `core/GameAdapter.lua`, `core/LoadoutEvidence.lua`, association fixtures, and exact active/locked evidence tests.
- #35: `logic/Model.lua`, `logic/Policy.lua`, `logic/Ratchet.lua`, `core/MainViewModel.lua`, `ui/WishlistOverlay.lua`, and Wishlist progress/parity tests.
- Workflow: `AGENTS.md`, `.vibe/STATE.md`, `.vibe/PLAN.md`, this file, and append-only `.vibe/EVIDENCE.md`.

## Agent Notes

- Current state: Stage 49 checkpoint 49.1 `NOT_STARTED`; design, retrospective, maintenance test-gap analysis, and context capture are complete. No WP5 product/test byte exists yet.
- Next action: use Caveman `observe -> isolate -> hypothesize -> expected red`; add public issue #23 tests for conflicting historical snapshots and later exact current/build authority before editing product code.
- After 49.1 review/hygiene advances the pointer, implement 49.2 with one deterministic pair selector and cross-surface Community/Leaderboard/sort parity coverage.
- Preserve the 79 ordinary-copy budget and the existing policy that overflow does not automatically become locked intent unless current trusted rules authorize it.
- No push, PR/issue mutation, merge, package/install, live SavedVariables access, native WoW, history rewrite, earlier-worktree mutation, or WP5 work is authorized.

## Stage Retrospective Notes

- Build the complete compatibility-positive inventory before freezing an authority migration; late Full-only fixture discovery is avoidable.
- Define one typed authority verdict and cross-surface alias matrix before updating ingress, summary, projection, and export callers.
- Expected-red preservation matrices must include collisions, malformed values, future-owned data, and restart/reload ordering.
- Public quarantine rules require sync/async/detail/fallback/count/sort/page parity.
- Reserve Full until all independent review axes accept the exact frozen bytes.
- Stage 48.1 needed repeated review repairs for catalog admission and defensive-copy drift; for Stage 49, define one public DPS authority verdict and make every projection consume it before widening callers.
- Stage 48.2 exposed copy-count and bound-snapshot edge cases after the first implementation; issue #23 tests must cover immutable nested aliases, conflicting provenance, future fields, and copy totals before product edits.
- Stage 48.3 succeeded with a narrow read-only derivation boundary; keep current/build copy resolution read-only over historical DPS rows and prove source immutability at every failure path.
- Stage 48.4 found presentation and automation parity gaps across repeated review cycles; issue #26 must test Community, Leaderboard, sorting, and detail projections against the same paired-summary output from the start.
- Stage 48 added no checkpoints but accumulated multiple implementation→review cycles; freeze Full only after focused adversarial matrices cover malformed identity, order changes, reload/restart, and Sync convergence.
