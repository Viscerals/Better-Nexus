# Nexus 1.20 Beta

- Ships a versioned baseline of community builds and synchronizes smaller incremental changes instead of repeatedly exchanging the full catalog.
- Makes Sync response preparation incremental and queue-aware so busy sessions avoid frame stalls and resume fairly as capacity becomes available.
- Keeps personal builds, newer revisions, filters, DPS records, and deletions intact while migrating existing data additively.
- Adds bounded, coalesced, and virtualized Builds, Leaderboard, HUD, and wishlist rendering for large collections.
- Adds session diagnostics, structured error history, and aggregate performance counters for easier tester reports without storing raw samples.
- Refreshes the Project Ebonhold Echo catalog when represented source data changes while retaining the last known-good catalog on failure.
- Expands deterministic compatibility and reliability coverage across data migration, synchronization, UI refreshes, reloads, and automation boundaries.

This is a public beta validated by offline harnesses. Back up `NexusDB` and `WishlistRealizerDB` before testing and report `/reload`, migration, large-library, and long-session behavior.

# Nexus 1.19.5

- Fixed the Wishlist button for active Saved Builds without an association; it now opens a persistent Create New Wishlist editor instead of hiding the Nexus menu.
- Reset all draft selections and locked-slot designs when opening an unassociated build, preventing stale editor state from carrying into the new wishlist.
- Made queued Sync traffic follow the named channel across reconnects and channel renumbering, with explicit queue limits and retained retries under backpressure.
- Hardened build, loadout, deletion, and DPS synchronization against malformed or spoofed traffic while preserving supported legacy/current peers.
- Prevented incomplete loadout, bucket, DPS, and deletion responses from being claimed or discarded before their payloads are safely queued.

# Nexus 1.19.4

- Forward-ported the proven queue-aware Echo policy, exact-quality targets, final-search handling, refusal recovery, equal-progress wishlist rotation, and truthful horizon/final diagnostics while preserving the current UI architecture.
- Added pre-click Tome of Echo bag detection and a 20-second mutation pause while leaving the stock bind confirmation fully owned by the client.
- Hardened build and DPS sync against oversized/conflicting transfers, sender/author spoofing, unsigned deletion relays, evidence-free legacy DPS records, partial build edits, and stale derived identities.
- Fixed sync response claiming so non-owner peers cannot suppress owner-only DPS records or tombstones, and prevented colliding build IDs from attaching records to unrelated loadouts.
- Made locked-Echo migration and current-run owned-state synchronization generation-aware and idempotent across reloads and new runs.
- Wishlist progress is now counted per exact Echo/quality everywhere, matching the rule the save gate already used. A forced Uncommon copy no longer counts as one of the Rare copies your wishlist asked for.
- Fixes STILL NEEDED and the save message contradicting the save decision: a run that shed forced Uncommon copies while gaining a real Rare one reported "loadout cleaned up — shed Quick Hands" and showed Quick Hands going backwards, even though the run was genuinely closer to the wishlist.
- Clearing a wrong-quality copy now counts as cleanup in the save gate instead of scoring nothing, so a run whose only achievement is removing them can still save.
- Save messages now say how many wrong-quality copies were cleared, so a family's owned count dropping is explained rather than looking like lost progress.

# Nexus 1.19.2

- "Automate locked Echo slots" now handles both locking and unlocking automatically as your wishlist's locked-slot designs change.
- The Wishlist Editor shows which currently-locked Echo each locked-slot design will replace.
- Native in-game wishlist imports now correctly recognize locked Echoes.
- Fixed save results being reported as unconfirmed when locked Echoes were involved.
- Runs that make genuine progress toward your wishlist now save even when one target's coverage shifted, instead of being blocked outright.
- Reduced forced low-quality picks late in a run by spending an available reroll instead, when doing so protects save quality.

## 1.19.2 Dev Test 15

- Wishlist progress is now counted per exact Echo/quality everywhere, matching the rule the save gate already used. A forced Uncommon copy no longer counts as one of the Rare copies your wishlist asked for.
- Fixes STILL NEEDED and the save message contradicting the save decision: a run that shed forced Uncommon copies while gaining a real Rare one reported "loadout cleaned up — shed Quick Hands" and showed Quick Hands going backwards, even though the run was genuinely closer to the wishlist.
- Clearing a wrong-quality copy now counts as cleanup in the save gate instead of scoring nothing, so a run whose only achievement is removing them can still save.
- Save messages now say how many wrong-quality copies were cleared, so a family's owned count dropping is explained rather than looking like lost progress.

## 1.19.2 Dev Test 14

- Reworked first-run onboarding so the primary button is now **Assign Wishlist**.
- **Assign Wishlist** opens the same server-backed assignment flow as **Swap** instead of opening the Community Builds browser.
- Updated the onboarding title, helper text, and tooltip to clearly explain how to associate a wishlist with the current loadout.
- Kept **Create Wishlist** as the secondary path for players who do not already have one.

## 1.19.2 Dev Test 13

- Budgeted bracket fishing: maximum 3 consecutive rerolls against the same unwanted guaranteed Echo and 4 rerolls per level bracket.
- Preserves 5 rerolls for later brackets until level 78, then allows the remaining charges to be spent.
- When bracket-fishing budget is exhausted, falls through to the existing wanted/banish/EV/least-harmful decision cascade instead of forcing filler.
- Save gate now rejects increased exact-target excess and newly added lower-quality siblings of wished families.
- Cleanup-only saves must reduce an existing exact excess instead of hiding it behind unrelated filler removal.

## 1.19.2 Dev Test 12

- Fixed freeze eligibility to require a real wishlist shortfall beyond the remaining exact Saved Build guarantees.
- Baseline-only side offers such as Lightning Charged or Reaper’s Verdict are no longer frozen when their exact copy is already guaranteed later.
- True extras such as Swift Step 3 with only 2 copies saved remain eligible to freeze.
- Existing protection remains: wished families are never banished, and a held wanted Echo is selected over unwanted guaranteed filler.

## 1.19.2 Dev Test 10

- Block level-80 startup/reload save evaluation until the current session has observed an actual run offering.
- Report every remaining wishlist deficit in save/no-save chat summaries instead of only the first missing Echo.

## 1.19.2 Dev Test 9

- Frozen wanted Echoes now always beat an unwanted guaranteed filler card.
- Taking the held Echo immediately frees the frozen slot instead of wasting a reroll, banish, or selection on filler.
- Wanted guarantees still retain priority; this rule only applies when slot 3 is not a valid wanted pick.

# Nexus 1.19.1

## 1.19.2 Dev Test 7

- Prefer exact wishlist duplicates over lower-quality same-family filler on forced boards.
- Treat save progress and filler at exact spell/quality granularity.
- Show wrong-quality saved variants in TO SHED with their quality.


- Fixed HUD overlaps and spacing across all HUD variants.
- Fixed Performance menu elements sticking on the HUD after being disabled.

# Nexus 1.19

- Major wishlist editor upgrades.
- Cleaner wishlist creation, selection, editing, and loadout association.
- New wishlists automatically associate with the active Saved Build.
- Added direct navigation between Builds, Leaderboard, and Wishlists.
- Added My Builds with easier community uploading and updating.
- Incomplete synced builds now remain at the bottom of build results.
- Improved Training Dummy and Lich King DPS capture, storage, and HUD display.
- Added Best Average rankings for builds with both DPS records.
- Fixed DPS records not appearing on matching saved loadouts and build sheets.
- Fixed saved loadouts displaying the wrong class when matched with leaderboard records.
- Improved HUD layout, navigation, Soul Ash display, performance records, and menu readability.
- Added Nexus-user recognition to player tooltips.
- General UI, spacing, tooltip, navigation, and dark-mode cleanup.
