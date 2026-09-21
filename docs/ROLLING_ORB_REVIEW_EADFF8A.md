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
