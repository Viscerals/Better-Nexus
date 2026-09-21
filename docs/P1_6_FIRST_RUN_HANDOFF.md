# First-run picker handoff correction

The independent review rejected `test.9012-eaa2b42`. Its 78-script suites passed,
but an independent actual-handler probe demonstrated a missing lifecycle case.
That candidate, complete FAIL review, exact probe and output remain preserved.
This correction supersedes its incomplete Unassign implementation.

## Demonstration

Actual Journal Create records `assigned:1` in both first-run and slot 1.
Selecting that same source through the real picker records `assigned:2` as the
first-run target but previously left slot 1 at `assigned:1`. Unassign then shows
unassigned at slot 0, but the first populated active Saved Build restores the
old target. Both source and package fail the independent assertion.

The exact review probe is retained byte for byte as
`tests/prototype/assignment_first_run_reselect.lua`. Its baseline replay exits 1.
The SHA-256 is
`d6f56034070354980cba73b89d9c7e9029505a4054bfd1d5e1bd3103e7185346`.

## Correction

The first-run replacement path proves ownership before replacing either record:
the previous first-run record and slot-1 record must have the same nonempty
assignment ID. In that case only, both records receive the complete replacement
and its new assignment ID. The existing selected-source and identity setters use
this path. Unassign uses the same ownership check to remove its own handoff.

False, nil, absent, different-ID and legacy unstamped records cannot establish
handoff ownership. Reassignment does not create a handoff when none exists and
does not change an unrelated slot-1 assignment. Other numbered slots are not
touched. There is no name/content-based migration or automatic damaged-state
recovery. The prior explicit-unassigned marker and unknown-identity restoration
guard remain unchanged.

## Tests and scope

The independent exact probe now passes without edits. A separate companion
regression tests real same/different/repeated picker selection and both setter
routes. It verifies the complete mirrored record, new identity, preservation of
unrelated and legacy records, no handoff creation from nil/false, invalid source
refusal, and zero service mutation. It fails on the rejected candidate.

All 78 prior entry scripts remain unchanged, including direct Unassign,
Create/Edit/HUD, pending operation, budget, Recheck, and Orb safety regressions.
The complete inventory has 80 scripts. Final receipts must cover frozen source
and the extracted replacement through the established LuaJIT route. A fresh
independent review must decide acceptance of the represented offline correction.

Only `core/GameAdapter.lua` changes product behavior. The other changed paths
are two new scripts, the inventory registration and this document. No native
input, installation, live saved data, stock-client source, protocol, gameplay,
or spending route is added. The failed native assignment still needs deliberate
supported-UI recovery by the coordinator. Source creation, native Sync and
cleanup remain separate native checks. **ORB SPENDING NOT TESTED — NO AUTHORIZATION.**
