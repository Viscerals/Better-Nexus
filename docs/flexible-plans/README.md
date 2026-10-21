# Flexible planning pool: preparation for #47

**Status: the first pure ordinary-target model is implemented for offline
review. Full #47 remains incomplete; no public-beta release is scheduled.**

[Issue #47](https://github.com/Viscerals/Better-Nexus/issues/47) requests a way to
describe a broader pool of acceptable Echoes and priorities when an exact ideal
Wishlist is too restrictive. An alternative pool must remain distinct from an
exact actionable Wishlist. This slice makes the decisions and compatibility
boundaries reviewable. The first slice will let the player choose the exact
Wishlist rather than have Nexus propose one; automatic resolution and pool
sharing are deferred. This direction does not select a storage format or UI.

## Reading order

1. [Boundaries](BOUNDARIES.md): current source facts and invariants to preserve.
2. [Resolution options](RESOLUTION_OPTIONS.md): unresolved decisions, without a
   selected representation or algorithm.
3. [Acceptance matrix](ACCEPTANCE_MATRIX.md): future discriminating scenarios,
   not tests already implemented or passed.
4. [Player-choice slice](PLAYER_CHOICE_SLICE.md): the selected direction, public
   model boundary and explicit limits of the first technical milestone.

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
At that pre-implementation base, no generalized alternative-pool entity or resolver was found in those paths,
the production TOC module list, or the `core/`, `logic/`, `ui/` and `data/` search
for generalized/flexible-plan entity names. This bounded finding agrees with the
issue comment; it is not a native or exhaustive semantic proof of absence.
The new `core/FlexiblePlanModel.lua` is a bounded session-only ordinary model,
not a stored entity or an automatic resolver.

## Decisions required before implementation

The player chooses the exact target for the first slice; Nexus will not rank
alternatives or propose a target. The [options table](RESOLUTION_OPTIONS.md)
records that decision and the remaining limits. Entity wording, count/quality
semantics, storage and work bounds, persistence/edit ownership, and later UI
integration still need a concrete reviewed contract. No automatic resolver,
SavedVariables format or wire format is authorized by the direction alone.

Exact Wishlist behavior, identities, fingerprints, role accounting, action
permissions and safety gates remain unchanged. Never-pick/banish preferences
([#46](https://github.com/Viscerals/Better-Nexus/issues/46)), current correctness
repairs, native troubleshooting, data-provider work, localization and Sync
characterization are outside this slice. No private tester data or proprietary
client code is used here.

## Review and validation status

The production-loaded model has a synthetic public-seam fixture,
`tests/prototype/flexible_plan_player_choice.lua`. It covers explicit selection
from more than 79 alternatives, exact draft controls, refusal, detachment and
no-I/O boundaries. Baseline capability absence and a role-input failure were
retained before their focused passes. Final full-suite/package checks and
independent Spec/Standards acceptance are separate gates; this document claims
neither their completion nor native validation or release. No end-user UI,
persistence, editor handoff or action path is implemented. This milestone does
not close #47.
