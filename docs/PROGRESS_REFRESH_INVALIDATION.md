# Progress refresh: rejected Echo fields and static fallback invalidation

Status: offline evidence only. No native test. These two defects reproduce the reported shape
("HUD stays 40/79 after a loadout switch, a reload shows 35/79") in the synthetic harness; whether
either one caused the native report is not established.

## D1: one rejected Echo field froze every generation

`GameAdapter.ReconcileEchoState` fingerprints five client mirrors (slots, granted, locked,
discovery with the disabled levers, active slot) with strict validation. Any rejected field made the
whole capture fail before any generation moved. The getters (`Owned`, `Slots`, `LockedOwned`) are
lenient and stayed fresh, but every reader keyed on the generations (the runtime's projection cache,
the HUD panel progress cache, the Wishlist overlay, the Journal association refresh) kept its last
accepted reading as current until a reload. The five-second fallback also ran a full repair step every
five seconds while it lasted.

Now each field is checked on its own (`CaptureEchoSnapshot`):

| Field state | Snapshot value | Generation |
|---|---|---|
| accepted | the strict fingerprint, as before | moves when the fingerprint changes |
| rejected | `rejected:<reason>` plus the raw source's shape | moves into, within and out of rejection when the source changes; not on identical repeats |

- A rejected field is never accepted and never stands for the last accepted one. Its raw shape is
  change evidence only; no reader takes ownership, roles, slots or confirmation from it. Every reader
  still uses its own getter with its own, unchanged rules.
- The snapshot confirms ownership only from an accepted granted mirror (its rule is unchanged); a
  rejected one leaves the confirmation state as it is. The ownership getter `Owned` keeps its own,
  unchanged confirmation rule.
- `EchoReconcileStats().rejected` reports the current verdict (field -> reason); `failures` counts scans
  that rejected any field; `lastReason` names them.
- The Orb read context gets no active-slot generation while the active slot itself is rejected
  (`EchoActiveSlotGeneration`), as when the reconciliation failed before.
- Legacy assignment upgrade (`docs/W3_LEGACY_ASSIGNMENT_UPGRADE.md`): absence is certified only while
  the slots field is accepted.
- A raw source deeper than 8 levels or larger than 100000 parts reads `unreadable` and stops tracking
  further change until it is readable again.

## D2: an assigned-Wishlist change could be missed by the static fallback

The runtime caches the assigned Wishlist and its plan in a static context, rebuilt on a dirty slot
notification or when the five-second fallback finds a static mismatch. Three links let a change be
missed for good; each is repaired:

1. A notification consumed by a non-dirty reader (the Orb read context) lost its dirty marking. It now
   keeps it (`ReconcileEchoState`: `markDirty or hadPending`).
2. Every full step advanced the fallback baseline of the slots and active-slot generations, also when the
   step did not rebuild the static context. Only the dynamic generations are advanced now
   (`AdvanceFallbackDynamicBaseline`); the static ones move only with a static rebuild.
3. The fallback classified only its first mismatched field, so a dynamic one listed earlier (granted,
   locked) hid a static one listed later (association). Any static mismatch now rebuilds the static
   context (`FallbackNeedsRepair`).

## Tests

`tests/prototype/echo_snapshot_rejected_field.lua` and `tests/prototype/fallback_static_invalidation.lua`
(shared fixture `progress_refresh_support.lua`): notified, silent and consumed notifications; four
mismatch orderings; HUD against the fresh getter; overlay and Journal; no minted confirmation from a
rejected granted mirror; no repeated work on repeated rejections or in steady state; recovery; locked
roles fail-closed. Both fail on the code before this change.

Not changed: ordinary and locked roles, the ownership getters and their trust rules, the strict
fingerprints themselves, granted refresh requests (none added), and the planner.
