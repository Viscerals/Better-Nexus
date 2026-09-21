# First-run Unassign correction

The coordinator found this blocker before installation of `test.9011-91d850f`.
Its actual Journal Unassign handler fails on clean newly created first-run data.
That reviewed package and its complete Create/Edit/HUD review remain preserved.
This correction is separate from NATIVE-03 and has not been verified natively.

## Demonstration and cause

The new regression uses real Journal New Wishlist, catalog selection, permanent
target selection, Create confirmation, and the real assignment-selector Unassign
row. The exact previous runtime reports `state=restoring`, `first=nil`, and a
remaining slot-1 handoff after the click. The fail-capable assertion exits 1.
This is a demonstrated defect, not a successful product validation.

First-run creation deliberately records the same stamped assignment both as
the current first-run target and as the future slot-1 handoff. Unassign previously
cleared only the first record. The resolver interpreted the handoff as unresolved
assignment evidence. Removing that handoff alone fixes the empty-account case,
but an unrelated saved assignment still produces the same false restoration.

## Bounded correction

`ClearFirstRunWishlist` removes slot 1 only when both records have the same
nonempty assignment ID. Equal names, equal rolled contents, or absent IDs are
not sufficient. Other slots and uncertain legacy records are retained unchanged.
The server Wishlist and permanent-target design store are not deleted.

The existing `firstRunWishlist` field records an explicit Unassign as `false`.
The known first-run resolver recognizes this value as a deliberate absence.
`nil` retains its previous meaning, including the existing restoration guard.
Normal assignment writes replace the marker through existing paths. Unknown
active-loadout identity still requires restoration when numbered assignments
exist. There is no automatic state migration or repair.

Only `core/GameAdapter.lua` changes product behavior. The other changed paths
are this document, the new regression, and its test-inventory registration.
No UI, controller, wire protocol, source selection, spending or retry path changes.

## Validation scope

The regression covers exact first-run creation and explicit Unassign, main and
Orb consumers, disabled Start, persistence, empty/late/reordered mirrors, delayed
active identity, unrelated numbered assignment selection, equal-name/content
records with different or missing IDs, exact retained source and permanent
design, deliberate reassignment through the real picker, and zero new service
mutations. Passive startup and observations leave the old damaged state intact.

All 77 prior prototype scripts remain unchanged. Run all 78 scripts against
the frozen source and extracted replacement using the existing LuaJIT bridge.
A fresh focused review and final exact receipts belong to the delivery evidence.
Native pixels, input, reload timing, server acknowledgment, two-client Sync,
and supported source deletion remain coordinator-owned validation.

The old failed test assignment is not repaired by installation. Any deliberate
recovery must use the supported UI and exact test-created record identity.
Unassign is not server-source deletion. No main-account assignment changes,
private saved-data access, installation, native input, or resource spending
occurred in this correction. **ORB SPENDING NOT TESTED — NO AUTHORIZATION.**
