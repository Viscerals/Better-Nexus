# P1.6 Journal Unassign rendering correction

This correction follows the native NATIVE-04 report on `test.9014-79e6296`.
It changes presentation only. Assignment, persistence, Sync, and Orb behavior
are unchanged.

## Demonstrated defect

The actual Journal association picker showed its candidate rows and an empty
bottom row. The native getter reported picker frame level 129 and Unassign
frame level 128. The Unassign text was present and shown. Its nonzero bounds
were inside the picker. These observations support the opaque parent covering
the child. They do not establish a universal frame-level clamp in the API.

The source requested parent level 500. Candidate controls had explicit
relative levels, but Unassign did not. The correction keeps the existing
TOOLTIP strata and uses a low parent level of 50. Unassign is explicitly set
to parent + 2 each time the selector opens. The border and candidate controls
retain their relative order. Anchors, dimensions, callbacks, and data remain
unchanged. This uses the same low-level ordering approach as the earlier Help
correction; it requires a native visible-control recheck on the new package.

Alternative explanations were checked by the coordinator before editing:
missing/hidden text would not produce the observed shown text, and collapsed
or out-of-bounds geometry would not produce the measured contained bounds.

## Editor context wording

The native first-run assignment was ready and its exact targets survived
Edit, Save, Close, and reload. The editor's `Assigned to: Not assigned` header
was therefore not evidence of assignment loss. The header describes the
editor's numbered Saved Build context. The Editing menu's CandidateAssignment
lookup also covers populated numbered Saved Builds, not first-run authority.
Local role projections can omit the display-only loadoutName.

The normal header and Editing menu now say `Saved Build:`. An absent numbered
association says `None`. Existing contextual names, including `No Saved Build
selected`, remain supported. This qualifies the scope of the label without
changing identity matching, projections, stored keys, or assignment behavior.
The first-run assignment remains authoritative for main and Orb projections.

## Offline regression boundary

`journal_picker_layers.lua` drives the real Journal picker. It asserts the
Unassign child is above its opaque parent, the low layer band, and candidate
ordering. It exercises reopening, row reuse, numbered and first-run Unassign,
unlinked states, preserved sources/designs, and no added service mutation or
Orb exposure. It reuses the retained real Journal reproduction.

`wishlist_editor_context_label.lua` inspects actual header/menu fontstrings
after the retained real first-run create/reload/edit sequence. It also checks
the numbered handoff and precise Saved Build name. Presentation changes no
durable assignment or service calls.

Both regressions must fail against the previous runtime for their specific
assertions and pass against corrected source and extracted package under the
established LuaJIT route. The 80 prior scripts remain unchanged. Synthetic
frame getters prove ordering intent, not native pixel visibility or hit tests.
Only the coordinator can complete the native recheck using visible controls.
No resource-consuming action is authorized. Orb spending is not tested.
