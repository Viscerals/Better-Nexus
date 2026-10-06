# Features & commands

Better Nexus continues the Nexus addon for **Project Ebonhold / WoW 3.3.5a**. The project name has changed; the in-game name and `/nexus` commands remain compatible.

## Wishlists and assignments

Create or import a desired plan, track exact qualities and copies, and assign it to the intended build. The beta includes draft-preserving save refusals and safeguards against an incorrect save destination.

## Rolling and automation

Review Take, Freeze, Banish, and Reroll decisions against the remaining Wishlist needs. Individual permissions remain separate from the master Automation switch. The experimental adaptive strategy is the public beta default; the previous strategy remains available.

“Auto ON” is permission to act, not evidence that all prerequisites are ready. Stop and capture evidence when an action stays uncertain or the addon behaves unexpectedly.

## Build Library and recorded DPS

Browse shared builds and recorded results. DPS capture uses Details! and supported events. Dummy and Lich King pairing and the “Require both DPS records” filter distinguish eligible records from incomplete entries.

Two recorded results are evidence of those captures, not a guarantee that a build is best for every player. A session-only capture is identified as such when the saved profile is read-only.

## Sharing and Sync

Sharing operates **within the same realm**. Preparing, queued, sent, refused, and completed are different states. A sent request does not prove the other client has received a complete record.

The beta checks owner identity and handles compatible shared records. Older clients may not represent every permanent/locked role. Local removal does not establish that a record was removed from other clients; remote withdrawal remains unavailable in the described protocol.

## Orbs / Lost Memories

Refinement works toward an assigned Wishlist with an explicit maximum budget and Pause, Resume, and Stop controls. Opening the window does not itself spend an Orb. A deliberate Start authorizes the run’s budget and eligible surplus use.

**Manual Continue** is a recovery path for eligible interrupted sessions. It is not automatic recovery, does not refund spent Orbs, and does not repeat uncertain actions. Closing the window does not stop an approved run; use the controls.

!!! warning "Experimental limits"
    The published player guide records unresolved native capability and real-resource verification limits. Do not treat an offline test pass as permission or proof that Orb spending is safe in your client. Read the exact build’s in-game guidance before using resource-changing actions.

## Loading, Help, and diagnostics

Startup is batched with visible progress. Local tools and shared views have their own readiness requirements. A loading percentage describes a specific step, not an overall ETA.

The read-only Help guide can be reopened. Diagnostic reports include rolling history and details for startup, Sync, Lua errors, and Orb recovery. NexusSupport supports private report files.

## Command reference

| Command | Purpose |
| --- | --- |
| `/nexus` | Show available commands. |
| `/nexus help` | Open the read-only in-game guide. |
| `/nexus editor` | Open the Wishlist editor. |
| `/nexus builds` | Browse Community Builds. |
| `/nexus leaderboard` | Open the DPS Leaderboard. |
| `/nexus status` | Show current build/loadout state. |
| `/nexus panel` | Toggle the main panel. |
| `/nexus loading` | Reopen startup progress. |
| `/nexus sync` | Request shared data. |
| `/nexus orbs` | Open refinement controls; opening does not spend. |
| `/nexus log errors` | View recorded errors. |
| `/nexus perf` | Inspect runtime performance observations, separate from DPS. |
| `/nexus report` | Prepare diagnostics for a support report. |

---

Sources: [public test.9092 release](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9092), [tagged player guide](https://github.com/Viscerals/Better-Nexus/blob/v1.20.0-beta.1-test.9092/README-PROTOTYPE.md), and [tagged README](https://github.com/Viscerals/Better-Nexus/blob/v1.20.0-beta.1-test.9092/README.md).
