# Pending design decisions

**First-slice direction: the player chooses the exact Wishlist.** Automatic
resolution and pool sharing are deferred. Other choices below remain pending
unless explicitly identified as this selected scope. These documents prepare
[#47](https://github.com/Viscerals/Better-Nexus/issues/47); they do not accept a
schema, algorithm, API or implementation plan. The
[current boundaries](BOUNDARIES.md) constrain every option. No option authorizes
new actions, storage or sharing merely by appearing here.

The separately scoped first ordinary model now implements the
[player-choice public seam](PLAYER_CHOICE_SLICE.md) in session memory only.
Its routine module/API and technical bounds do not select a durable pool
schema, full UI, locked-target interaction or any automatic resolver.

## Decision table

| Decision | Options for maintainer consideration | Evidence or question needed before selection |
| --- | --- | --- |
| Entity and language | A separately named planning document, a build pool, or another explicitly distinct concept. | Which user intention does it represent, and how is it unmistakably different from an exact Wishlist in UI and diagnostics? Name remains undecided. |
| Desired copies and quality | Exact desired variants/counts; explicit acceptable variant groups; or another declared alternative relation. | Define whether alternatives replace each other or are cumulative quotas. Define role, exact spell ID and quality effects; do not silently reuse existing family/quality progress with changed meaning. |
| Preference and substitution | User ordering, explicit priority groups, explicit substitution choices, or a narrower initial subset. | Resolve ties/conflicts and unavailable catalog entries without fabricating equivalence or claiming future offers. Selection rule remains undecided. |
| Pool size and work bounds | Explicit storage limits; larger retained collections with bounded projections; or a smaller initial feature. | Choose concrete limits and worst-case work/memory evidence before implementation. “More than 79 alternatives” neither specifies a maximum nor proves uncapped storage safe. |
| Exact-target resolution | **Selected for the first slice: the player explicitly selects the exact target.** Nexus does not propose or rank a target. | The technical contract must preserve the player's exact choice and existing validation, refusing unsupported selections rather than trimming or substituting them. No automatic resolver is selected. |
| Stability during a run | Hold an approved resolution; permit explicitly requested re-resolution; or another documented lifecycle. | Define what changes invalidate a resolution and whether changing catalog/ownership observations may affect it. Avoid silent target changes; exact behavior remains pending. |
| Local/shared ownership | **First slice is local; pool sharing is deferred.** Later shared/fork behavior remains undecided. | Define local persistence/edit identity before wiring storage. No identity format or migration is selected; a session-only technical milestone must say that it does not persist a pool. |
| Sharing eligibility | **Deferred for the first slice.** Later exact-result sharing or a distinct pool exchange remains undecided. | No new sharing or Sync path is enabled. A pool cannot masquerade as an exact Community/Sync loadout. Any later exchange needs separate compatibility and trust review. |
| Presentation and diagnostics | Distinct labels and status on a later UI; explicit resolved/unresolved explanation; or a narrower non-actionable planning view. | Specify how users identify the pool, exact result and current assignment without implying ownership, completion or assignment from a name. No UI layout is selected. |

The issue's [current comment](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
identified entity, resolution and Sync eligibility as missing at that snapshot.
The player-choice direction above now narrows the first slice; the comment's
units correction still qualifies the older 6/85 wording. This does not settle
the other design rows or authorize a new storage, action or sharing path.

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
