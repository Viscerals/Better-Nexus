# Flexible planning pool: #47 player-choice slice

**Status: the player-choice chooser and exact Wishlist-draft handoff (first
milestone, published with PR #136) and a later local Save/Load of one
planning pool per character (#151) are implemented, with offline evidence
only. Full #47 remains incomplete and
open. These documents claim no merge, release or native validation; native UI
validation is NOT_RUN.**

[Issue #47](https://github.com/Viscerals/Better-Nexus/issues/47) requests a way to
describe a broader pool of acceptable Echoes and priorities when an exact ideal
Wishlist is too restrictive. A planning pool must remain distinct from an exact
actionable Wishlist. The user selected the first-slice direction: the player
chooses the exact Wishlist from a broader local pool. Nexus does not resolve,
rank, prioritize, substitute or break ties, and pool sharing is deferred.

## Current bounded scope

The [player-choice slice](PLAYER_CHOICE_SLICE.md) is the first-milestone
contract. The [local persistence contract](LOCAL_PERSISTENCE_CONTRACT.md)
describes the separate #151 Save/Load extension. In summary:

- The Wishlist Editor's **Plan alternatives** button opens a chooser over an
  ordinary planning pool of at most 256 alternatives. The pool and its counts
  are session work: they are kept only for this session unless the player
  explicitly saves them with **Save pool**, and later edits stay unsaved until
  the next Save pool.
- Membership, catalog filtering, scrolling and reopening select nothing. The
  player explicitly sets each count. A choice holds at most 79 ordinary copies
  and no count above the captured catalog stack bound.
- `core/FlexiblePlanModel.lua` keeps each chosen exact spell ID, catalog
  quality and count through existing `WishlistModel` draft operations, or
  refuses. It never trims, ranks or substitutes; role-tagged input refuses.
- The catalog and pool lists each reuse 12 fixed visible row frames.
- **Open as new Wishlist draft** validates the complete choice and installs it
  atomically through `WishlistController.PrepareNewExactDraft`. An existing
  draft, name or edit/destination context needs an in-product replacement
  confirmation. Cancel, refusal and stale callbacks preserve unrelated editor
  work.
- The chooser and handoff assign, upload, share and spend nothing. Saving the
  new Wishlist draft remains a separate, later player action in the editor.
- **Save pool** and **Load saved** keep one planning pool per character (see
  below). A saved pool is planning state only, not ownership, an assignment
  or permission to act.

Unfinished: durable pool identity, several pools, edit and fork, migration,
locked planning pools and sharing. Broader priority, substitution and tie
decisions are outside the current user-selected slice. #47 remains open.

## Saving the pool on this character

### Saving and loading

- **Save pool** stores this pool and its set counts on this character. It
  replaces the pool saved there.
- **Load saved** brings the saved pool back.
- Nothing is saved or loaded automatically. After a reload the chooser opens
  empty, and it says when a pool is saved.
- **Hide** keeps the pool until reload. **Reset pool** clears only this
  session; the saved pool stays.

### Questions before changes

- A count you typed but did not Set is pending. Save pool waits until you Set
  each edited count.
- Saving an empty pool over a saved one asks first. Cancel keeps the saved
  pool.
- Load saved over unsaved changes or pending counts asks first. Cancel keeps
  your pool.

### Load saved and Open as new Wishlist draft

- These two actions are separate.
- **Load saved** changes only the planning pool. The Wishlist Editor's draft,
  its name and any Wishlist save still waiting stay as they are.
- **Open as new Wishlist draft** builds a new editor draft from the chosen
  counts. Replacing an existing draft asks first, and accepting that
  replacement cancels the earlier draft's waiting save.

### Changed catalog details

- Load saved keeps an Echo's saved details and count even if its catalog
  details changed since you saved. The status says how many Echoes changed.
- Open as new Wishlist draft then refuses, and keeps your pool and counts.
- To use the current details, Remove that Echo, Add it again, then Set its
  count.

### Saved data this version cannot change

- Saved data from a newer Nexus version, or a saved pool this version cannot
  read, is kept unchanged. Save pool and removing the saved pool are refused.
- When the saved data is read-only, Load saved still works and Save pool is
  refused.
- If a save cannot be confirmed, the status says so and never says Saved. Use
  Load saved to see what is stored.

### What this does not do

Saving, loading or removing a pool never assigns, uploads, shares, rolls or
spends. Nexus still chooses nothing for you, and pools are not shared.

The six locked target copies are an authored design budget, not a universal
cap on held or received locked copies and not a server limit.

## Reading order

1. [Boundaries](BOUNDARIES.md): source facts and invariants to preserve.
2. [Resolution options](RESOLUTION_OPTIONS.md): the selected first-slice
   decisions and the decisions that remain open.
3. [Player-choice slice](PLAYER_CHOICE_SLICE.md): the first-milestone model,
   chooser, exact-draft handoff and their deliberate limits.
4. [Local persistence contract](LOCAL_PERSISTENCE_CONTRACT.md): the #151
   Save/Load extension, its saved record, measured bounds and limits.
5. [Acceptance matrix](ACCEPTANCE_MATRIX.md): prospective scenarios for the
   full feature, not tests already implemented or passed.

“Flexible planning pool” is a working phrase in these documents. It names no
persistent entity and is not an addition to the project's accepted domain
glossary. The existing compiled `plan` in `Strategy.Compile` is an exact
Wishlist projection; its name alone does not implement this request.

## Evidence and precedence

Historical source inspection, made before this slice existed, is pinned to
[`18dc5b0313033dbc522bec1ab89c304078aa5645`](https://github.com/Viscerals/Better-Nexus/tree/18dc5b0313033dbc522bec1ab89c304078aa5645).
The issue's [later units correction](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
and the authoritative opening of [CONTRACTS.md](../../CONTRACTS.md) qualify the
older issue wording about a “79/6/85 game envelope.” Six is an authored
locked-target-copy budget, not a universal cap on held or received locked copies.
Neither that comment nor this local source inspection establishes a numeric
server budget or verifies the current native client.

The inspected historical source provided exact Wishlist draft operations in
[`WishlistModel.New`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/WishlistModel.lua#L1230-L1264),
exact requested-copy compilation in
[`Strategy.Compile`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/Strategy.lua#L106-L147),
and exact role/quality target normalization in
[`OrbPolicy.Normalize`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/OrbPolicy.lua#L8-L24).
At that pre-implementation base, no generalized alternative-pool entity or resolver was found in those paths,
the production TOC module list, or the `core/`, `logic/`, `ui/` and `data/` search
for generalized/flexible-plan entity names. This bounded finding agrees with the
issue comment; it is not a native or exhaustive semantic proof of absence. It
remains historical evidence and is not restated as a current-source finding.
The first slice added `core/FlexiblePlanModel.lua`, `ui/FlexiblePlanChooser.lua`
and `WishlistController.PrepareNewExactDraft`; none is a stored entity or an
automatic resolver. The #151 extension adds `core/FlexiblePlanStore.lua`, which
keeps one local per-character pool record through the existing data owner; it
is not a resolver.

## Remaining decisions

The player chooses the exact target for the first slice; Nexus does not rank
alternatives or propose a target. The [options table](RESOLUTION_OPTIONS.md)
records the selected first-slice scope and the open rows. Durable entity
wording, alternative-group semantics, edit/fork ownership, locked planning
pools and sharing still need a concrete reviewed contract.

The local one-pool record and its measured bounds are recorded in the
[local persistence contract](LOCAL_PERSISTENCE_CONTRACT.md). No automatic
resolver, other SavedVariables format or wire format is authorized.

Exact Wishlist behavior, identities, fingerprints, role accounting, action
permissions and safety gates remain unchanged. Never-pick/banish preferences
([#46](https://github.com/Viscerals/Better-Nexus/issues/46)), current correctness
repairs, native troubleshooting, data-provider work, localization and Sync
characterization are outside this slice. No private tester data or proprietary
client code is used here.

## Review and validation status

Two synthetic offline fixtures exercise the first slice's production-loaded
code:

- `tests/prototype/flexible_plan_player_choice.lua` covers the model's public
  seam.
- `tests/prototype/flexible_plan_editor_handoff.lua` drives the real editor
  entry, Add, Set, Open, Cancel and replacement callbacks, refusals,
  detachment, the 256/257 bound and the session lifecycle.

The #151 fixtures, `tests/prototype/flexible_plan_persistence_*.lua`, drive
Save pool, Load saved, Reset and removal through the real chooser and data
owner across serialized module reboots. A module reboot is not a native
reload or login.

All of these fixtures use a synthetic catalog and host. This document records
no test result. Final full-suite and package checks and independent Spec and
Standards review are separate gates; their results belong to the PR evidence
for the exact source pin.

No exact versioned native client/export reference was available. Native UI,
client loading, pixels, scaling, input, mouse wheel and popups remain NOT_RUN
and unverified. Offline tests and source or package checks cannot establish
native readiness, full #47 acceptance, release or merge. This slice does not
close #47.
