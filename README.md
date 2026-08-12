# Better Nexus

Better Nexus is a community-maintained continuation of the deprecated
Nexus addon for Project Ebonhold.

The repository begins from the installed Nexus 1.19.3 player build. The in-game
addon name, folder name, slash commands, and SavedVariables remain `Nexus` for
compatibility with existing installations and user data.

## Project status

- Repository visibility: public.
- Current stable release: Nexus 1.19.5.
- Current test release: Nexus 1.20 Beta (`1.20.0-beta.4`).
- Client target: World of Warcraft 3.3.5a / Project Ebonhold.
- Language target: Lua 5.1.
- Upstream author attribution is preserved in `Nexus.toc` and
  [UPSTREAM.md](UPSTREAM.md).

## What it does

Nexus provides Echo build automation, saved-build wishlists, community builds,
DPS records, and Snapshot convergence for Project Ebonhold.

## Requirements

- Project Ebonhold on World of Warcraft 3.3.5a.
- Details! for DPS capture and leaderboard records.

## Installation

1. Keep the runtime addon folder named `Nexus`.
2. Place it under `Interface\AddOns`.
3. Confirm `Interface\AddOns\Nexus\Nexus.toc` exists.
4. Start the game or use `/reload`.

Do not rename the installed addon folder to `Better-Nexus`; the repository name
is different from the runtime addon identity by design.

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
- Do not include tests, backups, local logs, or development artifacts in player
  release archives.
- Validate changes offline and in game before claiming a live issue fixed.
- Update notices come only from versions on already accepted Nexus Sync traffic.
  Nexus never downloads or installs updates; the notice exposes the stable
  releases page for manual use.

The release build catalog is generated, not hand-edited. Run
`node tools/export-bundled-builds.js --help` for the local export command. The
exporter parses SavedVariables as data, includes only complete shareable builds,
and writes deterministic catalog metadata plus an exclusion report.
`node tools/analyze-savedvariables.js --input <Nexus.lua>` uses the same literal
parser in read-only mode and prints aggregate compaction metrics without
evaluating Lua, exposing record contents, or writing the input.

For the repository's local offline gate, run these commands from PowerShell:

```powershell
node .tools/fengari/parse-lua51.js . --tests
Get-ChildItem -LiteralPath tests -Filter 'run_*.lua' | Sort-Object Name | ForEach-Object { node .tools/fengari/run-lua.js $_.FullName; if ($LASTEXITCODE -ne 0) { throw "failed: $($_.Name)" } }
node tests/run-bundled-build-export.js
node tests/run-savedvariables-analyzer.js
git diff --check
```

These checks do not prove in-game behavior; `/reload` and live Project Ebonhold
verification must still be reported separately.

See [CHANGELOG.md](CHANGELOG.md) for inherited release history and
[UPSTREAM.md](UPSTREAM.md) for provenance and redistribution notes.
