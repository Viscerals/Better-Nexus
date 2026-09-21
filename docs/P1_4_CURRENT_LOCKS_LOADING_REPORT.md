# Nexus P1.4 — current-lock default and nonblocking loading UI

## Task and supplied baseline

The user reported that the P1.3 role-choice panel could not be clicked, authorized
using matching current permanent locks by default, and requested visible progress
with local Wishlist/Echo use available during Community data preparation.

This package derives from the exact supplied P1.3 source archive:

- Declared original source commit: `ff14272496cef387543b29890496a747a05a63c2`.
- Source archive SHA-256: `916f4cb8fe57785e351cca6117559ad3059adc19a59ce43ca3d38212880f3edb`.
- Source archive bytes: 760,220.
- Imported tree: `769ca5afc795346f4b63d187de49832ee551122d`.
- Imported local parent commit: `baead47068fe969a2c7e1430e8544162f0f231d8`.
- Original P1.3 runtime ZIP SHA-256: `00fcbbbe3437b47e25be1ed44dc8f86da4f998ea4b4250f9b1ecb863978cb92b`.

The local Git parent imports those source bytes. It is not the original worker's
Git history. Final source commit/tree and runtime checksum are recorded alongside
the delivered package. Original archives were not edited.

## 1. Default to matching current permanent locks

Opening, assigning, or importing an unresolved 80–85-copy Wishlist now attempts
a detached local role resolution from synchronized current permanent locks.
Matching is by exact ID, quality, and copy count, never display order. It proceeds
without the chooser only if the complete contents produce a valid split of no
more than 79 ordinary and six locked copies. It does not require the desired
ordinary build to match the equipped ordinary build.

Existing server/explicit roles and earlier stored local choices take precedence.
No existing desired plan is silently rewritten when permanent ownership changes.

The choice has `current-locks` local-plan provenance. It is not a grant of
ownership, server lock operation, auto switch, or permission to spend resources.
Opening an existing plan preserves its contents and records only the local role
choice; assignment and server upload still follow their respective user actions.
Raw import remains a draft until the normal Save/Create operation.

Role choices remain bounded, character-local, keyed by full normalized content,
and checked against the actual selected source before acceptance. Save/reload,
server reorder, and rename preserve the correct choice. A stale or unavailable
selected server source is not guessed or replaced.

If matching current locks are missing, unavailable, wrong-quality, or insufficient
for a valid split, all source entries stay intact and the manual fallback remains
available. No entry is silently dropped to make the count fit.

`/nexus currentlocks off` selects manual choice for future unresolved plans;
`/nexus currentlocks on` restores the new default. Neither changes existing
confirmed roles or the master automation switch.

## 2. Clickable fallback layout

The fallback frame now occupies its visible 610x510 panel rather than the entire
screen. It uses FULLSCREEN_DIALOG strata, explicit frame levels for rows/buttons,
mouse-enabled controls, and an opaque background. Competing editor/dropdown
surfaces are hidden while it is open; cancellation restores the previous editor.

Offline tests invoke actual +/-/paging/cancel handlers and inspect the relevant
frame structure. They do not simulate WoW's complete hit-testing/compositor.
The screenshot's exact native input interception was not independently reproduced
in WoW here. Native confirmation of actual clicks is still required.

## 3. Loading status and feature availability

`ui/LoadingStatus.lua` provides a small movable/dismissible panel, throttled to
four refreshes per second, with actual phase, completed work, local readiness,
and elapsed time. `/nexus loading` opens it even before local initialization.
No repeated progress lines are printed into chat.

The current Community operation exposes only bounded scalar progress: phase,
records seen, and completed/total items where an existing finite list is known.
A displayed percentage is explicitly a CURRENT-PHASE percentage. Validation,
scanning, or commit phases without a reliable denominator show work/stage text,
not an invented total percent or ETA. Overall ready state appears only after the
real lifecycle reports readiness; the panel then hides after three seconds.

The main and Wishlist navigation show gray Builds/Leaderboard labels while
shared data is pending. Clicking one opens a guarded Loading placeholder rather
than incomplete shared views. A local-Wishlist button remains available after
real local readiness. Leaving the placeholder cancels its delayed auto-opening.

P1.2 already separated local and shared startup; this patch retains that behavior
and makes it visible. Local Wishlist editing and the actual rolling path can
operate while Community preparation waits, after their own local Store/ownership
prerequisites are met. It does not enable Auto, fabricate owned data, or waive
board/resource validation. Shared Sync/DPS initialization retains its existing
readiness gate; this patch does not claim those services are usable early.

No pumping or authority writes occur in the progress display. Presentation errors
are registered with the existing lifecycle isolation mechanism. Existing startup
and manual-Sync work/time limits are unchanged. A shared-data failure is reported
and leaves already-ready local tools available; unsafe local validation still
blocks local actions.

## 4. Code preservation

The following remain byte-identical to supplied P1.3: Store and BuildCatalog,
LoadoutEvidence and CandidateEvidence, hash and transport owners, the
LoadoutPilot-derived planner/policy, the rolling executor, and all remaining
runtime files not named by the final source diff. P1.2's evidence-bootstrap and
scheduling fixes are retained. MainLifecycle changes expose progress, register
and update the UI; they do not change its pump budget or readiness rules.

No SavedVariables, WTF, installed client, GitHub repository, or T3 worktree was
accessed or changed by this build. The supplied reference ZIP is read only for
the existing planner comparison, not bundled as a second addon.

## 5. Verification

Runtime: Lua 5.4 through the installed system library and existing prototype
compatibility shims. Native LuaJIT, plain Lua 5.1, and WoW were unavailable.
An attempted local Lupa installation failed at DNS and installed nothing. No
native-runtime result is inferred from the fallback interpreter.

All 29 prototype-specific scripts pass against the completed source. The exact
installable archive is separately extracted and subjected to the same tests;
its authoritative pass counts and runtime hashes are in the delivered reports.
This is not the original upstream 245-test inventory or a hosted CI campaign.

New scripts:

| Script | Coverage |
|---|---|
| current_locks | 37 named checks: real editor/adapter open, 79+6 split, current-lock provenance, unchanged ownership, assignment, save/reopen/import, insufficient-match refusal, bounded fallback structure and controls, manual opt-out |
| current_locks_exact | 12 named checks: the supplied complete 250-mio EBH1 input, the user's six permanent IDs in their physical order, different equipped ordinary build, direct opening/assignment and raw import |
| current_locks_reload | Real local-role persistence, serialization and fresh module reload, server rename/reorder, no dependency on later owned-lock changes, unavailable-evidence fallback |
| loading_status | 28 named checks: pre-ready status command, true local readiness, measured phase percentage, no fabricated denominator, gray/shared guards, UI cancellation, no status-driven pumping/chat spam, actual final readiness |
| loading_local | Actual Wishlist and LoadoutPilot recommendation-to-Freeze synthetic path with Community held pending, no shared send/initialization, pending-action protection, shared-failure display |

The exact 250-mio fixture has 85 input entries and the six permanent targets
200690, 200756, 200882, 201250, 201262, and 201270. This verifies the user's provided
input shape; it is not a live test of their installed database.

All prior 24 scripts pass, including the 10,000-case LoadoutPilot comparison,
P1.1's 96-assertion evidence regression, existing save/ownership/transport tests,
and eight P1.2 startup tests. Four prior manual-role scripts explicitly set
`useCurrentLocksForUntagged=false` so they continue testing the supported manual
mode; their original assertions are retained. New default-mode tests separately
cover the changed product behavior.

Expected-red controls against the unchanged supplied P1.3 source:

- Matching-current-lock direct-open test fails because P1.3 opens the chooser.
- Loading-status pre-ready command test fails because P1.3 has no such panel.

These are behavioral baseline differences, not a native proof of why clicks
were intercepted. See P1_4_EXPECTED_RED.json.

All 72 TOC Lua files compile under the stated fallback interpreter; the complete
addon boots in the synthetic harness. Reachable runtime closures remain within
60 non-environment upvalues. This is not a comprehensive native Lua 5.1 parser
or closure-limit certification.

## 6. Installation and remaining risks

Close WoW and preserve the previous addon and matching WTF backup. Replace only
the `Nexus` addon folder from the new ZIP; do not clear data, unresolved builds,
or the historical recovery archive. Confirm the delivered `test.9005-...` label.
Keep Auto OFF for the initial interface check.

Open the existing untagged plan. Matching current locks should bypass the dialog
and show all intended 79 ordinary/six locked copies. Save, reopen, and reload
through normal user controls to confirm live persistence. If current locks do not
match the plan, use the repaired fallback rather than deleting entries.

During startup, inspect the loading panel and local Wishlist controls. Builds
and Leaderboard must remain gated until shared readiness. Percentages can reset
between phases and are labelled accordingly. Total startup time, frame time,
native clicks, combat capture, public transport, resource usage, and peer
convergence are NOT TESTED in this environment. No fixed speed improvement or
stable-release acceptance is claimed.

The patch does not resolve unrelated historical player reports by association.
