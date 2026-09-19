# Nexus P1.5.1 — Experimental player guide

Nexus helps you work toward an Echo build: create or import a Wishlist, follow
recommendations or enable selected automatic actions, share builds, and compare
recorded DPS. P1.5 adds **Orbs / Lost Memories** refinement with explicit source
and spending approval. P1.5.1 corrects the demonstrated source-protection,
confirmation, and Recheck defects and completes the reviewed wording paths.

**Real-resource Orb testing is not approved for this replacement.** Native
capabilities, notification order, and quality-consumption behavior remain
unverified. No installation or native test follows this package automatically.
Any real-resource test requires a separate user decision.

This is an experimental prototype, not a stable release. Check the exact package
build label and checksum supplied beside the ZIP. Never substitute an older
package merely because it has the same addon version number.

## Install and roll back

Close WoW. Back up the old `Interface/AddOns/Nexus` folder and matching `WTF`
folder outside the client. Replace only the addon folder; do not merge packages,
reset SavedVariables, or delete unresolved Wishlists. The installed path is
`Interface/AddOns/Nexus/Nexus.toc` (not a nested Nexus/Nexus folder).

Disable other Echo pickers, including a separate LoadoutPilot, before using Nexus
automation. LoadoutPilot is a behavioral reference, not a runtime dependency.
Keep Automation OFF for the initial navigation/save test.

To roll back, close WoW and restore matching old code and old saved data together.
Local backups cannot undo spent currency, Orbs, changed owned Echoes, or builds
already sent to peers. Do not roll back while a server-side Orb offer is unresolved.

## Reopenable Help

`/nexus help` opens a read-only, seven-page guide. `/nexus guide` and
`/nexus tutorial` open the same guide; they do not start automation or a compulsory
walkthrough. Help is available during loading. The main menu and Welcome screen
also provide **Help / Getting Started**.

Pages: Getting started; Wishlists and permanent targets; Rolling and settings;
Shared builds and DPS; Orbs / Lost Memories; Loading and troubleshooting; About.

## Normal setup

1. Open **Wishlists** or `/nexus editor`.
2. Create a plan or import a Wishlist code. Import opens a draft.
3. Review exact qualities and copy counts, including permanent-slot targets.
4. Save and assign the Wishlist to the intended Saved Build/loadout.
5. Check recommendations before enabling Automation and its individual actions.

A Wishlist is a desired plan; you do not have to own it already. **Saved Builds**
are server slots. **Active Loadout** is the currently selected server loadout.
**Build Library** browses locally known shared/saved records. These are not the
same storage or action.

### Copies, permanent targets, and Freeze

The supported plan is up to **79 rolled copies + 6 permanent-slot copies**, not
85 ordinary picks. Duplicate copies and different qualities count separately.

- Current permanent (Locked) Echoes are what you own in permanent slots.
- Permanent-slot targets are the plan's intended copies for those slots.
- A Frozen offer is temporarily retained by the game's Freeze action.
- Lock position controls only the draggable overlay's position.

Unmarked imports use matching current permanent Echoes by default when they form
an exact valid split. Existing confirmed plans are not rewritten when ownership
changes. When matching is insufficient, the editor offers explicit target choice.
Opening or confirming targets never locks or unlocks owned Echoes.

`/nexus currentlocks on|off` controls that default for future unresolved plans.
Nexus's optional permanent-role import markers are not claimed compatible with
every native importer. Do not manually change permanent slots merely to match
sorted diagnostic display order.

Optional automatic permanent-slot changes require both the master Automation
permission and the separate permanent-slot option, plus real game capability,
ownership, and safety checks. Orb refinement never changes permanent slots.

### Rolling recommendations

Ordinary rolling follows an independent implementation of the supplied
LoadoutPilot 1.3.6 / P103 policy. Snapshot activation and genuinely confirmed
saved-build guarantees remain distinct from random Designed/Wishlist rolling.
Neither a prediction nor a submitted action proves future delivery or ownership.

`/nexus reroll on|off` and `/nexus freeze on|off` set individual permissions;
neither enables the master switch. Ordinary Take/Banish/Freeze/Reroll are blocked
while an Orb run owns an action or the game reports an active/unknown Orb offer.

**EXTRA COPIES** replaces “TO SHED”: rolled copies beyond exact Wishlist targets,
including unrequested or different-quality copies. Target 2/current 5 means 3
extras. It is not a delete action and does not promise a later replacement.
In save comparisons, “fewer requested copies” is distinct from “extra copies.”

“Waiting for current Echo data” is an ownership-readiness condition, not the
shared-build channel status. Do not force that state or repeatedly reload to
mask a lost response. Record the build and exact sequence for support.

## Orbs / Lost Memories

Open `/nexus orbs` or **Orbs / Lost Memories** in the main menu. Merely opening
it cannot spend an Orb. The mode is OFF by default and does not start on login,
resource arrival, import, ordinary Auto, or reopening its window.

1. Select a resolved Wishlist or use the assigned one.
2. Check exact missing rolled targets; move their priority with Up/Down.
3. **Suggest safe source pool**, then inspect every approved source and count.
   Use +/- or Exclude to protect additional copies. Clearing exclusions does
   not automatically authorize new sources.
4. Set the maximum Orbs for this run. The initial default is 10 but is not consent.
5. Optionally permit safe unwanted offers to be selected and recycled. Recycling
   is OFF by default. Without it, an offer without a needed target pauses.
6. Choose **Review single Orb** (cap 1) or **Review & start**.
7. Read the complete scrollable source list, balance, cap, and recycling option;
   check the explicit approval box and choose **Confirm & start**.

The controller requests **one Orb per replacement**, observes the actual offer,
chooses the first missing exact target in your ordered list or an approved safe
fallback, and waits for the observed offer/selection lifecycle, exact ownership
change, and charge/result confirmation before
another spend. It does not use the ordinary WishlistPlanner on Orb boards.

Required exact rolled copies, granted copies needed for future permanent targets,
and permanent copies are protected. One granted copy cannot satisfy both roles.
The candidate
source respects the reference's lowest-quality-family sacrifice behavior. A
source that could ambiguously refer to a permanent copy or multiple qualities
of the same ID is conservatively
excluded. Some apparently extra copies may therefore be unavailable as sources.
The run can stop with an unmet target when your approved source pool is exhausted.

Rolled targets and permanent targets are separate. Orbs do not create or replace
permanent slots; the run stops when rolled targets are complete, even when the
plan still has permanent targets you do not own.

**Starting turns ordinary Automation OFF; finishing never turns it back ON.**
The game's auto-accept and competing pickers must be off. Unknown or unavailable
client capabilities disable the affected Orb action with the missing capability
named. Tome-dependent availability uses discovered/observed Echo evidence and a
known disable-state answer; spellbook knowledge is not used as a substitute.

### Pause, Stop, uncertainty, and budgets

Closing the window does not stop an approved run. Use Pause or Stop.

- Pause/Stop prevents new submissions. It cannot undo an accepted spend.
- A submitted result may settle passively while paused or stopped.
- A pending offer remains available in the game's normal interface.
- Resume keeps the same approved source pool and usage; it cannot replay an
  ambiguous or already-attempted selection.
- A higher limit needs explicit review/confirmation and then explicit Resume.
- Confirmed usage and unresolved spending exposure both count against the cap.
- A missing response never makes the allowance available for another spend.
- Offer/result timeouts permit one bounded read-only refresh, then pause.
- Recheck requests charge/ownership data; it never submits a choice or spends.
- On reload/reconnect the run does not resume. A saved pending-operation marker
  is passive recovery evidence, not a restart instruction.

The same ID and quality can be removed and received again without a net count
change. The supported API cannot distinguish that result from stale ownership.
Nexus pauses with a specific reason and retains pending ownership and exposure.
A new table, lower charge count, or uncorrelated selection-result notice cannot
resolve that ambiguity. Recheck does not establish proof by returning the same
contents. No automatic retry is made. A same-ID result at a different quality
can settle when its exact state change and original offer/selection are observed.
Do not clear the recovery marker to force another run.

## Community, DPS, Sync, and loading

**Share Build** is different from saving a Wishlist or a server Saved Build.
Read delete/stop-sharing confirmations. A shared listing being removed does not
necessarily remove your server build or Wishlist.

**Both DPS records** means the required Training Dummy and Lich King records are
present; it is not a “good build” judgment. The combined ranking uses its highest
single eligible result; a shown average does not set that rank. DPS capture uses
Details! and supported events. Read-only Echo lists with attached results remain
protected.

Sync preparing, request sent, receiving, and completed are distinct. Request
sent does not prove peer convergence. **Removing expired requests** is queue
housekeeping. Nexus participates in its normal live sharing channel, so testing
is not network-isolated. Do not flood or send deliberately malformed traffic.
Older PR #68 receivers cannot fully represent the locked-bearing build format.

The loading panel shows the actual step and progress where a denominator exists.
A percentage is for that step, not a made-up overall percentage or ETA.
`/nexus loading` reopens it. Local Wishlist/rolling/Orb tools need their local
state and capabilities, not completed Community loading. Shared views and their
services retain their own readiness gates.

## Commands and diagnostic reports

- `/nexus help`, `/nexus guide`, `/nexus tutorial`: read-only guide.
- `/nexus orbs`: open refinement controls; does not spend.
- `/nexus loading`: show startup progress.
- `/nexus panel`: main panel visibility.
- `/nexus editor`: Wishlist editor.
- `/nexus status`: concise build and state.
- `/nexus sync`: request shared data through the existing manual route.
- `/nexus log errors`: recorded errors.
- `/nexus perf`: runtime performance observations, not DPS.
- `/nexus prototype`: implementation/provenance details.

**Prepare full diagnostic report** builds paged text. **Select this page** selects
only the current page; copy pages in order. Large reports may take a moment.
Start support reports with a build label, action, expected/actual behavior, and a
small relevant error screenshot. Do not publish full player backups by default.
Advanced raw reason codes remain for support; do not use reset/anchor/restore
commands as generic fixes without understanding their effects.

## Verification and remaining limitations

P1.5.1 uses synthetic services and real Nexus adapters/controllers/UI handlers
under the established LuaJIT 2.1 / Lua 5.1 Windows route. It uses no Lua 5.4
compatibility shims. These tests are not native WoW verification or the complete
upstream regression campaign. See the delivered source/package test receipts
and focused independent review for exact results, counts, hashes, and limitations.

New Orb capability discovery, source choice, action/result reconciliation, and
UI interaction must be verified in the actual client before relying on them.
No real Orb was spent to produce this package. Source compatibility with a
reference is not proof of the server's behavior, universal API availability,
or native safety/performance. This package does not authorize a spending test.

The original videos, data-recovery history, native timing, full peer convergence,
and historical-backup recovery are not retroactively resolved by these offline
passes. Stop for unexpected character actions, persistent uncertainty, missing
data, errors, or severe stalls. Preserve evidence rather than deleting fields.

Detailed historical notes are in the source archive under docs, not duplicated
as old install instructions here. The source review and tests remain available
with the exact release ZIP; GitHub, T3, and your installed game were not changed.
