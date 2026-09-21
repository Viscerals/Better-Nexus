# NATIVE-03 first-run edit correction

The coordinator reproduced this failure on the unchanged installed
`test.9010-1731003` package. Its source commit is
`1731003ddc6e2b6e8d48a5ae98cc88d9eaebca80`, tree
`0031ac3ac8da4f1fb8e14933eac52cca64f7dd5b`, package SHA-256
`b99322fde207e6e580862a93016d7390c42f9cdbeeca4c31b3089984952d33f3`.
That package, its review, the native report and all 12 supplied screenshots
remain preserved. Earlier successful Help, creation and reload observations
remain valid for their exact preceding states.

The actual test-account editor created one first-run Wishlist with Common
rolled ID 201172 x1 and permanent design ID 200767 x1. Creation and reload
retained both targets. After the Journal ellipsis opened Edit, one plus click
and Save Changes successfully uploaded two rolled copies to server slot 102.
The main panel disappeared on editor Close. Orb status stayed
`Restoring assigned Wishlist...`, with no active or pending operation and no
spent or reserved allowance. No resource action occurred.

## Causes and correction

The Journal used `firstRun and nil or active` to pass the editor's loadout
context. In Lua this returns `active` when `firstRun` is true. Slot 0 is truthy,
so the save controller selected the numbered-loadout update path. That path
stored the new record at `loadoutWishlists[0]`, cleared `firstRunWishlist`, and
left the old slot-1 handoff record unchanged. The first-run resolver correctly
refused to guess another assignment. Waiting for server data cannot restore an
assignment that this local save just cleared.

The Journal now passes nil for the first-run context. The existing first-run
save path updates both the durable first-run plan and its established slot-1
handoff. Exact rolled copies and local permanent design remain together.
The numbered-loadout adapter also rejects non-positive or non-integer slot
identifiers before any local assignment write. The controller, resolver,
upload protocol, assignment identity rules and Orb protections are unchanged.

A second cause explains the vanished main panel. When Edit is the first editor
entry after reload, `OpenForWishlist` suppressed the HUD without attaching the
editor's normal menu-close restoration hook. It now attaches that existing hook,
as Show and New Wishlist already do. Close restores the wanted HUD state; an
explicitly hidden HUD remains hidden. No new window manager is introduced.

## Verification and limits

The new fail-capable regression uses the retained synthetic harness and the
actual Journal New Wishlist, catalog rows, empty permanent-slot selector,
name field, Create confirmation, fresh startup, Journal Edit, plus, Save
confirmation, adapter submission and main/Orb presentation. It supplies only
the standard parent-hide behavior missing from the harness's XML close-button
template. It does not replace the product controller or assignment resolver.

The regression reproduces the original restoring failure on the exact prior
package. An isolated variant with only the assignment fix still fails its main
panel visibility assertion. The complete correction passes early, late, empty,
stale and reordered server mirrors, same-name wrong-content rows, post-edit
reload, exact permanent design, new durable assignment identity, invalid-slot
refusal, and zero new upload/gameplay actions during passive observation.

All 76 retained scripts remain unchanged; this adds one script. Validation uses
the established LuaJIT 2.1 / Lua 5.1 DLL and unchanged review bridge. Full source,
extracted-package and fresh independent-review receipts are in the delivery
handoff. Offline widget assertions do not establish native pixels or input.

This correction prevents the demonstrated bad save. It does not silently migrate,
delete or guess a repair for an assignment already damaged by the prior build.
The coordinator retains the failed test record and owns any deliberate recovery
through the existing UI, replacement installation and native recheck. The writer
does not read live SavedVariables or alter running clients.

ORB SPENDING NOT TESTED — NO AUTHORIZATION. B1/B2 safeguards, unresolved
same-ID confirmation, pending actions and budget exposure remain unchanged.
Two-client Sync, reverse-source availability and temporary-record cleanup remain
separate native tasks. No resource test or publication follows this package.
