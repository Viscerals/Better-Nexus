# Player-choice first slice

**Ordinary model accepted; session chooser integration implemented for focused offline review; full feature incomplete.** For the first version of
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

## Session chooser integration

The Wishlist Editor's **Plan alternatives** button opens an ordinary planning
pool. Players add exact catalog IDs, then explicitly Set each chosen count;
zero leaves a member unchosen. Membership, catalog filtering, scrolling and
reopening never select results. Two fixed sets of 12 visible row frames use
`VirtualList.Window`. The pool holds at most 256 alternatives; an explicit
choice still holds at most 79 ordinary copies and respects each captured stack
bound. Exact variants and ordinary IDs currently held locked remain ordinary.

The pool and choice live only in session memory. Hide/reopen retains them;
Reset clears only this planning session; reload loses them. No pool schema,
SavedVariables migration or persistent entity is added.

**Open as new Wishlist draft** validates the complete model result and detaches
it before replacing anything. `WishlistController.PrepareNewExactDraft` returns
a single-use install intent, without changing the current draft or its active
save confirmation. Required chosen ID/quality/maxStack/group facts and the
ordinary source role are checked against the existing catalog projection on
preparation and again on confirmation; unavailable or changed facts refuse.
Display-name changes do not reinterpret the exact selection.

A current draft, name or destination/edit context requires an in-product
replacement confirmation with Cancel. Cancellation, refusal or a stale editor
or planning context preserves the previous editor. The installed new context
contains exactly the chosen pending ordinary rows, empty locked/fulfilled and
retained-design maps, and no stale candidate, save/retry or confirmation identity.
Its seeded draft cannot auto-load an earlier Wishlist on refresh. Save remains
a distinct subsequent player action; this handoff uploads, saves, assigns,
shares and spends nothing.

The synthetic `flexible_plan_editor_handoff` fixture boots production modules,
drives real entry/Add/Set/Open/Cancel callbacks, compares 100 alternatives and
the explicit last 79 choices with an ordinary manual control, and covers
catalog/schema/count refusals, detachment, same-family variants, held locks,
stale confirmations, the 256/257 bound and session lifecycle. This is focused
offline evidence. Final full CI, package validation and independent Spec and
Standards review belong to the integration owner. Native UI validation is
NOT_RUN; no exact versioned client/export reference was available locally.

## Deliberate limits

The accepted model remains unchanged and frame-free. The integration uses
existing editor UI conventions and catalog projections, with no new refresh,
game-service, save/assignment, automation, resource-action or sharing route.
Session-memory retention does not satisfy the issue's reload/persistence goal.

Persistence format, durable pool identity/edit/fork/migration, grouped choices,
priorities/substitution/ties, locked planning pools and sharing remain deferred.
The full issue remains open and is not scheduled for public release by this
slice.

The [boundaries](BOUNDARIES.md) and [future acceptance matrix](ACCEPTANCE_MATRIX.md)
continue to apply. The focused synthetic fixture exercises the real
production-loaded public model and existing exact draft operations. It is not a
native UI, persistence, server, sharing or resource-spending proof. Final
full-suite/package checks and independent review remain separate acceptance
gates.
