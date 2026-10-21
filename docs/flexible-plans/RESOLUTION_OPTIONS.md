# Pending design decisions

**All choices below remain PENDING.** They are preparation for
[#47](https://github.com/Viscerals/Better-Nexus/issues/47), not an accepted
architecture, schema, algorithm, API or implementation plan. The
[current boundaries](BOUNDARIES.md) constrain every option. No option authorizes
new actions, storage or sharing merely by appearing here.

## Decision table

| Decision | Options for maintainer consideration | Evidence or question needed before selection |
| --- | --- | --- |
| Entity and language | A separately named planning document, a build pool, or another explicitly distinct concept. | Which user intention does it represent, and how is it unmistakably different from an exact Wishlist in UI and diagnostics? Name remains undecided. |
| Desired copies and quality | Exact desired variants/counts; explicit acceptable variant groups; or another declared alternative relation. | Define whether alternatives replace each other or are cumulative quotas. Define role, exact spell ID and quality effects; do not silently reuse existing family/quality progress with changed meaning. |
| Preference and substitution | User ordering, explicit priority groups, explicit substitution choices, or a narrower initial subset. | Resolve ties/conflicts and unavailable catalog entries without fabricating equivalence or claiming future offers. Selection rule remains undecided. |
| Pool size and work bounds | Explicit storage limits; larger retained collections with bounded projections; or a smaller initial feature. | Choose concrete limits and worst-case work/memory evidence before implementation. “More than 79 alternatives” neither specifies a maximum nor proves uncapped storage safe. |
| Exact-target resolution | User selects the exact target; a deterministic rule proposes one for explicit approval; or another separately specified resolver. | Specify complete inputs, failure/ambiguity behavior and how the output meets current exact-target contracts. No algorithm is chosen here. |
| Stability during a run | Hold an approved resolution; permit explicitly requested re-resolution; or another documented lifecycle. | Define what changes invalidate a resolution and whether changing catalog/ownership observations may affect it. Avoid silent target changes; exact behavior remains pending. |
| Local/shared ownership | Local-only plans; immutable shared source plus local fork; or mutable local copy with explicit provenance. | Define edit identity, provenance, conflict behavior and unknown-field preservation. No identity format or migration is selected. |
| Sharing eligibility | Defer sharing; share only an independently validated exact result through existing rules; or design a distinct compatible pool exchange. | Resolve whether pools are Syncable at all. A new pool cannot masquerade as an exact Community/Sync loadout. Any distinct exchange needs separate compatibility and trust review. |
| Presentation and diagnostics | Distinct labels and status on a later UI; explicit resolved/unresolved explanation; or a narrower non-actionable planning view. | Specify how users identify the pool, exact result and current assignment without implying ownership, completion or assignment from a name. No UI layout is selected. |

The issue's [current comment](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
explicitly leaves entity, resolution and Sync eligibility missing. It also
qualifies the older 6/85 wording. Acceptance of these preparation documents
does not select any table row or remove those dependencies.

## Existing meanings that an option must explain

The compiled `plan` already has exact requested-copy and role projections in
[`Strategy.Compile`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/Strategy.lua#L106-L147).
Its presence does not answer the distinct-entity question. Existing
[`Model.TargetProgress`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/Model.lua#L402-L435)
and [`OrbPolicy.Normalize`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/OrbPolicy.lua#L8-L24)
retain exact quality, role and authored-target constraints. Alternatives must
not become additional owned copies, duplicate fulfillment or a bypass around
those checks.

A future contract must define what “same input, same resolution” means before
determinism can be tested: which accepted pool revision and catalog/context are
inputs, which facts may be unknown, and what stable identity an exact result
has. This document deliberately supplies no serialized fields, revision model,
sorting rule, scoring function or action integration.

## Decision record required for a later slice

For each selected option, record the accepted meaning, rejected alternatives,
compatibility impact and discriminating acceptance scenarios. Use the repository
[domain-documentation rules](../agents/domain.md) for any later accepted glossary
or architecture decision; this proposal is neither. Preserve current exact
Wishlist fingerprints, saved-format/unknown-field behavior, action safety and
existing protocol boundaries.

Then select one separately scoped implementation slice with focused controls
and repository-required checks. Native/server facts need the authorized,
versioned evidence appropriate to that later change. Until then, native numeric
budgets, native handling of any proposed representation, storage format and
wire eligibility remain unknown or undecided; no client export or live test
has been performed for this preparation.
