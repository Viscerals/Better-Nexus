# W3: legacy Saved Build assignment upgrades are written only to a detached snapshot

Status: characterization and design options. No product change. Offline evidence only.

## Mechanism (reproduced on `20b5a10`)

Saved data can still hold two old shapes of `loadoutWishlists[slot]`: a bare designed-slot number
(1.0.5) and a table with a slot but no content key. `GameAdapter`'s `ResolveAssociation` recognizes
each on its first validated contact with a current server Wishlist and assigns the identity
(`links[slot] = {slot, key, name}`; `saved.key, saved.name = ...`) on the table it read from
`Store.State()`. Its comment promises that this persists "a content identity so a recycled server
slot can never resurrect an unrelated historical name". `Store.State()` returns a detached copy
(`core/Store.lua`, "a caller mutating it cannot reach durable state"), so neither assignment reaches
authoritative state. The 32 former write-through sites were migrated to `UpdateStateV1`; these two
were not.

## Authority proof (`tests/prototype/legacy_assignment_snapshot.lua`, 34 checks)

State is read from the saved table (`NexusDB`) after owner writes and after a serialize / reload
round trip, not from the snapshot alone. Seeded through `UpdateStateV1`, Saved Build 1 -> slot 101
(Wishlist A, Echo 200003), both shapes:

| Step | Saved table | Snapshot |
|---|---|---|
| seeded | legacy shape | legacy shape |
| after `GetLoadoutWishlistState`, `GetLoadoutWishlist` | byte-identical (read-only contract holds) | |
| after `Wishlist()` resolves A | still legacy | `{slot, key, name}` (upgraded) |
| after an unrelated authorized write | still legacy | legacy again (the upgrade is gone) |
| slot 101 reused by Wishlist B (Echo 200004), same session | | target resolves to **B** |
| serialized, reloaded, slot 101 holds B | still legacy | target resolves to **B** |

Contrast (same test): an association made by an explicit action carries a content key and an
assignment id in the saved table, and after a reload a reused slot does not capture it. Unassign
removes a record of either shape.

So the "upgrade" is lost, and the stale binding is real: a legacy association follows whatever
Wishlist occupies its slot number. It needs data from an old version (current code always writes a
keyed record), slot reuse, and no explicit assignment or save since. An explicit assign, an editor
save or Unassign replaces or removes the legacy record and ends the exposure. Repeated work: each
resolution revalidates against the candidate list and never converges; its cost was not measured.

## Why the obvious fix is not made here

The upgrade has to be persisted through the state owner with a compare-and-set against the original
record (a newer explicit choice must not be overwritten). The question is *where*. Every resolution
site is a read path:

| Option | Where | Covers | Cost / risk |
|---|---|---|---|
| A | `A.Wishlist()` on the active slot, beside the existing first-run hand-off write | the active slot | One Store mutation in the first `A.AssignedWishlist()` call that meets a legacy record (measured in a throwaway prototype: calls 1/2/3 = 1/0/0 mutations, baseline 0/0/0). `tests/prototype/hud_assignment_reads.lua` states the contract "one read enters no Store mutation, in every assignment state" (test.9053 HUD cost). With this test's expectations flipped the prototype passes: durable record upgraded, no capture by B in the same or a later session |
| B | the Journal getter `GetLoadoutWishlist` | slots the Journal shows | a UI read that writes; breaks the read-only getter contract this test pins |
| C | the adapter's own Echo reconciliation (notification / five-second fallback) when the slot mirror becomes known or changes: one bounded pass over `loadoutWishlists`, compare-and-set per slot | all legacy slots at once | not a getter, but a new mutation point in a path with cost budgets and no mutation today; arguably a migration-policy decision |
| D | leave it; the upgrade happens when the player assigns, saves or unassigns | | no change; the exposure above remains for never-reassigned legacy links |
| E | readiness-time migration | | the slot mirror is often unknown then, so it cannot validate; needs a retry trigger, i.e. option C |

Recommendation: C if an owner decision accepts a new mutation point in reconciliation (one pass,
only when a legacy shape is present, compare-and-set, no ownership or catalog changes); otherwise D
with the risk accepted. A is not recommended: it conflicts with an explicit HUD read contract. This
task does not choose, because the choice is an architecture rule (where authorized mutations may be
triggered), not a local defect fix.

## What the test pins and how to change it

`EXPECT = {durableUpgraded=false, followsReusedSlot=true}` states what is true today. A correction
flips both and changes the check "the saved table is still the legacy shape after resolution" to the
chosen boundary's timing. The invariant that stays under any correction: the getters leave the saved
table byte-identical. Mutation controls (evidence files `MUTANT-*.txt` and `PROTOTYPE-A.diff` in the
W3 evidence directory, outside the repository): a getter that persists the upgrade turns the test
RED; the option-A prototype turns it RED until the expectations are flipped.

Not done on purpose: no inference of owners, no relaxation of ownership, no recovery of old
catalogs, no reset, no wider migration, no change to `Store.State()`.
