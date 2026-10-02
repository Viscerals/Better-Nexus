# W4: empty locked-target buckets

Status: private fix, offline evidence only. No native test.

## Mechanism (source-confirmed)

Each character row can hold `lockDesignTargetsBySlot[<content key>]`, a legacy sidecar of
locked-Echo targets keyed by the content of a Wishlist (`Adapter.WishlistKey`).

| Where | Before |
|---|---|
| `WishlistController.LockDesignTargets` (the lookup used when a Wishlist is opened: `LoadPendingEchoes`, and by `CommitLockDesignTargets`) | wrote `bucket[key] = {}` when no bucket existed, on every distinct key |
| `CommitLockDesignTargets` (a save) | stored the new design under the saved content key even when the design was empty |
| removal | none: no code path deletes a bucket |

So every distinct ordinary-only Wishlist content that was opened or saved left a permanent
empty bucket in the saved profile. Reopening known content adds nothing; editing and saving
(or importing) new content adds one per distinct content.

## Reproduction (`w4-013/repro_w4.lua`, `repro_w4_store.lua`, `tests/prototype/lock_bucket_growth.lua`)

Owner-normal workflow only: open or save ordinary-only Wishlists of different content.

| Run | Before | After |
|---|---|---|
| 60 distinct ordinary-only opens (injected store) | 60 empty buckets | 0 |
| 10 / 100 / 500 / 2000 opens, real Store | 10 / 100 / 500 / 1777 persisted empty buckets (content collisions explain the last count), serialized 692 / 6,885 / 34,418 / 122,391 bytes | 0 buckets, 2 bytes |
| 20 save cycles | +20 empty buckets | 0 |

Cost: memory and saved-file size grow by the bucket key plus a few bytes. Measured: about 69
serialized bytes per bucket for the 7-entry test contents (key about 52 bytes), and the content key
of a full 85-entry Wishlist is 764 bytes. CPU per open stays small (about 0.01
to 0.02 ms offline). **No limit is claimed.** The 4096 bound in the migration reader
(`CharMigration.BOUNDS.mapEntries`) counts character rows, not these buckets, and no
write refusal, data loss or start-up failure was demonstrated.

## Repair

A lookup never creates a bucket. With no committed design it answers a fresh empty table that
is not stored; callers (`ApplyCommittedTargets`, `PlanLockCommit`) only read it. A save stores a
design only when it has targets, and still never replaces an existing bucket. The one-time
move of the retired flat account table `lockDesignTargets` under the current key is unchanged.
Opening or saving in a read-only saved root still writes nothing.

One behavior change besides the growth: the content key covers the rolled copies only, so opening
ordinary-only content K and later saving the same rolled content WITH locked targets used to find the
empty bucket and DROP those targets from the sidecar (they were stored only when the content had not
been opened first). The targets are now stored in both orders. Assigned Wishlists carry their own design
on the assignment and are unaffected; the sidecar is read when a Wishlist has no assignment design.
The user designed those targets in that save, so the new result matches the first-time-save result.
Keys that already have an empty bucket keep the old rule. A test pins this
(`lock_bucket_growth`, "same key").

Not done on purpose: no pruning or deletion of existing buckets (empty or not), no migration,
no other change to locked-role semantics, assignment identity, shared-build or Sync data.

## Behavior notes

- Readers treat an absent bucket as no committed design (the state of every Wishlist that was
  never opened). Assigned Wishlists carry their own design on the assignment and are unaffected.
- Auto locked-slot logic (`TryAutoLock`) on a Wishlist with no persisted bucket reports
  "table missing" and does nothing, as for any never-opened Wishlist. Before this change, opening
  such a Wishlist once created an empty bucket, after which that logic ran with zero targets and
  also superseded attempt records not belonging to its targets (`target_changed`). Those records are
  now left unchanged while the bucket stays absent: the step returns before its confirmation-timeout
  and reconciliation code runs, so nothing expires or supersedes them in that time. When a target set
  is next evaluated, matching records reconcile or expire as usual and records outside that set are
  superseded. Keeping them is the more conservative direction (a pending record blocks a duplicate
  attempt). Neither an absent nor an empty bucket sends a lock or unlock without targets. Existing
  empty buckets keep their old behavior.
  The transition is pinned offline, with the real runtime and Store and counted adapter sends, by
  `auto_lock_absent_empty_bucket` (added after the W4 review). Offline harness only: it does not
  confirm native LockPerk or UnlockPerk behavior.
