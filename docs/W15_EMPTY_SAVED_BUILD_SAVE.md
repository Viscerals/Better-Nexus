# W15: saving to an empty Saved Build

Status: private fix, offline evidence only. No native test.

## Mechanism (reproduced on `05d890d`)

The Echo Journal's Wishlist picker lists the server Wishlists. Its edit button opens the editor
bound to the active Saved Build whenever that slot number is positive, even when the Saved Build
holds no Echoes ("Empty Saved Build slot" in the Journal). A save then:

| Step | Before |
|---|---|
| `PrepareApply` / confirmation | offered; only an empty Wishlist (no ordinary copies) was refused |
| `TryApply` | uploaded the Wishlist, then called `UpdateWishlistAssociationAfterSave` |
| `UpdateWishlistAssociationAfterSave` | checked the slot number range only, wrote `loadoutWishlists[slot]` and cleared the first-run plan |
| result | an association under an empty slot, which `GetLoadoutWishlist` hides (unusable), and no first-run plan |

Reproduction (`w15-014/repro_w15.lua`, real picker gear and editor, harness): first-run plan
`201172:1`, active slot 2 empty. After one Edit and Save: `first=nil`,
`loadoutWishlists={1=..., 2=201172:2}`, one upload, `GetLoadoutWishlist(2)=nil`.
The two sibling writers (`SetLoadoutWishlistIdentity`, `SetLoadoutWishlist`) already refused an empty
slot; this was the one writer that did not.

Not a defect (checked, left as is): an editor with no ordinary copies is refused at `PrepareApply`
("pending list is empty"), `UploadWishlist` ("no echoes") and every association writer. A
locked-only draft without ordinary copies is refused the same way; that is existing behavior.

## Repair

| Layer | Change |
|---|---|
| `GameAdapter.IsLoadoutPopulated(slot)` | new read-only answer; a locked-only Saved Build counts as populated |
| `WishlistController.PrepareApply` | refuses before the confirmation when the numbered destination is empty |
| `WishlistController.TryApply` | checks again before the upload (the slot can empty while the editor or the confirmation is open; the delayed-retry path goes through it too) |
| `UpdateWishlistAssociationAfterSave` | refuses an empty slot at the moment of the write ("that loadout slot is empty or unavailable") |

A refusal uploads nothing, writes nothing, keeps the first-run plan and every assignment, keeps the
draft on screen and says why. It never redirects the save to the first-run plan: choosing another
destination is the player's decision. The first-run route (the Journal design button, which opens the
first-run plan with no numbered destination) is unchanged. A controller whose adapter has no
`IsLoadoutPopulated` is never treated as empty. Unassign, the assignment buttons, stale-binding
protection and the populated-slot save are untouched.

## Open question (not decided here)

When the editor is bound to an empty slot, the save is refused. A different rule could instead upload
the Wishlist and skip the assignment ("saved, not assigned"). That would keep the edit but leaves the
player's chosen Wishlist unassigned without a decision, so it was not chosen.
