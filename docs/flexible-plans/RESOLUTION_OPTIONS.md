# Design decisions for #47

**First-slice direction: the player chooses the exact Wishlist.** The user
selected this direction. Automatic resolution, priorities, substitution, tie
rules and pool sharing are not part of it. Other choices below remain pending
unless explicitly identified as the selected first-slice scope. These documents
track [#47](https://github.com/Viscerals/Better-Nexus/issues/47); they do not
accept a durable schema, algorithm or wire format. The
[current boundaries](BOUNDARIES.md) constrain every option. No option authorizes
new actions, storage or sharing merely by appearing here.

The selected first slice is implemented for offline review as described in the
[player-choice slice](PLAYER_CHOICE_SLICE.md): a frame-free ordinary model, a
session-only **Plan alternatives** chooser in the Wishlist Editor and a
validated, atomic **Open as new Wishlist draft** handoff. It keeps nothing past
a reload and adds no persistent schema or migration. Its technical bounds do not
select a durable pool schema, locked-target interaction or automatic resolver.
Issue #47 remains open.

## Decision table

| Decision | Options for maintainer consideration | Selected first-slice scope, or evidence needed before selection |
| --- | --- | --- |
| Entity and language | A separately named planning document, a build pool, or another explicitly distinct concept. | **First slice:** a session view labelled **Plan alternatives**, whose result is a new, unsaved Wishlist draft. A durable entity name, and how a persisted pool stays unmistakably distinct from an exact Wishlist in UI and diagnostics, remain undecided. |
| Desired copies and quality | Exact desired variants/counts; explicit acceptable variant groups; or another declared alternative relation. | **First slice: exact spell IDs, catalog quality and explicit ordinary counts.** Same-family variants stay separate exact rows, and role-tagged input refuses. Whether later alternatives replace each other or form cumulative quotas, and any locked-role or grouped-variant meaning, remain undecided; do not silently reuse existing family/quality progress with changed meaning. |
| Preference and substitution | User ordering, explicit priority groups, explicit substitution choices, or a narrower initial subset. | **Outside the current user-selected slice.** No ordering, priority, substitution or tie rule exists; pool order is not a preference. A later rule must resolve conflicts and unavailable catalog entries without fabricating equivalence or claiming future offers. |
| Pool size and work bounds | Explicit storage limits; larger retained collections with bounded projections; or a smaller initial feature. | **First slice: at most 256 session alternatives, at most 79 explicitly chosen ordinary copies within each captured stack bound, and 12 fixed visible rows per list.** These are technical admission and allocation bounds, not native, server or evidence limits. A persisted or larger pool needs its own limits and worst-case work/memory evidence. |
| Exact-target resolution | **Selected for the first slice: the player explicitly selects the exact target.** Nexus does not propose or rank a target. | The model and handoff preserve the player's exact choice and existing validation, refusing unsupported or changed selections rather than trimming or substituting them. No automatic resolver is selected. |
| Stability during a run | Hold an approved resolution; permit explicitly requested re-resolution; or another documented lifecycle. | **First slice:** the choice becomes an ordinary editor draft only through Open, and a changed required catalog fact refuses instead of reinterpreting it. There is no resolution to hold or re-run. A later lifecycle remains pending; avoid silent target changes. |
| Local/shared ownership | **First slice is local and session-only; pool sharing is deferred.** Later shared/fork behavior remains undecided. | Hide/reopen retains the pool; a reload loses it. Persistent pool identity, edit, fork and migration remain unfinished; no identity format or migration is selected. |
| Sharing eligibility | **Deferred for the first slice.** Later exact-result sharing or a distinct pool exchange remains undecided. | No new sharing or Sync path is enabled. A pool cannot masquerade as an exact Community/Sync loadout. Any later exchange needs separate compatibility and trust review. |
| Presentation and diagnostics | Distinct labels and status on a later UI; explicit resolved/unresolved explanation; or a narrower non-actionable planning view. | **First slice:** the chooser shows pool membership and chosen ordinary copies separately and implies no ownership, completion or assignment; the installed draft is unsaved and unassigned. Persisted-pool presentation and diagnostics remain undecided. Native layout is NOT_RUN. |

The [issue comment](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
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

If a later slice adds resolution, its contract must define what “same input,
same resolution” means before determinism can be tested: which accepted pool
revision and catalog/context are inputs, which facts may be unknown, and what
stable identity an exact result has. This document deliberately supplies no
serialized fields, revision model, sorting rule, scoring function or action
integration.

## Decision record required for a later slice

For each selected option, record the accepted meaning, rejected alternatives,
compatibility impact and discriminating acceptance scenarios. Use the repository
[domain-documentation rules](../agents/domain.md) for any later accepted glossary
or architecture decision; this proposal is neither. Preserve current exact
Wishlist fingerprints, saved-format/unknown-field behavior, action safety and
existing protocol boundaries.

Any later slice needs its own scope, focused controls and repository-required
checks; native/server facts need authorized, versioned evidence. For the first
slice no exact versioned client/export reference was available, so native UI,
client loading, pixels, scaling, input, mouse wheel and popups are NOT_RUN and
unverified. Native numeric budgets, durable storage format and wire eligibility
remain unknown or undecided. Offline checks cannot establish native readiness,
full #47 acceptance, release or merge.
