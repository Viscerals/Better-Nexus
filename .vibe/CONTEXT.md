# CONTEXT

## Architecture

- WP4 is isolated in `.test19-wp4-worktree` on `bugfix/test19-wp4-exact-wishlist-evidence`, based exactly on frozen WP3 head `e674f033cc51494a382191b987c9a99cb6827f4a`.
- Wishlist draft flow is `core/WishlistModel.lua` -> `core/WishlistController.lua` -> `ui/WishlistEditor.lua` / `ui/WishlistRenderer.lua`; EBH1 transfer passes through `core/Codec.lua`.
- Typed record evidence is owned by `core/CandidateEvidence.lua`; live active/locked reads and Wishlist association are behind `core/GameAdapter.lua` and `core/LoadoutEvidence.lua`.
- Progress and automation decisions flow through `logic/Model.lua` -> `logic/Policy.lua` -> `logic/Ratchet.lua` -> GameAdapter; `ui/WishlistOverlay.lua` must consume the same exact progress authority.
- Runtime targets WoW 3.3.5a and Lua 5.1. `tools/Invoke-QualityGate.ps1` owns Fast/Full/Package/Security validation.

## Key Decisions (2026-08-21)

- Execute WP4 in order: #43 exact ordinary draft identity -> #44 counted locked evidence -> #20 read-time role derivation -> #35 exact progress.
- Trustworthy exact `spellId` owns ordinary draft rows. Family is display/search grouping only; compatibility rows need deterministic collision-safe fallback identity.
- Locked validation uses total copies `sum(stacks) <= 6`, preserving exact tier, count, provenance, and unknown fields; ordinary and locked limits remain separate.
- #20 derives `exact active total - authoritative exact locked counts = exact ordinary counts` without rewriting active, Snapshot, Designed, or historical evidence. Partial, stale, ambiguous, or underflow inputs fail closed.
- #35 must share one exact-tier progress boundary across model, policy/ratchet, editor, HUD, and overlay; family possession never satisfies a sibling tier.
- Freeze product/test/workflow bytes, complete independent Spec/Standards/adversarial review, then run one final Full. Any governed-byte repair after Full requires another Full.

## Gotchas

- Root and `.lag-hotfix-worktree` contain unrelated user changes. Earlier WP2/WP3 worktrees are frozen and must not be edited, rebased, cleaned, stashed, or deleted.
- Vibe flags and routing are dispatcher-owned. The Stage 48 maintenance scan/review/hygiene is complete and deliberately left product checkpoint 48.1 `NOT_STARTED`.
- Current draft code repeatedly uses `family` as the map/action handle; change the handle explicitly before switching ordinary identity so sibling actions cannot alias.
- CandidateEvidence currently limits locked row count and rejects duplicate spell identities; WP4 must validate counted copies and preserve legitimate exact counted evidence instead.
- GameAdapter locked reads already produce `bySpell` counts. Do not infer count one from row presence or derive roles from title, short hash/name, family, slot proximity, or approximate similarity.
- LuaLS, Luacheck, and StyLua may remain advisory-unavailable and must not be reported as passes. Offline checks do not prove native WoW behavior.

## Hot Files

- #43: `core/WishlistModel.lua`, `core/WishlistController.lua`, `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua`, `core/Codec.lua`, and Wishlist model/editor/controller/import tests.
- #44: `core/CandidateEvidence.lua`, `core/WishlistModel.lua`, `core/GameAdapter.lua`, `core/LoadoutEvidence.lua`, and CandidateEvidence/locked-loadout tests.
- #20: `core/GameAdapter.lua`, `core/LoadoutEvidence.lua`, association fixtures, and exact active/locked evidence tests.
- #35: `logic/Model.lua`, `logic/Policy.lua`, `logic/Ratchet.lua`, `core/MainViewModel.lua`, `ui/WishlistOverlay.lua`, and Wishlist progress/parity tests.
- Workflow: `AGENTS.md`, `.vibe/STATE.md`, `.vibe/PLAN.md`, this file, and append-only `.vibe/EVIDENCE.md`.

## Agent Notes

- Current state: Stage 48 checkpoint 48.1 `NOT_STARTED`; Stage design and scheduled maintenance cycle are complete. No WP4 product/test byte or commit exists yet.
- Next action: apply the selected behavior-preserving explicit `rowKey` precursor, prove existing public Wishlist model/editor equivalence, then add the required public expected-red for same-family sibling tiers.
- Use public seams for TDD: WishlistModel/controller/editor round-trip and actions, CandidateEvidence envelope, GameAdapter Wishlist resolution, and public progress projections. Do not test private helpers directly.
- Preserve the 79 ordinary-copy budget and the existing policy that overflow does not automatically become locked intent unless current trusted rules authorize it.
- No push, PR/issue mutation, merge, package/install, live SavedVariables access, native WoW, history rewrite, earlier-worktree mutation, or WP5 work is authorized.

## Stage Retrospective Notes

- Build the complete compatibility-positive inventory before freezing an authority migration; late Full-only fixture discovery is avoidable.
- Define one typed authority verdict and cross-surface alias matrix before updating ingress, summary, projection, and export callers.
- Expected-red preservation matrices must include collisions, malformed values, future-owned data, and restart/reload ordering.
- Public quarantine rules require sync/async/detail/fallback/count/sort/page parity.
- Reserve Full until all independent review axes accept the exact frozen bytes.
