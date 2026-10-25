# P1.5 Orb of Lost Memories implementation

## Actual execution path

Read-only target/source selection -> opaque expiring approval token -> explicit
represented maximum/history review -> ordinary Automation OFF -> exclusive Orb owner -> durable
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

`IDLE`, `READY`, `WAIT_WORLD`, `WAIT_OFFER`, `WAIT_RESULT`, `PAUSED`, `STOPPED`, `COMPLETE`,
`ROLLED_COMPLETE`, `LIMIT`, `OUT_OF_ORBS`, `NO_SOURCES`, and `RECOVERY` are distinct.

Client-observed consumption plus unresolved and archived uncertain spend exposure counts toward the run cap. An
explicit local rejection can clear unincurred reservation; an exception or unknown
outcome cannot. Once a selection was attempted it is not automatically replayed.
A pending operation is reconciled passively after Stop; Stop cannot undo a spend.

Offer/result timers begin reconciliation at 10/12 seconds respectively. A live
approved run can attempt at most two bounded recovery checks using explicit
empty-choice response evidence; an open choice or active action is never
replayed. A failed check pauses with its receipt retained. See
`ORB_BOUNDED_RECOVERY.md`. Explicit Recheck is rate-limited
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
depend on the timed reads. Besides the exact matching result, the player's explicit Continue has two narrow
classes: an action with a spend this client observed (one Orb fewer with its
offer) and no recorded outcome whose offer is gone, or a stopped ambiguous choice
with its fresh distinct gain actually owned
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

A loading screen holds a running Orb action in `WAIT_WORLD`, retaining only
its existing session approval. Once the game is readable the owner reconciles
the current choice; it never resends a submitted selection. Stop and Pause
are preserved, and logout/reload still ends authorization. When the
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
character/run/service context, owner and budget. A pending run continues its
original operation, and a changed target waits until that operation settles. A
settled paused run resumes with the ready assignment read at Resume, which can
differ from its current binding. User interface and local readiness describes how
such a change is shown and reviewed. A budget increase needs a new approval token
and explicit Resume; it does not reset usage. Completed/stopped runs cannot be
revived by an increase operation.

## User interface and local readiness

The bounded Orb window is opened by `/nexus orbs`, a main-menu entry, or Welcome.
It includes actual target selection, order controls, source approval/exclusion,
all-source review, run limit, optional recycling, Start/single-step, separate
fixed Pause and Resume during a run, Stop, Recheck, and Help. Start is never
implicit. Missing Orb APIs disable only this feature. Local Store/ownership
capability readiness is required; Community preparation is not a prerequisite.

The synthetic UI checks execute the real handlers and inspect structure. They do
not reproduce native font measurement, focus, keyboard input, dragging,
hit-testing, double-click timing, frame strata effects, server effects, resource
spending, or interference from other game addons. Offline checks and source text
do not establish native results.

### Run controls

The full Orb window, the compact strip under the main Nexus panel and the
optional mini panel (`ORB_MINI_PANEL.md`) show the same runtime status. The
window replaces Start with separate fixed Pause and Resume buttons while a run is
running, paused, at its limit or has a pending operation. The strip appears once
this session has an approved run, or while an operation is pending. It has its
own fixed Pause and Resume beside Stop and Details. Each button keeps one
meaning, so a repeated press of Pause never becomes Resume. A Pause or Resume
click reads the status again and acts only if that read still offers the action.
It then calls the existing runtime action, which makes its own final checks. The
displayed status authorizes nothing. Resume keeps the approved maximum and the
run's usage, and the runtime may pause or end the run again at once. These views
offer no way to raise the maximum during a run. To raise it, stop and start a new
run with a higher maximum. Start returns once the run is no longer active,
including the two-step **Start new run** / **Confirm new run** after a finished
run. Starting a run and approving its maximum stay in the full window.

The earlier one-button entries remain only as hidden programmatic compatibility
routes. They are the window's Start control while a run is running or paused
(Pause while running, Resume while paused) and the strip's original single
button. A player cannot see or click them. They reach the same runtime Pause and
Resume, and so the same final checks. Their interface withholding differs from
the fixed buttons, though. The window route applies the target review but does
not first require a displayed Resume offer. The strip route never resumes a
changed target. A direct runtime call is governed only by the runtime's own
checks, which do not include the window's target review.

Usage reads "Orbs used: X / Y approved" in the window, the strip and the
history, and "X of Y approved" in the mini panel. Pending is a count of Orbs
requested whose spend is not confirmed yet. When no Orb is pending but the last
Orb action has not settled, the strip and the mini panel say so instead. That is
not a pending count. Unknown spend exposure, unconfirmed outcomes and earlier
totals unavailable after a reload are shown apart from the observed usage.
Exposure still counts toward the run cap (see State and spending), but none of
these is taken as a confirmed spend, a refund or a settled result. A receipt
restored without its recorded approved maximum shows "maximum not recorded"
(strip: "max not recorded") instead of a number. The configured fallback still
gates it. It is not a new approval, and the wording changes no gate.

### Resume target and target review

While a run is paused, the window and the strip state what an explicit Resume
would act on. They take it from the runtime's Resume-target view. For a pending
run it is the original operation that Resume continues. For a settled run it is
the ready assigned Wishlist that Resume would use, which may be the same target
or a changed one. A target counts as changed in two cases. It may differ from the
binding and context that the run holds now (those of its approval, or those a
later explicit Resume adopted). The runtime may also have recorded a target or
context change during the run. The Wishlist name the run started with does not
decide this on its own. When Resume is blocked or not offered, no target is
guessed:

- An assigned Wishlist that is restoring, loading, unavailable or unassigned is
  reported as unknown, without a name, and Resume is not offered.
- A pending operation whose target changed must settle first. Until then the
  window says that Resume waits for it and names no new target.
- A paused run that no longer holds its approval or action ownership cannot
  resume, whatever the assignment says. No target is named, and the way on is
  Stop, then a new approval. A loading screen does not necessarily end approval.
  A running action waits in `WAIT_WORLD` with its existing session approval (see
  Persistence and interruption).
- A restored receipt, an operation whose choice was already attempted, and any
  other paused state without an offered Resume name nothing. The runtime reason
  says what must happen.

For a changed target, the window offers Resume only after **Review target** for
the exact target it shows. It names that target and, when the names differ, the
name it would replace. A target that changed and came back to the run's own
Wishlist still needs that review. The window says "Target changed and is back",
the compact views mark it "(back)" or "Target back to", and none calls it new.
The strip and the mini panel name a changed target and point to the full window.
They never resume it, even after it was reviewed there. **Review target** shares
the place of **Continue...** and is not shown while that button is shown.

**Review target** and **Cancel review** act only on the exact target and the
action that the button showed at the last refresh. The click reads the status
again. If that read shows another target, the click neither reviews nor cancels.
It clears any review and says to check the target shown now. If the read shows no
changed target, the click clears any review and changes nothing else. A stale
click therefore never reviews a target that was not shown. A later deliberate
click on the redrawn button may review the target shown then. A review is memory
only: it writes, sends and spends nothing. It is cleared by a different target,
by leaving the paused changed-target state or by closing the window. Resume
stays a separate deliberate click. The review only withholds the window's Resume
and is not a runtime gate. Resume still makes every runtime check and adopts the
assignment it reads at that moment.

### Unresolved records

In the full window, an unresolved earlier result reads in layers. First comes
what it blocks. Next comes what the player can do now, from the actual Continue
state: **Continue...**, **Why blocked...**, **Review check...** or the open
check. Last come the details: the runtime reason, unshortened. This layout
applies in `RECOVERY`. It also applies to a receipt restored after a reload that
the runtime keeps `PAUSED` (for example by the loadout hold), and to another
pending, nonrunning record whose Continue view offers its explanation. Only the
restored `PAUSED` record takes the label "Paused - a result restored after a
reload is unresolved". It stays `PAUSED`, and no state, receipt, gate,
settlement, limit, authorization or spend rule changes. A live automatic
recovery check keeps its owned phase before the headline. No Resume target is
guessed for such a record. A run paused in this session without such a record
keeps its phase line, such as "Paused", with its reason.

Paused, restored, already selected and settling records do not all have an
eligible Continue. The headline says "until it settles or you continue past it"
only where an explicit Continue is offered, meaning the record is eligible or
its check is running or ready. Otherwise it says "until it settles". A record
with only an explanation offers **Why blocked...**, which starts no check. An
eligible Continue first makes its read-only check and asks the player to
confirm. It then archives the original receipt unchanged as unconfirmed
(`ORB_RECOVERY_CONTINUE.md`). That is not settlement, retry, refund or deletion.
It sends no spend or choice, keeps the counted usage and exposure, and never
happens by itself. The strip and the mini panel may show an owned recovery or
Continue check phase first. They do not show Continue eligibility. **Details**
and **Open Orbs** open the full window for the explanation and the action.

### Compact strip

The strip shows usage, a second line and a state line. An owned recovery phase
comes first while one exists. Its complete text is available on hover. The
second line shows one fact, in this order of priority: Orbs pending, not
confirmed yet; the last Orb action is not settled; the target copies remaining,
or that target data is unavailable. While a run is paused and a target is named
or reported unknown, that fact stays first in short form, followed by the
target. The target is either "Resume target unknown" or a name, shortened on a
character boundary, with a short kind caption. The caption is "(same)" for the
original operation or an unchanged Wishlist, and "(new)" or "(back)" for a
changed one. The caption says how the target relates to the run; it is not the
name. The hover keeps the complete target, the complete fact and the
instruction. The state line gives that instruction, for example "Paused - review
it in the Orb window", "Paused - Wishlist not ready" or "Paused - original must
settle first". When it would read just "Paused", a pending unconfirmed Orb is
restated there. A paused pending run whose Resume is not offered, and that has no
more specific instruction, reads "Paused - result must settle". Line lengths
follow an offline character model, not a native measurement, and are no evidence
that the text fits natively. The mini panel's compact form is described in
`ORB_MINI_PANEL.md`.

## Verification limits

New tests exercise the actual Nexus adapter/runtime and mocked game services.
Exact-role/source/budget and fresh-evidence guards have separate controls
(`tests/prototype/echoweaver_orb_policy.lua` and the `orbs_*` tests). An earlier
offline comparison with an outside addon's source is retired (2026-09-24);
it was never a claim of blanket parity.

Offline harnesses and compatibility shims do not establish native client
behavior or independent review acceptance. Native game behavior and actual
resource spending remain untested here.

Future native testing needs separate explicit consent, with an expendable approved
source and a one-Orb limit first. An unresolved server operation must be handled
in the game, not by deleting the marker or retrying a spend.

## Local readiness and idle window work (2026-09-22)

- **Start and persistence agree.** Orb preferences and the recovery receipt are written through the Store owner (`StoreAuthorityOwner.UpdateStateV1`). `Store.StateWriteStatus()` (read-only) states whether that write can be durable now: character identity unknown, saved data loading, database or character container missing, a newer schema, or a character row of another shape. Start is enabled only when it can be durable, and its reason names the case. An absent character row is not a refusal: the owner creates it at the explicit Orb write, and the Orb runtime then checks that the durable row holds the data (the owner also reports success for its transient fallback). Reading a view never creates or writes the row. No spend or choice is sent before its receipt is durable; if persistence fails after a spend may have been sent, the unresolved exposure stays.
- **Idle window work.** One display refresh (every 0.25 s while the window is shown) makes one adapter read. The adapter builds availability rows only for the IDs a read is asked about (targets, owned copies, offered cards), with the same rules per row, instead of rebuilding the whole local Echo catalog on every read; nothing is kept between reads. The source list is prepared only while Advanced is open. Every action (Start, Resume, each spend and selection) reads again; the display snapshot authorizes nothing.
- The earlier idle-window work counts predate bounded recovery and its retained-history checks. They do not measure the current refresh path. Current aggregate work and native frame cost are unmeasured here.

New runs with nonempty validated unconfirmed history require the displayed
current-state baseline acknowledgment. It lasts only for that approval and its
same pending observation, including after Stop; reload restores no acknowledgment
or action authority. Old receipts remain unconfirmed. New operation admission
requires one complete bounded exit slot and late-growth headroom. Full valid
history is a finite capacity refusal, while malformed/future history is an
unverifiable-history refusal; neither is empty history. See
`ORB_BOUNDED_RECOVERY.md` for the current exact contract and native limits.
