# Nexus P1.6 — Experimental player guide

Nexus helps you work toward an Echo build: create or import a Wishlist, follow
recommendations or enable selected automatic actions, share builds, and compare
recorded DPS. This continuation simplifies **Orbs / Lost Memories** around the
assigned Wishlist and one explicit Start. It retains the P1.5.1 source, result
confirmation, and read-only Recheck safeguards.

**Real-resource Orb testing is not approved for this replacement.** Native
capabilities, notification order, and quality-consumption behavior remain
unverified. Bounded native Help, assignment-persistence, and controlled Sync tests
are authorized separately for this exact build. All spending remains prohibited.
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

1. Check the assigned Wishlist, missing rolled copies, permanent-target limits,
   and confirmed Orb balance. Unknown or loading is never shown as zero.
2. Enter the maximum Orbs for this run. The initial default of 10 is not consent.
3. **Start** approves that maximum and automatic use of eligible surplus copies,
   including safe unwanted replacements and recycling after confirmation.
4. The run continues after each confirmed result. Use Pause or Stop when needed.
   Advanced contains optional source exclusions and a read-only Recheck.

The main panel, Wishlist tools, and Orb view use the same assignment. There is no
second Orb target selector. If no assignment exists, use My Builds or the editor.
A known assignment shows **Restoring assigned Wishlist...** while active identity
is unavailable. Duplicate names and reordered slots cannot replace its exact
saved contents. An absent server mirror is explained; the saved plan is retained.
Server-list absence alone is not proof of deletion.

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
The run can stop with an unmet target when no safe surplus source remains.

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
- Active loadout, assignment, or target changes pause new submissions. The
  original pending operation keeps its original target until settlement.
- Explicit Resume adopts the new resolved assignment, recalculates protection,
  and retains the same maximum and all confirmed/unresolved usage. It cannot
  replay an ambiguous or already-attempted selection.
- The compact main-panel row provides progress and Pause/Resume/Stop while the
  detailed window is closed.
- The maximum cannot be edited during an active or paused run.
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

Changing the active loadout during a pending operation also prevents reliable
confirmation: ownership responses do not identify their originating loadout.
The pending receipt and exposure remain, including after returning to the old
loadout, Recheck, Stop or reload. A matching snapshot from a different loadout
cannot permit another spend. Assignment changes within the same loadout still
permit passive settlement when the original offer, selection and exact result
are confirmed.

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

This continuation uses synthetic services and real Nexus adapters/controllers/UI handlers
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
with the exact experimental ZIP. Native results are recorded separately against
the exact package; an offline pass is not native confirmation.

## Stop Sharing result text

Stop Sharing reports whether local removal was refused, is waiting for its
accepted catalog operation, or has completed. The record remains present while
local removal is pending. Queue admission alone does not prove local removal.
Local removal does not prove removal on another client.

Remote withdrawal remains unavailable with the current Sync protocol. A local
removal can finish while its withdrawal is not queued. The panel states this
limit. No automatic removal retry or resource spending is added.

The Stop Sharing confirmation stays above the Build Library. Closing or
reopening the Library keeps that confirmation bound to the original record.
Cancel or Escape dismisses it without removal. The shared popup slot returns
to its prior layer when the confirmation closes.
