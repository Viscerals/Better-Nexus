# Better Nexus

Better Nexus is a public, community-maintained continuation of the deprecated
Nexus addon for Project Ebonhold (World of Warcraft 3.3.5a, Lua 5.1).

The in-game addon name, folder name, slash commands, and SavedVariables remain
`Nexus` for compatibility with existing installations and user data.

## Project status

- `main` is the one maintained development line. It holds the current
  experimental 1.20 prototype source. It is **not** a stable release.
- Stable production release: Nexus 1.19.5.
- Current experimental beta download:
  [Public Beta / Test 9027](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9027).
  `main` is newer than that package. Source on `main` is not a published build.
- All prereleases: [GitHub Releases](https://github.com/Viscerals/Better-Nexus/releases).
  Release tags are immutable.
- How `main` was consolidated, and where older branches and pull requests went:
  [docs/REPOSITORY_CONSOLIDATION.md](docs/REPOSITORY_CONSOLIDATION.md).
- Upstream author attribution is preserved in `Nexus.toc`,
  [UPSTREAM.md](UPSTREAM.md) and [THIRD_PARTY.md](THIRD_PARTY.md).

## Known limitations of the current beta

These are tracked in the [issue list](https://github.com/Viscerals/Better-Nexus/issues).
They are open, not fixed:

- Two-account Sync transfer is not proven end to end. One incoming record makes
  the local catalog rebuild its whole root, which can delay all other Sync work.
- Remote withdrawal (Stop Sharing for records that peers already hold) is not
  supported.
- Sharing a build with permanent (locked) Echoes can be refused or can lose the
  permanent roles in test.9027. A correction is in review; it is not on `main`.
- The Nexus Advisor tab placement inside Character Progression is not verified
  in the game client.
- Orb / Lost Memories spending has no approved real-resource test.

The player guide for the prototype is [README-PROTOTYPE.md](README-PROTOTYPE.md).

## Installation (players)

1. Close WoW. Back up `Interface\AddOns\Nexus` and your `WTF` folder.
2. Download a package from Releases and extract it.
3. Keep the runtime addon folder named `Nexus` under `Interface\AddOns`.
4. Confirm `Interface\AddOns\Nexus\Nexus.toc` exists (not `Nexus\Nexus\`).

Do not rename the installed addon folder to `Better-Nexus`. Back up `NexusDB`
and `WishlistRealizerDB` before you test a prerelease.

## Development quick start

Requirements: Git, Python 3.9 or newer, and a `luajit` executable on `PATH`
(LuaJIT 2.1; on Debian/Ubuntu `sudo apt-get install luajit`). No game client,
network access or account data is needed for the offline checks.

```
git clone https://github.com/Viscerals/Better-Nexus.git
cd Better-Nexus
python tools/ci_check.py                      # inventory check + complete offline suite
python tools/ci_check.py --only parse,boot    # a bounded shard (reported as PARTIAL)
python tools/build_package.py --check         # package content and TOC checks
python tools/build_package.py --label test.9999-abcdef0   # writes dist/Nexus-<label>.zip
```

- The test list lives in `tools/run_prototype_tests.py`. A test file that is not
  listed there fails the inventory check. No test count is fixed anywhere.
- Two tests (`planner_reference`, `orbs_policy`) compare against a third-party
  LoadoutPilot archive that this repository may not redistribute. Without it
  they are reported as **NOT RUN**, never as passed. If you hold the exact
  archive named in [THIRD_PARTY.md](THIRD_PARTY.md), extract the two reference
  modules with `python tools/prepare_pilot_reference.py <archive> <dir>` and
  pass `--reference <dir> --require-reference`.
- Without `luajit`, `tools/run_prototype_tests.py --runtime lua54` can run the
  suite on Lua 5.4 with compatibility shims (needs `liblua5.4`). That result is
  labelled as such. It does not replace the LuaJIT run.
- `tools/build_package.py` never publishes. A public release is a separate,
  human-authorized step ([RELEASE_SECURITY.md](RELEASE_SECURITY.md)).
- Offline tests use a synthetic harness. They do not prove behavior in the game
  client. State the native-testing status in every pull request.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow.

## Reporting problems

Use the [structured issue
forms](https://github.com/Viscerals/Better-Nexus/issues/new/choose) to report a
bug, performance or stutter problem, or multiplayer Sync problem. Include the
exact build label and the diagnostics requested by the selected form. Report
vulnerabilities privately ([SECURITY.md](SECURITY.md)).

## Commands

- `/nexus` — show commands
- `/nexus help` — open the read-only guide
- `/nexus builds` — open Community Builds
- `/nexus leaderboard` — open the DPS Leaderboard
- `/nexus editor` — open the Wishlist Editor
- `/nexus sync` — request builds and records
- `/nexus auto` — toggle automation
- `/nexus panel` — toggle the HUD
- `/nexus log` — open the diagnostic log
- `/nexus status` — show current build and loadout state

## Development rules

- Preserve Lua 5.1 and WoW 3.3.5a compatibility.
- Preserve `NexusDB` and `WishlistRealizerDB` migrations and user data.
- Do not include tests, tools, backups, local logs, or development artifacts in
  player release archives.
- Validate changes offline and in game before claiming a live issue fixed.

See [CHANGELOG.md](CHANGELOG.md) for inherited release history and
[UPSTREAM.md](UPSTREAM.md) for provenance and redistribution notes.
