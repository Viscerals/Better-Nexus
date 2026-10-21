# Flexible planning pool: preparation for #47

**Status: proposal preparation only. Not implemented, not an accepted design,
and not scheduled for the current public beta.**

[Issue #47](https://github.com/Viscerals/Better-Nexus/issues/47) requests a way to
describe a broader pool of acceptable Echoes and priorities when an exact ideal
Wishlist is too restrictive. An alternative pool must remain distinct from an
exact actionable Wishlist. This slice makes the decisions and compatibility
boundaries reviewable; it introduces no entity, schema, resolver, API or UI.

## Reading order

1. [Boundaries](BOUNDARIES.md): current source facts and invariants to preserve.
2. [Resolution options](RESOLUTION_OPTIONS.md): unresolved decisions, without a
   selected representation or algorithm.
3. [Acceptance matrix](ACCEPTANCE_MATRIX.md): future discriminating scenarios,
   not tests already implemented or passed.

“Flexible planning pool” is a working phrase in these documents. It is not a
runtime type or an addition to the project's accepted domain glossary. The
existing compiled `plan` in `Strategy.Compile` is an exact Wishlist projection;
its name alone does not implement this request.

## Evidence and precedence

Source inspection is pinned to
[`18dc5b0313033dbc522bec1ab89c304078aa5645`](https://github.com/Viscerals/Better-Nexus/tree/18dc5b0313033dbc522bec1ab89c304078aa5645).
The issue's [later units correction](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
and the authoritative opening of [CONTRACTS.md](../../CONTRACTS.md) qualify the
older issue wording about a “79/6/85 game envelope.” Six is an authored
locked-target-copy budget, not a universal cap on held or received locked copies.
Neither that comment nor this local source inspection establishes a numeric
server budget or verifies the current native client.

The inspected source provides exact Wishlist draft operations in
[`WishlistModel.New`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/WishlistModel.lua#L1230-L1264),
exact requested-copy compilation in
[`Strategy.Compile`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/Strategy.lua#L106-L147),
and exact role/quality target normalization in
[`OrbPolicy.Normalize`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/OrbPolicy.lua#L8-L24).
No generalized alternative-pool entity or resolver was found in those paths,
the production TOC module list, or the `core/`, `logic/`, `ui/` and `data/` search
for generalized/flexible-plan entity names. This bounded finding agrees with the
issue comment; it is not a native or exhaustive semantic proof of absence.

## Decisions required before implementation

Maintainers still need to accept the entity and its user-visible meaning,
count/quality/substitution semantics, deterministic resolution and run stability,
storage and work bounds, persistence/edit ownership, and sharing eligibility.
The [options table](RESOLUTION_OPTIONS.md) records these as **pending**. Preparing
these documents does not schedule the feature, choose a preferred algorithm, or
authorize a new SavedVariables or wire format.

Exact Wishlist behavior, identities, fingerprints, role accounting, action
permissions and safety gates remain unchanged. Never-pick/banish preferences
([#46](https://github.com/Viscerals/Better-Nexus/issues/46)), current correctness
repairs, native troubleshooting, data-provider work, localization and Sync
characterization are outside this slice. No private tester data or proprietary
client code is used here.

## Review and validation status

This is documentation and source-reference work only. There is no behavioral
change to test, no new regression implementation, no full-suite result, and no
native validation or release claim. Future implementation needs an accepted
contract, its own focused failing controls and required suite, independent Spec
and Standards reviews, and the existing native/release gates where applicable.
This preparation does not close #47.
