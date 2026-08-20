# Better-Nexus agent instructions

VibeRun is the sole workflow dispatcher, state owner, and roadmap owner. Repository scripts are deterministic validation workers beneath it; do not create another dispatcher, state namespace, prompt catalog, skill, or project tracker.

## Hot-context read order

1. Read `AGENTS.md`.
2. Read `.vibe/STATE.md`.
3. Read only the active checkpoint section in `.vibe/PLAN.md`.
4. Read `.vibe/CONTEXT.md`.

Search `.vibe/EVIDENCE.md` by the current checkpoint, read a bounded tail, or open an exact referenced receipt. Do not load the whole file by default. Read `.vibe/HISTORY.md` only when historical reconciliation is necessary.

## Dispatcher-owned roles

Follow the role selected by the installed VibeRun dispatcher and use only its supported state schema and installed prompts.

- Implementation: start with Caveman `observe -> isolate -> hypothesize -> expected red`; run focused mapped tests and `tools/Invoke-QualityGate.ps1 -Mode Fast`; create one coherent clean commit; set `IN_REVIEW`; stop for review.
- Review: work from the committed candidate; run `tools/Invoke-QualityGate.ps1 -Mode Full` exactly once; inspect `build/verify/summary.json`; open only failing or suspicious logs; route directly related repairs back through a new implementation role; do not paste successful logs into hot context or PR comments.
- Hygiene: inspect only the reviewed checkpoint surface. When no product or test byte changed, run artifact, diff, and hygiene checks without repeating Full. Prefer a clean result over churn.
- Consolidation: preserve exact receipts in append-only `EVIDENCE.md`, archive completed detail in non-authoritative `HISTORY.md`, retain the current stage/checkpoint pointer and one executable chain, and never change product bytes or invent a stage.

## Repository safety

- Inspect Git evidence and status before editing or committing; preserve unrelated work.
- A skipped, advisory, unavailable, or failing check is never a pass.
- Preserve Lua 5.1, WoW 3.3.5a, `Nexus.toc`, version, protocol, author, SavedVariables, bundled data, runtime tests, and historical artifacts unless the active scope explicitly authorizes them.
- Do not publish `.vibe` runtime caches, prompt transcripts, generated logs, dependency caches, `.ai/**`, `.codex/**`, or `.chatgpt/**`.
- Never push a protected/default branch, force-push, merge, rewrite history, release, install, or perform live-game work without explicit authorization.
- Record concise checkpoint outcomes in `.vibe/EVIDENCE.md`; keep unknown product and architecture requirements explicit.

Detected toolchains: JavaScript and Lua addon metadata. Language target: Lua 5.1.
