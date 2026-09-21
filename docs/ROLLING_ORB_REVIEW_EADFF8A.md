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
`orb_review_reload_no_observer`, `orb_review_reload_rejected_selection`.
