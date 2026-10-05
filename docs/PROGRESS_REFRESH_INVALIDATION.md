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
| rejected | `rejected:<reason>` plus the raw source's shape | moves into, within (inside the reading limits below) and out of rejection when the source changes; not on identical repeats |

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
- The raw reading is bounded while it is made (`RawShape`): keys are counted as they are collected
  and nothing over the limit is sorted; a string is measured before it is copied; the size is checked
  before every append. A source deeper than 8 table levels, with more than 20000 tables, keys and
  values, larger than 262144 bytes, holding one string longer than 1024 bytes, or containing a
  cycle reads `unreadable` as a whole field. Identical over-limit sources give the identical
  reading (no generation churn); a change of an over-limit source is NOT tracked until the source is
  back within the limits, and then it is read again (the generation moves once). Supported mirrors
  are well inside the limits: a 15-row, 85-Echo slot mirror reads about 73 KB in about 13000
  entries; an over-limit source is refused after at most the limit's work (`echo_raw_shape_bounds`).

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
`tests/prototype/echo_raw_shape_bounds.lua`: wide, long-string, many-string, deep and cyclic raw
sources against the limits above (largest sort, heap growth, reading size), over-limit idempotence and
recovery through the real reconciliation, and no ownership change; it fails on 19ac830, whose
first `RawShape` collected and sorted every key before its part limit applied.

Not changed: ordinary and locked roles, the ownership getters and their trust rules, the strict
fingerprints themselves, granted refresh requests (none added), and the planner.
