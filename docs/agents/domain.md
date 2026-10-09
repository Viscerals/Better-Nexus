# Domain documentation

## Layout

Better-Nexus uses a single domain context:

- Root `CONTEXT.md`: domain glossary only.
- Root `docs/adr/`: accepted architecture decisions.

Create these lazily: the glossary when the first term is resolved, and an ADR when a meaningful decision needs recording. They are absent at the inspected source pin. This setup configures their location; it does not manufacture a glossary or architecture decision.

The `core/`, `logic/`, `ui/` and `data/` directories are modules of the same addon. `companion/NexusSupport/` is the small support-storage companion in the same package. These paths do not require a `CONTEXT-MAP.md` or separate contexts.

## Consumer rules

- Read `CONTEXT.md` when present before domain-led work. Use its terms in requests, specifications, tests and implementation.
- Read relevant `docs/adr/*.md` before design or changes in that area. Surface conflicts with accepted decisions before proceeding.
- Keep implementation plans, tests, native evidence and release receipts outside the glossary. Reuse existing focused documents; migrate them only within an approved documentation scope.
- Check document status and source pin against current code. `CONTRACTS.md` is a historical 1.19/stack-era reference per `docs/REPOSITORY_CONSOLIDATION.md`; prototype reports may also describe older snapshots.
- Current source and verified tracker evidence take precedence over stale reports or chat summaries. Archived PR #67's `.vibe/**` layout and PowerShell/Node gates are historical and are not the current configuration.

## Native contracts and exports

For changes at the WoW / Ebonhold API or UI boundary, consult the authorized exact versioned client/export reference. The source targets Lua 5.1 and WoW 3.3.5a (client build 12340 / interface 30300); actual Ebonhold API shapes remain build-specific.

The ignored `.native-reference/` convention holds local versioned exports and private contract references when provided. Keep them read-only and local. Cite the export version or manifest/hash plus the relevant symbol/path in local evidence; record any missing or mismatched reference. Preserve provenance under `THIRD_PARTY.md`, `UPSTREAM.md` and `AI_POLICY.md`. Do not copy private or third-party client code into source or packages.

Inspect the relevant adapter and current behavior before changing an API assumption. Synthetic harnesses characterize offline behavior; API presence and offline passes do not prove native compatibility, UI behavior, frame timing, server responses or resource-spending safety.

For diagnostic export/copy work, retain the complete byte and decoder contract and consult issue #25's native EditBox/clipboard characterization criteria. A refusal notice or synthetic copy check does not prove exact native clipboard bytes. Any representation change needs its own evidence and inverse/parser contract.

Keep the active task's source pin, review, complete-inventory, package, native tester and delivery gates. Publishing or live-game actions require their existing authorization under `CONTRIBUTING.md` and `RELEASE_SECURITY.md`.
