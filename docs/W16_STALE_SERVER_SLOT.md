# W16: saving to a server Wishlist slot that was reused

Status: private fix, offline evidence only. No native test; what the real host does with an
overwrite is not known.

## Mechanism (reproduced on `06a9bb8`)

Two destinations exist. A Saved Build number receives the *association* (W15). A server Wishlist
slot receives the *content*. `WishlistController.BeginWishlist` binds the opened Wishlist's server
slot S, name and key. A save then used the frozen S: `PrepareApply` checked only that S exists,
`TryApply` checked the local assignment tokens and the Saved Build, and `GameAdapter.UploadWishlist`
validated the payload and the spacing, then called `UploadServerBuildSlot(S, name, rows)`. Nothing
asked whether S still showed the Wishlist the editor opened. Assignment tokens are local and do not
change when the slot service shows another record at S.

| Case (counted host uploads to S) | Before |
|---|---|
| unchanged slot | 1 |
| another Wishlist at S before Save | the confirmation is offered |
| slot reused while the confirmation is open | 1 |
| slot reused while the save waits on the upload spacing | the retry stays queued |
| same name with other content / other name with same content / slot removed / slot emptied | 1 each |
| A -> B -> A2 (A's name, other content) | 1 |

(`w16-015/REPRO-W16-before.txt`.)

## Repair

The editor binds the set of identity tokens the slot service shows at S when the editor opens. A
token is the name plus the content (`WishlistIdentity`: Echo id and total copies). The editor's own
uploads are added to the set, so a second save in the same session is accepted before or after the
mirror catches up. A save is refused when S shows any other token, shows nothing, or showed
nothing when the editor opened.

| Layer | Change |
|---|---|
| `GameAdapter.ServerWishlistSlotToken(slot)`, `ServerWishlistTokenFor(name, echoes)` | new, read-only |
| `GameAdapter.UploadWishlist(slot, name, echoes, expected)` | optional `expected` set; for an existing slot the slot is read again immediately before the host call and refused as `stale_slot` when it shows anything else or nothing. Slot 0 (create) is never checked; a caller that passes no set is unchanged |
| `WishlistController.PrepareApply` | refuses before the confirmation |
| `WishlistController.TryApply` | refuses before the upload and drops a queued retry (the retry path goes through it) |

A refusal uploads nothing, assigns nothing, keeps the draft and every assignment, and never
redirects the save to another slot. The new Wishlist flow (slot 0), first-run edits, locked-only
Wishlists, Unassign, the W15 empty-Saved-Build refusal and the binding tokens are unchanged. A
controller whose adapter cannot name slot identities binds nothing and keeps the earlier behavior.

## Routes

Every route that reaches a host upload for an existing slot with an editor context is checked:
`PrepareApply`, `AcceptApply` (including the direct payload API), `PumpApplyRetry` (through `TryApply`)
and the adapter's `expected` set, which also covers a payload that names a slot other than the bound
one. `GameAdapter.UploadWishlist` holds the only call to the host. Not checked, by design: slot 0
(create; also `CommunityController`'s copy flow), the direct payload API with no editor context, and
any caller of `UploadWishlist(slot > 0, ...)` that passes no `expected` set. The controller's own
check and the adapter's check overlap for the editor's bound slot, so a mutant that removes only one
of them stays green behind the other; each layer has its own test.

## Limits

- The slot service exposes no revision of a slot. Name and content are the strongest identity that
  can be observed there. A match proves nothing; it means no contradiction was seen. A slot that
  is removed and re-created with the identical name and the identical content cannot be told from
  the original, and the upload then replaces equal content. Name alone is not used (duplicate names
  are supported) and neither is the slot number.
- If the server stores an upload differently from what was sent (it renames or reshapes it), the
  mirror will show a state the editor did not predict, and a later save in that session is refused
  until the Wishlist is reopened. That is a refusal with the draft kept, not a lost edit. Not
  checked in the real game.
- `UploadWishlist` requests the slots again after every upload. If the real mirror is cleared and
  refilled during that refresh, an immediate second save could meet an absent row and be refused
  ("empty or not loaded") until the mirror is back. Not checked in the real game.
- "Your edits are kept" is true while the editor stays open; reopening the Wishlist reloads it from the
  mirror.
- A Wishlist opened while its slot is not in the mirror (for example the slot data is not loaded)
  cannot be saved in that editor. The mirror evidence is what the freshness check reads; it is not
  a server transaction.
