# W16: saving to a server Wishlist slot that was reused

Status: private fix, offline evidence only. No native test; what the real host does with an
overwrite is not known. The mechanism below is contradiction detection over the slot service's
mirror, not proof of which Wishlist a slot holds.

## Mechanism (reproduced on `06a9bb8`)

Two destinations exist. A Saved Build number receives the *association* (W15). A server Wishlist
slot receives the *content*. `WishlistController.BeginWishlist` binds the opened Wishlist's server
slot S. A save used the frozen S: `PrepareApply` checked only that S exists, `TryApply` checked the
local assignment tokens and the Saved Build, and `GameAdapter.UploadWishlist` validated the payload
and the spacing, then called `UploadServerBuildSlot(S, name, rows)`. Nothing asked whether S still
showed the Wishlist the editor opened. Assignment tokens are local and do not change when the slot
service shows another record at S. (`w16-015/REPRO-W16-before.txt`.)

## Repair, in two steps

**Step 1 (`98efd61` .. `af2d83e`).** After the editor opens, the slot is compared with what the
editor bound; `PrepareApply`, `TryApply` and `UploadWishlist` (an optional accepted set, read again
immediately before the host call, reason `stale_slot`) refuse any other state. Own uploads join the
set. That step bound *what the slot showed when the editor opened*, so a slot that was already
reused at that moment was accepted as the selection (found in review; `REPRO-W16-open-before.txt`).
A second gap: `ServerWishlistSlotToken` hashed the entries `A.Slots()` could read and ignored its
`roleSourceValid = false` flag, so a row with an unreadable extra entry could match.

**Step 2 (this change).**

| Boundary | Change |
|---|---|
| Selection | `OpenForWishlist` takes the selected record's token (its own name and content, as the Journal row, assignment or confirmed role choice carries them) before any resolution and passes it to `BeginWishlist`. `BeginWishlist` binds that token, never the token the slot shows. Opening against a slot that shows something else marks the binding contradicted |
| Contradiction latch | A positive mismatch the guard has seen (at open, at `PrepareApply`/`TryApply`, or reported by the adapter) stays seen: the selection reappearing in the slot does not restore the overwrite. Reopening the Wishlist is a fresh selection. A slot that cannot be read is *unknown*, not a contradiction: it refuses the save for now and does not latch |
| Unreadable rows | `ServerWishlistSlotToken` returns no token for a row with `roleSourceValid = false` (dense row with an unreadable entry, sparse list), so survivors that equal the selection do not match |
| Role picker | `ConfirmWishlistRoles` now compares the selected name as well as the content. A slot reused under the same content but another name is refused instead of being opened from the live row |
| Submitting editor | `TryApply` captures the editor it belongs to before the host call and adds the submitted state to that editor's accepted set only, even if a callback opened another editor or changed the draft |
| Confirmation | a refused `PrepareApply` drops a pending confirmation |

A refusal uploads nothing, assigns nothing, keeps the draft and every assignment, and never
redirects the save. The new Wishlist flow (slot 0), first-run edits, locked-only Wishlists,
Unassign, the W15 guard and the binding tokens are unchanged. A locally saved locked design is not
compared: the token is the name and the Echo ids and copies of the selected record, which is what
the host row holds, so an edit with a design the host row does not carry still saves, and a changed
ordinary source is refused even when a design is present. A controller whose adapter cannot name
slot identities binds nothing and keeps the earlier behavior.

## Routes

Every route that reaches a host upload for an existing slot with an editor context is checked:
`PrepareApply`, `AcceptApply` (including the direct payload API), `PumpApplyRetry` (through
`TryApply`) and the adapter's accepted set, which also covers a payload that names a slot other
than the bound one. `GameAdapter.UploadWishlist` holds the only call to the host. Not checked, by
design: slot 0 (create; also `CommunityController`'s copy flow), the direct payload API with no
editor context, and any caller of `UploadWishlist(slot > 0, ...)` that passes no accepted set.

## Limits

- The slot service exposes no revision of a slot. Name and content are the strongest identity that
  can be observed there. A match proves nothing; it means no contradiction was seen. A slot that is
  replaced and then shows the same name and the same content again, with no reading in between,
  cannot be told from the original. Saving then submits the *edited* draft: the host receives
  different content from the slot's, so this is not an equal-content overwrite, and whether it
  replaces the same server object cannot be known here. Closing it needs a host revision or a
  conditional write, which this addon does not have. Name alone is not used (duplicate names are
  supported) and neither is the slot number.
- If the server stores an upload differently from what was sent (it renames or reshapes it), the
  mirror will show a state the editor did not predict; that counts as a replacement and a later
  save in that session is refused until the Wishlist is reopened. The draft is kept. Not checked in
  the real game.
- `UploadWishlist` requests the slots again after every upload. If the real mirror is cleared and
  refilled during that refresh, an immediate second save is refused as unknown ("empty or not
  loaded") until the mirror is back; it is not latched. Not checked in the real game.
- "Your edits are kept" is true while the editor stays open; reopening the Wishlist reloads it from
  the mirror.
- A Wishlist whose slot cannot be read cannot be saved until it can; the mirror is what the check
  reads, not a server transaction.
- The roles and the Journal row are captured when they are built. A slot reused before the row was
  built is not detectable: the row is then the selection.
