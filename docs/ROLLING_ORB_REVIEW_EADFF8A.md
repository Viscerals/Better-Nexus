# Rolling and Orb corrections after the review of main `eadff8a`

Baseline: `eadff8abfe2ef4c732fc23afe18a3eb6c4f98302`, tree
`a54eb169ea01c310c86139788d3669d678f89c47`.

All tests named here are new synthetic offline tests written from the review
report's stated scenarios. The review's original probes were not available.
The tests use the real Nexus modules with mocked game services. They prove no
native client behaviour.

## R1 - Unknown Orb state and the ordinary-action gate

### Demonstrated cause

`GameAdapter.OrdinaryBoardAllowed()` read `OrbService.IsOfferPending()` only.
It did not read `OrbService.IsStateKnown()`. With a service that reported
"state not known" and "no offer pending", the gate returned true. The real
`GameAdapter.Take` then called `PerkService.SelectPerk`. Automatic rolling
submitted a Freeze in the same state.

### Current contract

`OrbAdapter.ServiceState()` is the one owner of the OrbService known/pending
classification for callers outside Orb mode. `OrdinaryBoardAllowed()` uses it.

| Capability case | Condition | Ordinary mutation |
|---|---|---|
| `NO_ORB_SERVICE` | `ProjectEbonhold.OrbService` is nil | Allowed. Explicit legacy capability. |
| `PENDING_ONLY` | `IsOfferPending` is a function and no `IsStateKnown` member exists | Allowed only when `IsOfferPending()` returns boolean false. Explicit legacy capability. |
| `STATE_AWARE` | `IsStateKnown` and `IsOfferPending` are functions | Allowed only when `IsStateKnown()` returns boolean true and `IsOfferPending()` returns boolean false. |
| `MALFORMED` | OrbService is not a table, `IsOfferPending` is not a function, or `IsStateKnown` exists and is not a function | Blocked: `orb state unavailable`. |

| State answer | Reason code | Visible text |
|---|---|---|
| `IsStateKnown()` returns false | `orb state not yet known` | Ordinary rolling paused: the server's Orb state is not confirmed yet |
| A callback throws or returns a non-boolean | `orb state unknown` | Ordinary rolling paused: the game's Orb state could not be read |
| Missing or malformed capability | `orb state unavailable` | Ordinary rolling paused: the game's Orb service does not expose its pending-offer state |
| `IsOfferPending()` returns true | `Orb offer active -- manual action required` | An Orb offer is active; use Orb mode or resolve it in the game |

Unknown state wins over the pending answer. A service that does not know its
state cannot vouch for its pending flag.

### Mutators and gate coverage

| Mutator | Game call | Guard |
|---|---|---|
| `GameAdapter.Take` | `PerkService.SelectPerk` | `OrdinaryBoardAllowed()` |
| `GameAdapter.Banish` | `PerkService.BanishPerk` | `OrdinaryBoardAllowed()` |
| `GameAdapter.Reroll` | `PerkService.RequestReroll` | `OrdinaryBoardAllowed()` |
| `GameAdapter.Freeze` | `PerkService.FreezePerk` | `OrdinaryBoardAllowed()` |
| Automatic rolling (`AutomationRuntime` `AutoAllowed`, and the policy state field `ordinaryBoardAllowed`) | the four calls above | `OrdinaryBoardAllowed()` |
| `GameAdapter.Activate`, `Save`, `UploadWishlist`, `LockPerk`, `UnlockPerk` | build-slot and permanent-slot calls | `OrbRuntime.BlocksOrdinary()` only. Not changed by R1. |
| `GameAdapter.ToggleLever` | `PerkService.ToggleTomeEcho` | No Orb guard. Not changed by R1. |

The second and third groups do not act on the three-card board. R1 did not
extend the Orb-state gate to them. The `BlocksOrdinary()` guard on the second
group still holds while an Orb operation is unresolved.

### Retained legacy decision

The existing test `tests/prototype/automation.lua` requires that a service
with `IsOfferPending` and no `IsStateKnown` member permits ordinary rolling.
R1 keeps that behaviour as the named `PENDING_ONLY` capability case. Orb mode
itself stays unavailable on such a client, because `OrbAdapter.Read()` requires
`IsStateKnown`.

Test: `tests/prototype/rolling_review_unknown_orb_state.lua`.

## R2 - Passive recovery after reload

### Demonstrated cause

A restored receipt went directly to `finishResult`. It never collected offer or
selection observations. The read-only `SelectPerk` observer was installed only
by `OrbAdapter.Acquire`, and a reload does not restore that owner. The visible
instruction was "Resolve the native offer, then Recheck". On the baseline, a
checkpoint with the observed offer, then a manual choice, the exact result and
four Rechecks stayed unresolved. The instruction promised more than the code
could observe.

### What changed

| Part | Change |
|---|---|
| `OrbAdapter.Watch(snapshot)` / `Unwatch()` | Passive watcher. It installs the same read-only `SelectPerk` observer that the action owner uses. It sets no owner, so `Spend`, `Select` and `Rebind` stay unavailable. |
| `OrbRuntime` restore | The read-only recovery pump starts when the receipt is restored. It reads at 0.2 s while an offer is open and for 60 s after restore or Recheck, then every 5 s. |
| `OrbRuntime` `recoverObserve` | Records the offer and a manual choice for a restored receipt, through the existing `observeLifecycle`. |
| Settlement | Unchanged owner: `finishResult`. All B2 requirements stay: the offer, a choice sent or observed within that offer, one Orb, closed offer and host state, the exact ownership delta, a fresh ownership response, unchanged permanent Echoes, the original loadout. |
| Text | The recovery reason is derived from the current observation on each passive pump. `Status().recovery = {kind, observing}` reports the same classification. |

An open offer is tied to the saved action only when all of these hold: the Orb
balance is exactly one less than the receipt, rolled ownership equals the
receipt with or without the named source, permanent Echoes are unchanged, the
loadout is the original one, and, for an offer first seen after the reload, no
host action is in flight and no selection was recorded. A recorded offer must
also have the same offer identity. An offer first seen after the reload is
marked `offerSeenAfterReload` in the receipt. This is the same evidence the live
path uses for its first offer observation, checked more strictly.

The watcher is bound to the original loadout only. A choice observed on an
unmatched offer, or on another loadout, is discarded and is never evidence for
the saved action. A choice recorded on the matched offer is still consumed when
that offer closes between two recovery reads.

| Recovery kind | Meaning | Text tells the player |
|---|---|---|
| `OFFER_OPEN`, observing | The matching offer is open | Choose in the game's offer window. Nexus records the choice and will not choose or spend. |
| `OFFER_OPEN`, not observing | No `hooksecurefunc` observer | A manual choice cannot be observed; the action cannot be confirmed afterwards; the record is kept. |
| `OFFER_UNMATCHED` | An open offer does not match the receipt | Nexus cannot confirm the earlier action from this offer; the record is kept. |
| `WAIT_RESULT` | A choice is recorded | Waiting for the exact fresh ownership response; Recheck requests one. |
| `WAIT_OFFER` | No offer, state still equals the receipt | The offer may still open; Nexus cannot tell whether the spend was refused; the record is kept. |
| `UNOBSERVABLE` | The action ended while unobserved | Nexus cannot confirm it; Recheck cannot settle it; record, exposure and blocks are kept; nothing is retried, refunded or deleted. |

Recovery never spends, never selects, never retries, never refunds allowance,
never erases the receipt, and never accepts an ownership delta alone.

### Not changed

- The live-path rule that a manual choice different from a recorded proposed
  key pauses the operation. This also applies after a reload.
- `UNOBSERVABLE` receipts still block new Orb runs and ordinary rolling
  indefinitely. See the proposal below.

### Proposal only, not implemented: acknowledged settlement of unobservable history

Goal: let a player leave the permanent block of an `UNOBSERVABLE` receipt
without any fabricated confirmation.

1. Eligibility: recovery kind `UNOBSERVABLE` only, continuously for a minimum
   time, with a successful fresh read: known Orb state, no Orb offer, no board,
   no host action, nothing in flight, original character.
2. Action: an explicit panel control with a typed or two-step acknowledgement.
   The text states that Nexus did not confirm the action and that the Orb is
   counted as spent.
3. Effect: the receipt moves, unchanged, to a bounded per-character
   `orbRefinement.unresolvedHistory` list with outcome `ACKNOWLEDGED_UNCONFIRMED`
   and the snapshot keys seen at acknowledgement. It is never recorded as a
   confirmed replacement and never enters `recent`.
4. Accounting: the exposure counts as one spent Orb of the old run. The old run
   ends as `STOPPED`. No allowance returns. No Resume.
5. After it: a new Orb run needs the normal new review. Ordinary rolling resumes
   only through the normal gate (`OrdinaryBoardAllowed`), which verifies the
   current native Orb state first.
6. Never: a retry of the original spend, a selection, an automatic trigger, or
   use for receipts whose offer is open or whose choice evidence exists.

This needs a user decision because it changes what a permanent block means.
It also needs a panel control in `ui/OrbPanel.lua` and a Store field.

Tests: `orb_review_reload_unobservable`, `orb_review_reload_manual_choice`,
`orb_review_reload_offer_after_reload`, `orb_review_reload_offer_mismatch`,
`orb_review_reload_no_observer`, `orb_review_reload_rejected_selection`,
`orb_review_reload_other_loadout`, `orb_review_reload_choice_between_reads`.

## R3 - Reroll: outstanding need versus original Wishlist membership

Status: deliberate policy difference from the named reference strategy
(LoadoutPilot 1.3.6 / patch 103). It is a proposed strategy change, not a
correction of a proven bug. It is one separate commit and can be reverted alone.

Reference rule: a permitted Reroll is skipped when any Echo of the original
Wishlist is on the board, also when its exact count is already met.

Nexus rule (option `rerollIgnoresSatisfiedTargets` in
`WishlistPilot.NEXUS_POLICY`, passed by `DecideNexus`): only an Echo that is
still needed stops the Reroll. `Pilot.Decide` without the option keeps the
reference decision, so `tests/prototype/planner_reference.lua` still compares
10,000 random inputs with the reference, unchanged.

Kept: the Reroll preference (`allowReroll`), the Reroll charge count, trusted
resource state, the pending guards, the ordinary-board gate, the two-frozen
Reroll prohibition, exact copy counts, permanent ownership, and every
still-needed or frozen still-needed offer (taken, never rerolled away).

New reason code `REROLL_NO_OUTSTANDING_ON_BOARD`, text "Reroll: no Echo on this
board is still needed". The old text "no requested Echo on board" would be
false for such a board.

Demonstrated on fixtures only (no draw odds are modelled):

| Fixture | Reference rule | R3 rule |
|---|---|---|
| F1: need 102, board 101 (met) / 901 / 902, 1 pick, 5 Rerolls | Take surplus 101, 0 Rerolls, 102 missing | Reroll |
| Replay A: the third scripted board holds 102 | 101 taken, 0 Rerolls, incomplete | 102 taken after 2 Rerolls |
| Replay B: 102 never appears | 101 taken, 0 Rerolls | 101 taken after all 5 Rerolls |
| `policy_compare` battery, 864 decisions | - | 16 decisions differ (8 states, each verified/unverified): with Banish and Reroll both available, 12 change from Banish of the met target to Reroll, and 4 (30 picks left, low pressure) change from a low-pressure fallback take to Reroll |

Trade-off: R3 spends Rerolls in states where the reference spends none or
spends a Banish. When the needed Echo does not appear, those Rerolls are gone
and the final pick is the same. No universal or optimal gain is claimed.

Test: `tests/prototype/rolling_review_reroll_outstanding.lua`.

## R5 - Freeze of a duplicate that the next selection makes surplus

Status: deliberate policy difference from the named reference strategy. It is a
proposed strategy change, not a correction of a proven bug. It is one separate
commit and can be reverted alone.

Reference rule: under high pressure, with a Freeze and a Banish available, the
best still-needed offer is frozen before the search.

Nexus rule (option `freezeMustStayNeeded` in `WishlistPilot.NEXUS_POLICY`): the
Freeze is skipped when the next selection is another selectable copy of the same
Echo and exactly one copy is needed. The planner takes the Echo at once.
`Pilot.Decide` without the option keeps the reference decision;
`planner_reference` is unchanged and passes.

Kept: the Freeze preference, Freeze and Banish charges, trusted resource state,
pending guards, the ordinary-board gate, exact copy counts, permanent ownership,
observed frozen offers, and the reference Freeze wherever the held copy stays
needed (two different needed Echoes, two needed copies, or no selectable
duplicate).

Demonstrated on the F3 fixture only (need 101 x1 and 102 x1, board 101 / 101 /
filler, 2 picks, 1 Freeze, 1 Banish):

| | Reference rule | R5 rule |
|---|---|---|
| Step 1 | Freeze 101 (index 1) | Take 101 (index 1) |
| Step 2 | Take the other 101 | - |
| Freeze charges used | 1 | 0 |
| Next board | held surplus 101 plus two fresh offers | three fresh offers |

The `policy_compare` battery has no duplicate-offer board: 0 of 864 decisions
change. No general efficiency gain is claimed.

Test: `tests/prototype/rolling_review_freeze_surplus.lua`.

## R4 - Reroll ration and reserve fields: trace only, no behavioural change

| Item | Location | Fact |
|---|---|---|
| Counters `fillerFishState` (`guaranteedId`, `consecutive`, `bracket`, `bracketSpent`) | `core/AutomationRuntime.lua` | Session-local. Reset at each level-bracket change (`RerollBracket`: 1-34, 35-63, 64-69, 70-77, 78+), at a change of the guaranteed spell, and at each run boundary. Not saved. |
| `state.rerollBudget` (`consecutive`, `consecutiveLimit` 3, or 2 at level 10 or lower; `bracketSpent`, `bracketLimit` 4, or 2 at level 10 or lower; `reserve` 5, or 0 from level 78) | `core/AutomationRuntime.lua` StepRun | Built for every decision. |
| The only reader | `logic/Policy.lua`, historical branch "bracket fishing: reroll filler guarantee" | It rations Rerolls of an unwanted *guaranteed* Echo. Production never reaches it: `Policy.Decide` routes every ordinary board to `WishlistPilot.DecideNexus`. |
| The active planner | `logic/WishlistPilot.lua` | Does not read `rerollBudget`. Its Reroll limits are: permission `allowReroll`, trusted charges, Reroll charges above 0, not pending, fewer than two frozen offers, no still-needed Echo on the board. |
| Counter increment | `core/AutomationRuntime.lua`, after a confirmed `Adapter.Reroll()` | Keyed to the reason string `bracket fishing: reroll filler guarantee`. The Pilot never returns that reason, so `bracketSpent` stays 0 and `consecutive` is set to 0. |
| User setting | `data/DefaultProfile.lua` `autoReroll`, commands `/nexus reroll on|off` | Effective: it becomes `allowReroll` and `searchRefused.reroll`, and the action executor checks it again. There is no setting for a count, a bracket limit or a reserve. |
| Current user-facing text | `ui/Help.lua` "Rolling and settings", `README.md`, in-game changelog | No limit or reserve is promised. Help says: "Reroll asks for new choices when enabled." |
| Historical text | `CHANGELOG.md`, 1.19.2 Dev Test 13 | "maximum 3 consecutive rerolls against the same unwanted guaranteed Echo and 4 rerolls per level bracket", "Preserves 5 rerolls for later brackets until level 78". This describes the guarantee-based bracket fishing. |
| `core/UserText.lua` | mapping for the old reason string | Display only. |
| Test adapter | `tests/prototype/policy_adapter.lua` | Passes a fixed `rerollBudget`, as the runtime does. No test asserts that the ration limits a Pilot Reroll. |

Conclusion: no current setting or text promises a Reroll ration. The ration was
part of the guarantee-based model. The intended resource policy for the current
planner cannot be determined from current decisions. R4 therefore changes no
behaviour. The fields stay as they are. The open question is in the delivery
report: retain (enforce in one action-eligibility boundary, count confirmed
Rerolls, state the limits in Help) or retire (remove the dead fields and
counters; the permission and the server charge count stay the only limits).
R3 makes this question more relevant, because R3 spends Rerolls in more states.

## Orb-offer redraw: investigation only

Question: does the repository hold evidence of a supported action that redraws
an open Orb offer, with its cost and its confirmation contract?

| Source examined | Finding |
|---|---|
| `core/OrbAdapter.lua` capability probes | Required `OrbService` members: `IsStateKnown`, `GetCharges`, `IsOfferPending`, `ConfirmSpend`, `RequestCharges`. Required `PerkService` members: `GetGrantedPerks`, `GetLockedPerks`, `GetCurrentChoice`, `SelectPerk`, `RequestGrantedPerks`. Optional: `GetDiscoveredEchoes`, `IsTomeEchoDisabled`. No redraw member is probed or called. |
| `core/OrbRuntime.lua` | One spend is `ConfirmSpend(sourceId, 1)`. A changed pending offer is treated as ambiguity ("The pending Orb offer changed unexpectedly") and pauses. |
| `docs/ORB_MEMORY_MODE.md`, `docs/P1_5_1_CORRECTIONS.md` | Describe spend, offer, select, confirmation. No redraw action. |
| `tests/prototype/orbs_support.lua` and the `orbs_*` tests | The mocked `OrbService` has the five members above only. |
| Supplied third-party reference used by `orbs_policy` (`Memory/MemoryMode.lua`) | Its one use of the word "redraw" means a result with the same spell ID as the source. It has no offer-redraw call. |
| `PerkService.RequestReroll` | This is the ordinary-board Reroll. The ordinary gate blocks it while an Orb offer is pending. It is not evidence of an Orb-offer redraw, and it must not be used as one. |

Result: unavailable from the repository's evidence. Exact missing capability:

1. The name and signature of the client call that redraws an open Orb offer
   (service, function, arguments).
2. Its cost contract: an authoritative one-Orb (or other) charge change that the
   client reports for that call, and its refusal and failure answers.
3. Its confirmation contract: evidence that a *new* offer generation replaced
   the old one for the *same* owed operation (the current API exposes no offer
   ID or generation; `boardKey` equality cannot tell a redraw from an unrelated
   offer), with unchanged rolled and permanent ownership and an unchanged
   owed-offer count.
4. Whether any quality boost carries over to the redrawn offer. Nothing in the
   repository supports an assumption either way.

Until a supported client supplies items 1-3, Nexus keeps the current behaviour:
an offer change during a pending operation is ambiguity, not a redraw. No test
for a redraw action was prepared, because no established interface exists to
test against. This investigation does not block R1 or R2.
