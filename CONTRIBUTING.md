# Contributing to Better Nexus

Better Nexus is in public prerelease stabilization. Keep contributions focused, evidence-based, and compatible with the existing addon and player data.

## Compatibility

- Target Lua 5.1.
- Target World of Warcraft 3.3.5a on Project Ebonhold.
- Preserve the runtime addon name and folder name `Nexus`.
- Preserve `NexusDB` and `WishlistRealizerDB`, including migration behavior, unknown fields, and rollback safety.

## Before opening a pull request

1. Find or open the issue, and say in it that you are working on it. Link the issue in the pull request with `Refs #<number>`. Use a closing keyword only when the pull request verifiably fixes that issue.
2. Create a short-lived branch from the current `main` branch (for example `fix/<issue>-<topic>`). `main` is the only maintained development line. Older stacked branches and pull requests are history; see `docs/REPOSITORY_CONSOLIDATION.md`.
3. Keep the change narrowly scoped. Separate unrelated product, policy, and infrastructure work.
4. Run `python tools/ci_check.py` (needs Python 3.9+ and `luajit`) and, for packaging or TOC changes, `python tools/build_package.py --check`. The README lists prerequisites and the two reference-dependent tests that are reported as NOT RUN without a third-party archive. A new test file must be added to `tools/run_prototype_tests.py`, or the inventory check fails.
5. Open one focused pull request against `main`. Release tags are immutable; do not move or reuse them.
6. Record what was tested offline and what was tested in the native game client. Do not claim live behavior from offline checks.
7. Review the final diff for unrelated files, generated output, secrets, private data, and provenance concerns.

Do not include:

- AI chat transcripts, prompts, scratch notes, or transient automation artifacts;
- release packages or locally built archives;
- SavedVariables, account or character data, private diagnostics, or logs;
- editor, backup, cache, or temporary files.

Do not force-push, rebase, or otherwise rewrite a head that is already under exact-SHA review or native testing. Open a successor commit or coordinate with the maintainer when reviewed history must be preserved.

## Reports and requests

- Use the repository's GitHub Issue Forms for bugs, performance or stutter reports, and Sync or multiplayer reports.
- Feature requests are deferred while public prerelease stabilization is active.
- Report vulnerabilities through [private vulnerability reporting](https://github.com/Viscerals/Better-Nexus/security/advisories/new), not a public issue.

## Pull-request evidence

Every pull request should state:

- the problem and proposed change;
- the exact paths and behavior in scope;
- focused validation results;
- regression and migration risks;
- native testing status and any unproven boundary;
- confirmation that unrelated changes are excluded.

Maintainers may ask for a smaller PR or additional evidence when review, provenance, compatibility, or player-data safety is unclear.
