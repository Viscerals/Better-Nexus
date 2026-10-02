# W3: legacy Saved Build assignment upgrades were written only to a detached snapshot

Status: private fix, offline evidence only. No native test.

## Mechanism (reproduced on `20b5a10`)

Saved data can still hold two old shapes of `loadoutWishlists[slot]`: a bare designed-slot number
(1.0.5) and a table with a slot and no content key. `GameAdapter`'s `ResolveAssociation` (reached from
`A.Wishlist`, `A.GetLoadoutWishlist` and `A.GetLoadoutCandidates`) recognized each on its first
validated contact and assigned the identity (`links[slot] = {slot, key, name}`; `saved.key,
saved.name = ...`) on the table it read from `Store.State()`. Its comment promised that this persists
"a content identity so a recycled server slot can never resurrect an unrelated historical name".
`Store.State()` returns a detached copy (`core/Store.lua`: "a caller mutating it cannot reach durable
state"), so neither assignment reached authoritative state. The 32 former write-through sites were
migrated to `UpdateStateV1`; these two were not. No other path upgrades these shapes (`EnsureStateShape`
only creates empty subtables; the saved-format and legacy-migration code does not touch the field), and
current writers always write a keyed record, so the shapes exist only in data from older versions.

Authority proof (`tests/prototype/legacy_assignment_snapshot.lua`, state read from the saved table
`NexusDB` after owner writes, after the poll and after a serialize / reload), before the fix, both shapes:
the saved table stayed legacy through resolution and through an unrelated authorized write, the snapshot's
upgrade vanished at the next invalidation, and a slot 101 reused by another Wishlist captured the
association in the same session and, after a reload, in the next one. An association made by an explicit
action carries a content key and an assignment id and is not captured. An explicit assign, an editor save
or Unassign replaces or removes a legacy record. Each resolution also revalidated and never converged;
that cost was not measured.

## Repair

`ResolveAssociation` now only recognizes the legacy shapes and no longer writes to the detached copy.
`ReconcileLegacyAssignments` persists the identity through the state owner. It is not a getter: it runs
from `A.Poll`, beside `ReconcileTomePending`, which is the existing poll-time owner mutation it follows.

- It enters the mutation entry only when a legacy record is present (a cheap check of the cached
  snapshot first), and tries again only when the slot mirror has changed.
- It upgrades only what the live mirror shows at that record's slot now, which is the validation the
  resolver already applied, and only a bare slot reference: a number, or a table with a slot and neither a
  content key nor contents of its own nor an assignment id (a plan saved before content keys carries an
  identity of its own and is left alone).
- Inside the transaction it re-checks that each record is still the legacy shape it read, so a newer
  explicit choice is never overwritten. It stamps no assignment id, does not call `Wrote`, and leaves
  first-run, locked designs, modern records and records whose slot shows nothing as they are.
- It does nothing under the passive-diagnostic write block, and a read-only saved root refuses the write
  as for any mutation.

Unchanged: the read-only getters (the test asserts the saved table is byte-identical after them), the
HUD read (`A.AssignedWishlist` still enters no Store mutation), first-run, locked roles, Unassign and
Restore (an upgraded record keeps its identity through both), binding tokens, and the W15 and W16 guards.

## Options considered

| Option | Where | Why not |
|---|---|---|
| A | `A.Wishlist()` on the active slot, beside the first-run hand-off write | measured in a throwaway prototype: the first `A.AssignedWishlist()` that meets a legacy record enters one Store mutation (calls 1/2/3 = 1/0/0). The HUD read test (`hud_assignment_reads.lua`) lists its states without a legacy one and states the cost contract (no mutation per read); a one-time write has the hand-off precedent, but it adds a mutation to the HUD read path |
| B | the Journal getter | a read that writes; breaks the read-only getter contract the test pins |
| C (chosen) | poll-time reconcile | not a getter or the HUD; follows `ReconcileTomePending`; covers every legacy slot the mirror validates |
| D | explicit actions only | leaves never-reassigned legacy links exposed |
| E | readiness-time migration | the mirror is often unknown then; needs a retry trigger, i.e. C |

## Limits

- The identity recorded is the occupant of the slot at first contact. If the slot was reused before
  the upgrade ran, the record binds the new occupant; nothing in the saved data can say otherwise.
  The poll runs within a fraction of a second of the mirror becoming known, which narrows this window
  but does not remove it.
- A record whose slot never shows a Wishlist stays legacy (and keeps slot-number semantics) until it does.
- Unassign of a keyless table that is still legacy keeps it as it is in the removal list (a bare number
  is not retained); Restore returns that shape, and the poll upgrades it when the mirror validates it.
- Offline only. Native persistence of the upgrade across a real reload is untested.
- Not done on purpose: no inference of owners, no relaxation of ownership, no recovery of old catalogs,
  no reset, no wider migration, no change to `Store.State()`.
