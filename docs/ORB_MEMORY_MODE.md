# P1.5 Orb of Lost Memories implementation

## Actual execution path

Read-only target/source selection -> opaque expiring approval token -> explicit
review/checkbox -> ordinary Automation OFF -> exclusive Orb owner -> durable
passive pending marker -> ConfirmSpend(source ID, 1) -> authoritative offer and
one-Orb charge change -> exact target or allowed recyclable fallback ->
SelectPerk(choice ID) -> fresh ownership/diff/charge confirmation -> next approved
source or terminal stop.

The frame advances at most one transaction step per 0.2-second update; it does not
loop through a run synchronously. The ordinary EchoWeaver planner is not called
on Orb boards. All mutation calls sit behind GameAdapter.Orbs. Ordinary Take,
Freeze, Banish, Reroll and permanent-slot/activation/upload actions stay guarded
while an Orb operation owns state. When an OrbService exists, ordinary Take,
Freeze, Banish and Reroll also require its known, not-pending state
(`OrbAdapter.ServiceState`). Sync and Community transport are not repurposed
as an Orb API.

## Targets and source selection

Normalize exact `(spellId, quality, role)` copies, with no more than 79 rolled and
6 permanent copies. Ordered rolled deficits guide target selection. Permanent
deficits remain visible but cannot be fulfilled by Orb spending. Once rolled
deficits reach zero the loop stops, including with unmet permanent targets.

Group sources by real catalog family. Select the lowest actual owned quality/ID
in a family before assessing excess above the required target count. Do not jump
over a protected low-quality source or assume an ID-only call consumes a different
variant. Exclude a source ID also represented in permanent ownership, since the
reference call cannot disambiguate such a copy. User exclusions remove source
eligibility; explicit approved counts remain finite.

Safe recycling is opt-in. A non-target fallback is only selected when available,
selectable, under its actual capacity and not excluded. It becomes the preferred
recyclable source only after a fresh confirmed result and another safety check.
A target obtained through refinement is not automatically reapproved as a source.

## State and spending

`IDLE`, `READY`, `WAIT_OFFER`, `WAIT_RESULT`, `PAUSED`, `STOPPED`, `COMPLETE`,
`ROLLED_COMPLETE`, `LIMIT`, `OUT_OF_ORBS`, `NO_SOURCES`, and `RECOVERY` are distinct.

Confirmed consumption plus unresolved exposure counts toward the run cap. An
explicit local rejection can clear unincurred reservation; an exception or unknown
outcome cannot. Once a selection was attempted it is not automatically replayed.
A pending operation is reconciled passively after Stop; Stop cannot undo a spend.

Offer/result timers permit one read-only refresh at 10/12 seconds respectively,
then pause if confirmation remains unavailable. Explicit Recheck is rate-limited
to three seconds. No action is confirmed by time, pcall success, closed UI, or an
unchanged old snapshot.

Same-ID replacement is reconciled by subtracting the known source before comparing
the complete granted map. Runtime additionally requires fresh granted-reference or
content evidence, one-Orb charge change, no unresolved offer/choice/host action,
and unchanged permanent ownership. These are local evidence checks; no native
server correlation capability is invented.

The one-Orb charge change is required once. When it was already observed while
the action's Orb offer was pending (`spendConfirmed` in the saved receipt), settlement does not
require the player's later total Orb balance to stay one less than before the
action: an Orb gained or spent later for another reason must not hold the action
forever. A later balance change is not completion evidence. Every other
requirement above still applies, and only the exact ownership result settles it.

On the live path `spendConfirmed` is client-side evidence, not a server
confirmation. The game client lowers its own Orb count and marks an offer as
owed when the spend is called, before the server answers, and Nexus reads those
two values. After a reload, recovery can also set it from the balance and the
owed offer that the server sends after the reload. The
server's evidence is the offer it then shows (three choices, recorded in the
receipt) and the ownership that follows the choice. Settlement therefore still
needs the recorded offer, the recorded choice and the exact fresh ownership
delta. Without the later balance check, the balance can no longer show that
the server charged exactly one Orb: a moved balance can make Nexus's usage count
differ by one from the server's charge, but it cannot change which Echo result
settles the action.

## Persistence and interruption

Only configuration, explicit choices, and passive unresolved-operation evidence
are stored per character through the existing Store authority owner. No live
function/object, mutation callback, raw server owner, or automatic-resume flag is
persisted. Reload starts RECOVERY, not running. A fresh baseline plus a later
read-only response can settle the old result; it cannot launch another Orb.

Recovery after reload is passive (see `docs/ROLLING_ORB_REVIEW_EADFF8A.md`, R2).
It holds no action owner. It installs only the read-only `SelectPerk` observer.
An offer that is still open is tied to the saved action only on exact evidence:
one Orb less than the receipt, ownership equal to the receipt with or without
the named source, unchanged permanent Echoes, and the original loadout. A manual
choice observed in that offer, then the exact fresh ownership delta, settles the
action. An action that ended while unobserved stays unresolved; the visible
text says that it cannot be confirmed and that Recheck cannot settle it.
The offer and the choice are also recorded at the moment of a manual choice
(event-driven, through the same read-only observer), so the observation does not
depend on the timed reads. Besides the exact matching result, the only exit from a block is the player's explicit
Continue for an action with a spend this client observed (one Orb fewer with its
offer) and no recorded outcome whose offer is gone
(`docs/ORB_RECOVERY_CONTINUE.md`); a block that has no such exit says so.

After a reload or login the client shows its load-time default active slot
(0, "none") until the server sends its build-slot data; `GetServerBuildSlots()`
is nil until then. That default is not an observation of a loadout change: a
restored action waits read-only (`LOADOUT_UNKNOWN`), records nothing and
settles nothing until the real slot is known, and then applies the normal
loadout rule (a different slot, or a receipt without an original slot, keeps
the hold). A slot other than 0 shown in that state comes from the server's
active-slot push: a different one is a loadout change, and a later return to
the original slot does not settle the action. A client without
`GetServerBuildSlots()` keeps the plain slot comparison.

The loadout hold is one saved flag (`loadoutChanged`). Several different causes
set it alike: a real slot change, a different slot pushed before the build-slot
data, the plain comparison on a client that cannot report slot data, a receipt
without an original slot, and (in builds before the wait for the build-slot data
existed) a reload whose first read came before the server's slot data, because
that build compared the load-time default slot 0 with the recorded slot. A hold that an earlier build saved says nothing about which
of these happened, and no later read can tell. The support summary therefore
adds a loadout line to the Orb action: the original slot (`not recorded` when
absent), the slot read now and whether the build-slot data has arrived, the
loadout check, the cause the hold was first set for and when, whether an offer
is recorded, and the requirements that the saved record alone shows unmet
(`loadout`, and `choice` when no choice is recorded). The cause is recorded once,
at the moment a build with this line first sets the hold, as three small saved
fields in the pending receipt (`loadoutCause`, a fixed name;
`loadoutObservedSlot`, a whole number from 0 to 65535; and `loadoutObservedAt`,
the client clock time in whole seconds, from 2000-01-01 to 2100-01-01 UTC, shown
with the date in the local form of the audit rows and labelled "local", so that it
can be compared with them (the error times in the same report are UTC and say so);
it is absent when the clock is missing, failing or implausible). They are never changed
later. A hold saved without a cause stays `not recorded`: it is not filled in
from a later read, and a missing original slot is never inferred. Older builds
copy these fields through their own saves. The line is text only. It adds no
requirement, removes none, and changes no block. Settlement still needs the
recorded offer, a recorded choice inside that offer and the exact fresh ownership
delta, so a receipt that records no choice cannot be settled, with or without the
hold.

While a recorded choice waits for its result (`WAIT_RESULT`), the
status names the settlement requirement that the last read did not meet (a
fresh ownership response, the chosen Echo in ownership, an open offer or
another game action, an open Echo choice, or, while the spend is not yet
confirmed, an Orb balance other than one less than before the action). Naming it
changes no requirement.

After a reload the player can choose in the game before Nexus has read the game
state. The first ownership read then already shows the recorded choice, but it
is not newer than the recovery baseline. When that is the only missing
requirement, recovery asks the game once per load for a newer ownership
response: the same read-only request as Recheck. It sends no Orb and no choice
and changes no requirement. If no newer response arrives, the status says that
the request was made and that Recheck requests one more.

A loading screen pauses a running Orb action ("Session interrupted"). When the
choice that Nexus sent before it gets no reply, the game keeps its own latch for
that choice and refuses every choice in its offer window until a /reload. If
the game still holds this action's choice five seconds after the loading screen,
the status says so, names the recorded Echo, and says that /reload ends the
wait and that only that Echo can confirm the action afterwards. After the
reload, while the recorded offer is still open, the recovery status names the
same Echo, also when the Orb balance moved after a spend this client observed
(the same recorded offer still belongs to the action). It is text only; any other offer
stays unmatched.

The support summary and the prepared support report state the unresolved Orb
action, if any: whether it was restored after a reload, the recovery state, the
settlement requirement that the last read did not meet, whether the spend and the
choice are recorded, the selected and source Echo keys, whether the game still
holds a choice, whether a loadout change is recorded, and whether the automatic
refresh was requested. It contains no names and writes nothing; like the
ordinary-rolling block check, reading it can start the read-only recovery of a
saved action.

Character/run/service/loadout change pauses the run. Resume rechecks the original
context, targets, owner, and budget. A budget increase needs a new approval token
and explicit Resume; it does not reset usage. Completed/stopped runs cannot be
revived by an increase operation.

## User interface and local readiness

The bounded Orb window is opened by `/nexus orbs`, a main-menu entry, or Welcome.
It includes actual target selection, order controls, source approval/exclusion,
all-source review, run limit, optional recycling, Start/single-step, Pause/Resume,
Stop, Recheck, and Help. Start is never implicit. Missing Orb APIs disable only
this feature. Local Store/ownership capability readiness is required; Community
preparation is not a prerequisite.

During a run (running, paused, at its maximum or with an operation pending) the
window shows Pause and Resume as two separate buttons in Start's place, and the
main Nexus panel strip has the same two fixed buttons, so a repeated press of
Pause never becomes Resume. Each click reads the status again and acts only if
that read offers the action; Orb mode then makes its own final checks. Resume
continues the paused run with the same approved maximum and does not reset its
usage. Starting a run and approving its maximum stay in this window: Start,
including the two-step **Start new run** / **Confirm new run**, returns once the
run is no longer active. The earlier one-button Pause/Resume entry points are
not shown during a run. They reach the same runtime actions and final checks,
but what they withhold before that call is not identical to the fixed buttons
(before a Resume, the window's hidden entry checks only the target review below).

While a run is paused, the status names what Resume would act on (the runtime's
`resumeTarget`). For an ordinary pending operation it is the original operation,
which Resume continues. For a settled run it is the ready assigned Wishlist that
Resume would use, shown as the same target or a new one. Same or new is the
runtime's current comparison with the assignment the run is bound to: the one
approved at Start, or the one a later Resume adopted. When a pending operation's
assignment no longer matches, the status says that the original operation must
settle first; when a settled run's assignment is restoring, loading, unavailable
or not assigned, it says that the target is unknown. Neither names a Wishlist.
No target is named for a record restored after a reload, an operation whose
choice was already attempted, or any other case in which Resume is not offered.
When the runtime records a target change, the status also names the original
operation.

When a settled run would resume with a new target, the window withholds Resume
until **Review target** records a review of the exact target it shows, including
its slot and Echo entries. The button then reads **Cancel review**, which clears
the review. A click acts only on the target and the action that the button
showed at the last refresh: when the target changed since, nothing is reviewed,
the review is cleared, and the new target needs its own review. Review target
shares Continue's place and is not shown with it. Review and Cancel review
spend, send and save nothing. The review is held in memory and is cleared when
the target shown changes, when the run leaves that state or when the window
closes. It gates only the window's own Resume: the runtime's Resume does not
check it, still makes every final check and adopts the assignment it reads
then. The mini panel and the strip never resume a new target; they point to
this window.

An unresolved earlier result reads in layers in the window's status: first
what it blocks ("Previous result is unresolved: no new Orb run or ordinary roll
until it settles."), then what you can do now, by the Continue state actually
shown (**Continue...**, **Why blocked...**, **Review check...**, or finishing or
cancelling a check in the Continue window), then `Details:` with the runtime's
own reason, unshortened, so recorded Echo names and earlier facts stay exact. A
status longer than its box is complete on hover. The layers are shown in
RECOVERY and also while a record restored after a reload is held in another
state, for example paused by its saved loadout hold. Such a paused record names
no Resume target; the mini panel and the strip say only that its result must
settle, and **Open Orbs** or **Details** opens this window. Continue is offered
only for an eligible record (`docs/ORB_RECOVERY_CONTINUE.md`). It needs its
read-only check and your explicit confirmation; it does not confirm the earlier
result, and it never refunds, retries or deletes it. Nexus never continues by
itself. While this session's history is empty, the Continue window of a
restored record says that the steps before the reload are not listed. A paused
action of this session keeps the plain status: its state, any Resume target,
then the runtime's instruction.

Usage reads in one form. Orbs used counts spent Orbs against the approved
maximum, written "X / Y approved" in the window, strip and history. A requested
Orb whose spend is not confirmed yet is pending: the window adds "pending: 1 Orb
requested, not confirmed yet" and the strip shows "1 Orb pending, not confirmed
yet". When no requested Orb is waiting but the last action's result has not
settled, the strip shows "Last Orb action is not settled" (in short while a
target is named); that is not an unconfirmed request. The history page states
the requested count and, separately in the same line, that the run has an
unresolved operation; it shows that line only while an Orb is requested and not
confirmed. The copied history report keeps its existing lines, labels and entry
layout: its confirmed usage is the Orbs used count, and its unresolved exposure
is the requested count.

The strip has three lines: usage; then the pending count, an unsettled last
action or the rolled target copies remaining; then the state. While a paused
run names a Resume target, the second line keeps its fact first, in short (such
as "1 Orb pending" or "3 copies left", with "?" for an unknown count), then the
target's name, cut so that a short kind caption, "(new)" for a new target and
"(same)" otherwise, stays on the line; an unknown target reads "Resume target
unknown". The third line gives the instruction, such as "Paused - review it in
the Orb window" or "Paused - 1 Orb pending". Hovering the strip shows the
complete target, the complete fact line and the instruction. The strip has no
Continue state: a paused unresolved result reads "Paused - result must settle",
or "Paused - original must settle first" after a target change, and **Details**
opens this window.

Name bounds on the strip and the mini panel are character counts from offline
font models, not native measurements. A longer name is shortened on a character
boundary and is complete on hover; no native fit of a full name, or of a line
drawn in a larger client font, is promised.

The synthetic UI checks execute the real handlers and inspect structure. They do
not reproduce native font measurement, focus, hit-testing, frame strata effects,
or interference from other game addons.

## Verification limits

New tests exercise the actual Nexus adapter/runtime and mocked game services.
Exact-role/source/budget and fresh-evidence guards have separate controls
(`tests/prototype/echoweaver_orb_policy.lua` and the `orbs_*` tests). An earlier
offline comparison with an outside addon's source (3,000 offer decisions,
3,000 result diffs, and 10,000 ordinary decisions) is retired (2026-09-24);
it was never a claim of blanket parity.

These checks are offline. They load the real Lua modules against synthetic game
services and mocked Orb and ownership data. An offline pass is not a native client
result, an original upstream inventory or an independent review, and the checks
access no Orbs, player resources, live profiles or game sessions.

Future native testing needs separate explicit consent, with an expendable approved
source and a one-Orb limit first. An unresolved server operation must be handled
in the game, not by deleting the marker or retrying a spend.

## Local readiness and idle window work (2026-09-22)

- **Start and persistence agree.** Orb preferences and the recovery receipt are written through the Store owner (`StoreAuthorityOwner.UpdateStateV1`). `Store.StateWriteStatus()` (read-only) states whether that write can be durable now: character identity unknown, saved data loading, database or character container missing, a newer schema, or a character row of another shape. Start is enabled only when it can be durable, and its reason names the case. An absent character row is not a refusal: the owner creates it at the explicit Orb write, and the Orb runtime then checks that the durable row holds the data (the owner also reports success for its transient fallback). Reading a view never creates or writes the row. No spend or choice is sent before its receipt is durable; if persistence fails after a spend may have been sent, the unresolved exposure stays.
- **Idle window work.** One display refresh (every 0.25 s while the window is shown) makes one adapter read. The adapter builds availability rows only for the IDs a read is asked about (targets, owned copies, offered cards), with the same rules per row, instead of rebuilding the whole local Echo catalog on every read; nothing is kept between reads. The source list is prepared only while Advanced is open. Every action (Start, Resume, each spend and selection) reads again; the display snapshot authorizes nothing.
- Measured offline with the review probe setup (1,000-row catalog, one idle second): before 8 reads, 8 full catalog traversals (8,000 row visits), 16 assignment lookups; after 4 reads, 0 traversals, 8 row builds, 4 assignment lookups. These are work counts, not native frame times.
