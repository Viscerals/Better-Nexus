# P1.5 Orb of Lost Memories implementation

## Actual execution path

Read-only target/source selection -> opaque expiring approval token -> explicit
review/checkbox -> ordinary Automation OFF -> exclusive Orb owner -> durable
passive pending marker -> ConfirmSpend(source ID, 1) -> authoritative offer and
one-Orb charge change -> exact target or allowed recyclable fallback ->
SelectPerk(choice ID) -> fresh ownership/diff/charge confirmation -> next approved
source or terminal stop.

The frame advances at most one transaction step per 0.2-second update; it does not
loop through a run synchronously. The ordinary WishlistPilot planner is not called
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
depend on the timed reads. A block that has no exit says so: the settlement path
is only a proposal and is not built.

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

The synthetic UI checks execute the real handlers and inspect structure. They do
not reproduce native font measurement, focus, hit-testing, frame strata effects,
or interference from other game addons.

## Verification limits

New tests exercise the actual Nexus adapter/runtime and mocked game services.
3,000 offer-decision and 3,000 result-diff comparisons run against the supplied
MemoryMode source on compatible represented inputs. Exact-role/source/budget and
fresh-evidence guards have separate controls, not a claim of blanket parity.
The ordinary 10,000-case reference comparison remains unchanged.

All tests in this build use Lua 5.4 with the included compatibility shims. They are
not a LuaJIT, native client, original upstream inventory, or independent review
result. No Orbs, player resources, live profiles, or game sessions were accessed.

Future native testing needs separate explicit consent, with an expendable approved
source and a one-Orb limit first. An unresolved server operation must be handled
in the game, not by deleting the marker or retrying a spend.

## Local readiness and idle window work (2026-09-22)

- **Start and persistence agree.** Orb preferences and the recovery receipt are written through the Store owner (`StoreAuthorityOwner.UpdateStateV1`). `Store.StateWriteStatus()` (read-only) states whether that write can be durable now: character identity unknown, saved data loading, database or character container missing, a newer schema, or a character row of another shape. Start is enabled only when it can be durable, and its reason names the case. An absent character row is not a refusal: the owner creates it at the explicit Orb write, and the Orb runtime then checks that the durable row holds the data (the owner also reports success for its transient fallback). Reading a view never creates or writes the row. No spend or choice is sent before its receipt is durable; if persistence fails after a spend may have been sent, the unresolved exposure stays.
- **Idle window work.** One display refresh (every 0.25 s while the window is shown) makes one adapter read. The adapter builds availability rows only for the IDs a read is asked about (targets, owned copies, offered cards), with the same rules per row, instead of rebuilding the whole local Echo catalog on every read; nothing is kept between reads. The source list is prepared only while Advanced is open. Every action (Start, Resume, each spend and selection) reads again; the display snapshot authorizes nothing.
- Measured offline with the review probe setup (1,000-row catalog, one idle second): before 8 reads, 8 full catalog traversals (8,000 row visits), 16 assignment lookups; after 4 reads, 0 traversals, 8 row builds, 4 assignment lookups. These are work counts, not native frame times.
