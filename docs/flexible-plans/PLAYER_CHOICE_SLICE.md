# Player-choice first slice

**First ordinary model implemented for offline review; full feature incomplete.** For the first version of
[#47](https://github.com/Viscerals/Better-Nexus/issues/47), the player chooses the
exact Wishlist from a broader local planning pool. Nexus does not propose the
result. Automatic resolution, priority/substitution/tie rules and pool sharing
are deferred. Existing exact Wishlist limits and safety checks remain unchanged.

## First technical milestone

A small, frame-free model supports a bounded pool containing more than
79 ordinary alternatives and a separately supplied, explicit player selection.
It produces a detached exact Wishlist draft through existing model operations.
It preserves selected spell IDs, catalog quality and explicit copy counts or
refuses the request; it does not choose, trim, rank or substitute rows.
Pool membership is not ownership, completeness, assignment or action authority.

The conservative first model handles ordinary targets only and refuses
role-tagged planning input. It does not change existing locked Wishlist support
or limits on held locked evidence. Its 256-alternative bound is a technical
allocation/admission choice, not a native/server rule or a requirement for every
later pool representation.

## Public model boundary

`Nexus.FlexiblePlanModel.New({alternativeSpellIds=ids, catalog=snapshot})`
accepts 1–256 distinct exact catalog IDs in a dense plain array. The supplied
catalog and its rows must be plain tables with finite valid ID, quality and
stack-bound facts. Required scalar facts are copied; optional names are bounded
to 256 bytes. No game getter or refresh obtains or verifies that snapshot.

The returned session facade has two dot-call methods:

- `Alternatives()` returns detached catalog-derived row copies in input order.
  That order is not a priority or a recommendation.
- `Choose(selection)` takes a whole explicit dense list of `{spellId, stacks}`
  rows: distinct pool members, explicit positive integer counts, at most 79
  ordinary copies and no count above its captured catalog bound. It returns
  fresh `pending`, empty `pendingLock`/`fulfilledTargets`, and canonical ordinary
  `echoes`, or `nil` plus a fixed refusal code. Each call supplies the entire
  choice; no previous winner is remembered. A whole explicit choice can be a
  partial Wishlist draft and is never a claim of complete ownership.

Role fields are not accepted in this ordinary-only input, even if false. Sparse,
metatable-bearing, duplicate, nonmember or invalid inputs refuse; caller
metamethods are not invoked. Existing `WishlistModel` exact operations build the
draft, and a canonical row/count comparison refuses any lossy result. The broad
pool never goes through import or captured-evidence normalizers. No fingerprint,
verification, completeness or assignment authority is attached to the result.

## Deliberate limits

The model milestone has no game-service reads, frames, SavedVariables,
save/assignment calls, automation, resource actions or sharing. A detached draft
would not be uploaded or installed into the current editor automatically.
Session-memory retention does not satisfy the issue's reload/persistence goal.

Persistence format, pool editing/identity, visible UI and the explicit handoff
to the existing editor still need separately reviewed integration. Naming a
routine module is an implementation detail; accepting a stored entity/schema
or a new player interaction is not. The full issue remains open and is not
scheduled for a public release by this milestone.

The [boundaries](BOUNDARIES.md) and [future acceptance matrix](ACCEPTANCE_MATRIX.md)
continue to apply. The focused synthetic fixture exercises the real
production-loaded public model and existing exact draft operations. It is not a
native UI, persistence, server, sharing or resource-spending proof. Final
full-suite/package checks and independent review remain separate acceptance
gates.
