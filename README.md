# Better Nexus

Better Nexus is a public, community-maintained continuation of the deprecated
Nexus addon for Project Ebonhold.

The repository begins from the installed Nexus 1.19.3 player build. The in-game
addon name, folder name, slash commands, and SavedVariables remain `Nexus` for
compatibility with existing installations and user data.

## Project status

- Stable production release: Nexus 1.19.5.
- Experimental public prereleases are available through
  [GitHub Releases](https://github.com/Viscerals/Better-Nexus/releases). These
  builds are for testing and are not stable releases.
- Client target: World of Warcraft 3.3.5a / Project Ebonhold.
- Language target: Lua 5.1.
- Current TOC maintainer metadata identifies Valentine. Original upstream author attribution is preserved in `Nexus.toc` and [UPSTREAM.md](UPSTREAM.md).

## What it does

Nexus provides Echo build automation, saved-build wishlists, community builds,
DPS records, and Snapshot convergence for Project Ebonhold.

## Requirements

- Project Ebonhold on World of Warcraft 3.3.5a.
- Details! for DPS capture and leaderboard records.

## License, policy, and AI use

- Better Nexus is source-available, not open source.
- Personal gameplay use follows [LICENSE.md](LICENSE.md).
- Provenance and redistribution boundaries are documented in [UPSTREAM.md](UPSTREAM.md).
- AI-assisted development rules are documented in [AI_POLICY.md](AI_POLICY.md).
- Release safety and archive controls are documented in [RELEASE_SECURITY.md](RELEASE_SECURITY.md).
- Security and suspected compromises are documented in [SECURITY.md](SECURITY.md).

## Installation

1. Keep the runtime addon folder named `Nexus`.
2. Place it under `Interface\\AddOns`.
3. Confirm `Interface\\AddOns\\Nexus\\Nexus.toc` exists.
4. Start the game or use `/reload`.

Do not rename the installed addon folder to `Better-Nexus`; the repository name
is different from the runtime addon identity by design.

Back up `NexusDB` and `WishlistRealizerDB` before testing a prerelease. Better
Nexus preserves compatibility with these SavedVariables because existing user
data must survive upgrades and rollback testing.

## Reporting problems

Use the [structured issue forms](https://github.com/Viscerals/Better-Nexus/issues/new/choose) to report a bug, performance or stutter problem, or multiplayer Sync problem. Include the exact prerelease build and the diagnostics requested by the selected form.

## Commands

- `/nexus` — show commands
- `/nexus builds` — open Community Builds
- `/nexus leaderboard` — open the DPS Leaderboard
- `/nexus editor` — open the Wishlist Editor
- `/nexus sync` — request builds and records
- `/nexus dps` — show DPS capture status
- `/nexus auto` — toggle automation
- `/nexus panel` — toggle the HUD
- `/nexus overlay` — toggle the wishlist overlay
- `/nexus log` — open the diagnostic log
- `/nexus log errors` — open the newest 20 structured errors
- `/nexus perf` — open bounded performance aggregates for this session
- `/nexus err` — print the newest retained error
- `/nexus status` — show current build and loadout state

## Development rules

- Preserve Lua 5.1 and WoW 3.3.5a compatibility.
- Preserve `NexusDB` and `WishlistRealizerDB` migrations and user data.
- Keep policy decisions deterministic and data-driven.
- Do not include tests, backups, local logs, or development artifacts in player release archives.
- Include `LICENSE.md`, `AI_POLICY.md`, and `UPSTREAM.md` beside `Nexus.toc` in every player release archive, without adding those Markdown files to the TOC.
- Validate changes offline and in game before claiming a live issue fixed.
- Update notices come only from versions on already accepted Nexus Sync traffic. Nexus never downloads or installs updates; the notice exposes the stable releases page for manual use.

The release build catalog is generated, not hand-edited. Run
`node tools/export-bundled-builds.js --help` for the local export command. The
exporter parses SavedVariables as data, includes only complete shareable builds,
and writes deterministic catalog metadata plus an exclusion report.
`node tools/analyze-savedvariables.js --input <Nexus.lua>` uses the same literal
parser in read-only mode and prints aggregate compaction metrics without
evaluating Lua, exposing record contents, or writing the input.

Bootstrap the repository's pinned development-only validation dependencies from
tracked files, then run the local offline gate from PowerShell:

```powershell
./tools/Bootstrap-QualityTools.ps1
node tools/parse-lua51.js . --tests
node tools/check-lua51-upvalues.js . --toc Nexus.toc
Get-ChildItem -LiteralPath tests -Filter 'run_*.lua' | Sort-Object Name | ForEach-Object { node tools/run-lua.js $_.FullName; if ($LASTEXITCODE -ne 0) { throw "failed: $($_.Name)" } }
node tests/run-bundled-build-export.js
node tests/run-savedvariables-analyzer.js
git diff --check
```

The bootstrap requires Node.js 20 or newer with npm and runs `npm ci` against
the exact tracked lockfile. It then downloads the exact Gitleaks, actionlint,
zizmor, and PSScriptAnalyzer assets in `tools/security-tools.json`, verifies
their SHA-256 values before extraction, and installs the pinned pre-commit
runner under ignored `.tools` state. `node_modules`, downloaded tools, and hook
environments remain ignored development state.

After bootstrap, use one quality-gate entry point:

```powershell
./tools/Invoke-QualityGate.ps1 -Mode Fast
./tools/Invoke-QualityGate.ps1 -Mode Full
./tools/Invoke-QualityGate.ps1 -Mode Package
./tools/Invoke-QualityGate.ps1 -Mode Security
```

`Fast` maps changed paths through `tests/validation-map.json`; `Full` runs the
complete offline matrix; `Package` verifies a temporary logical `Nexus` package
manifest without retaining an archive; and `Security` owns artifact, secret,
workflow, Lua, and PowerShell policy. Results are written under ignored
`build/verify/`: compact `summary.json` and `summary.md` files plus detailed
per-check logs. Successful logs are not copied into the summary.

The Security profile blocks staged/local artifacts, secrets, private keys,
workflow syntax errors, high-severity workflow security findings, PowerShell
parse/security findings, and warnings beyond the explicit initial advisory
baseline. LuaLS and Luacheck target Lua 5.1, while StyLua is check-only; those
three are advisory and are reported as unavailable when not installed rather
than being counted as passes. Pre-commit runs artifact, secret, filename,
conflict, whitespace, and check-only line-ending checks at commit time, with
Fast reserved for pre-push or explicit use. Three inherited mixed-ending files
are recorded narrowly in `tests/security-advisory-baseline.json` and are not
rewritten by this infrastructure stage.

VibeRun remains the project workflow owner. Its implementation role runs
expected-red and focused checks followed by `Fast`, then stops after one clean
commit. Its independent review role runs `Full` once at the committed candidate,
reads the compact summary, and opens detailed logs only for a failure or a
suspicious result. A hygiene pass does not repeat `Full` when no product or test
byte changed. Consolidation archives receipts without changing product bytes or
inventing a new stage. Normal sessions read `AGENTS.md`, current `STATE`, only
the active `PLAN` checkpoint, and `CONTEXT`; evidence and history reads stay
bounded to the receipt needed for the current decision.

The adjacent upvalue command audits every TOC-loaded function against the WoW 3.3.5a hard limit of 60. It reports a production advisory above 48 to retain a practical 12-upvalue maintenance margin where feasible; the regression fixture keeps every reviewed exception explicit.

These checks do not prove in-game behavior; `/reload` and live Project Ebonhold
verification must still be reported separately.

See [CHANGELOG.md](CHANGELOG.md) for inherited release history and
[UPSTREAM.md](UPSTREAM.md) for provenance and redistribution notes.
