# Release highlights

This page summarizes published changes in original wording. The versioned GitHub release is the full record.

## Public test.9094

**1.20.0-beta.1 · needs testing · 9 October 2026**

- **Automatic pick recovery:** Track an unresolved pick and make bounded read-only rechecks when Auto is on and other pauses allow it. Automation can resume once the exact tracked grant is proven, without resending the pick.
- **Travel and final rolls:** Preserve unresolved picks across loading screens; clear stale waiting guidance after a proven final level 80 pick.
- **Status and reporting:** Show waiting, rechecking and pauses clearly; preserve useful bounded recovery reasons in `/nexus report`.

Native behavior is unverified. Recovery is not guaranteed, and the separate Orb server-data readiness wait is not claimed fixed.

[Full test.9094 notes](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9094)

## Public test.9093

**1.20.0-beta.1 · 8 October 2026 · EXPERIMENTAL PRERELEASE**

- **Wishlist progress and data:** Refresh after loadout swaps; preserve authored descriptions and links; retain explicit selected design identity; refuse over-limit locked-target Copy and Save before accepting them.
- **Locked Echo evidence:** Distinguish record slots from copies held in stacks, use observed capacity conservatively, and preserve validated locked Saved Build mirrors.
- **Orbs:** Improve readiness refusal diagnostics and assigned-Wishlist guidance; describe spending as client-observed rather than server-confirmed; handle bounded native-error feedback.
- **DPS and sharing:** Restore supported historical DPS into the served authority payload and improve current-class capture/import while preserving evidence guards.
- **Interface:** Repair leaderboard selection/tooltips/menu states, link drafts, log paging, Wishlist menu cleanup, name markers, Saved Build labels and HUD hide ownership. Use validated client Intensity constants, Journal fallback and declared slot ranges; display low integer DPS.

!!! warning "Native validation remains open"
    The hosted and retained offline checks use simulated services. The reported live Orb server-data wait is not proven resolved, and actual client/server legality, spending, native UI timing and peer/error delivery remain unverified. Preserve your saved data; no wipe is required.

[Full test.9093 notes →](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9093)

## Public test.9092

**1.20.0-beta.1 · 5 October 2026**

- **Freeze recovery:** A refused Freeze action no longer leaves the board stalled; the existing loop breaker still applies.
- **DPS-to-build matching:** A bounded exact-fingerprint index replaces a whole-catalog copy walk. Incomplete or refused queries remain visible rather than being reported as “no match.”
- **Removal-marker reads:** Independent readers stop scans from interfering with one another. Refused Sync scans use bounded restarts, and reloaded exact markers retain their evidence classification.
- **Capture status:** Read-only saved profiles identify DPS captures that exist only for the current session.
- **Less repeated work:** Removes unused scans, redundant copies, and no-op reads. Auto-lock setters return success consistently.

!!! info "What the validation establishes"
    The public notes report successful offline validation and reduced synthetic work in the exercised paths. They do not establish that gameplay hitching is fixed in a live frame experiment. Deferred native checks and hypotheses remain open.

[Full test.9092 notes →](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9092)

## Earlier public beta improvements

The test.9092 release also records earlier changes:

- **test.9088:** Reserved Wishlist footer space with two lines of counts and a scrollable selection list above Save.
- **test.9089:** Same-realm DPS owner authority, deliberate full-build requests, clearer completion states, independent catalog cursors, and interface/layout improvements.
- **Across the 1.20 beta:** Exact Wishlist targets, the experimental adaptive rolling strategy, batched startup, shared builds and DPS handling, in-game Help, Orb budget/recovery controls, and `/nexus report` with NexusSupport.

These are cumulative published highlights, not a promise that every native edge case is resolved.

## Full history

- [All published releases](https://github.com/Viscerals/Better-Nexus/releases)
- [Inherited changelog in the source repository](https://github.com/Viscerals/Better-Nexus/blob/main/CHANGELOG.md)
- [Download test.9094](index.md)

The historical changelog and development source can differ from the current package. Use the release tag and package identity for a precise report.
