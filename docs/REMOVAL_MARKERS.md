# Removal markers: policy, budget and expiry

Status: characterization of the shipped behaviour (offline evidence only), with
a decision the owner still has to take. Nothing here changes what the catalog
admits or refuses.

## What a removal marker is

A removal marker (tombstone) is catalog ingress authority for one typed build
ID. It is written when:

- the local character stops sharing one of its own builds (Stop Sharing,
  `core/CommunityController.lua`), including the automatic replacement of a
  superseded record page after a better personal DPS best
  (`core/DpsCapture.lua`, RemoveSupersededPage -> CommunityBuilds.DeleteBuild);
- a remote owner's withdrawal is admitted for a row that owner proved
  (`BuildCatalog.SetTombstone` with `source = "remote"`).

While the marker is in force the ID is refused with `TOMBSTONE_RESERVATION`,
no row is restored, and only the catalog's explicit readmission claim for the
same ID (`BeginTombstoneReadmissionClaim`) can replace it. A local removal
writes an exact V1 marker that also carries the removed row's unknown evidence
(MASTER-RC-016); a remote withdrawal stores a bounded opaque payload.

## Classification across sessions

| State | When | Effect |
| --- | --- | --- |
| `CURRENT_DENY` | written in this session | deny |
| `RELOADED_BLOCK_ALL` | an exact V1 marker read from saved data (the `unknownEvidence` field is optional) | deny |
| `OPAQUE_BLOCK_ALL` | any other saved marker (remote payloads, older shapes, malformed) | deny |

All three deny. The distinction is diagnostic (support summary, PeerDebug) and
decides which exact readmission claim is possible.

## Expiry: none after a reload

Retention markers (barriers) expire 30 days after a trusted local age
(`docs/9020_SYNC_AND_NO_GUARANTEE.md`, `catalog_marker_expiry`). Removal
markers do not:

- `TombstoneExpired` (`core/BuildCatalog.lua`) retires only a `CURRENT_DENY`
  marker whose local creation time is at least `TOMBSTONE_AGE` (180 days) old.
  A marker written in this session cannot be that old, and every reloaded
  marker is `RELOADED_BLOCK_ALL` or `OPAQUE_BLOCK_ALL`. The retirement path is
  therefore unreachable in practice, and the 180-day constant has no effect.
- `tests/prototype/tombstone_retirement_policy.lua` pins this: 181 days after
  a removal, across a reload, the marker is in force, the ID stays refused and
  the retention pass retires nothing.

This is the fail-closed reading of the retention owner's own comment
("reloaded and opaque reservations stay block-all"). It is documented here so
the constant is not read as a promise.

## Budget: a lifetime count per saved profile

`BUDGET.tombstones` is 2048 markers per saved profile. Because markers never
expire, the budget is consumed for the life of the profile:

- every Stop Sharing, every automatic replacement of a superseded own record
  page and every admitted remote withdrawal uses one marker;
- at the limit a removal that needs a new marker is refused with
  `TOMBSTONE_SET_LIMIT` (local and remote alike); existing data, the Build
  Library and the Leaderboard stay usable (`catalog_saturation`).

The count is visible as `removal markers N/2048` in the support summary
(`/nexus report`, Copy summary) and as `tombstoneCount` / `tombstoneLimit` in
`BuildCatalog.Status()`.

## Decision required (not implemented)

Bounded options, each needing the owner's decision because the first two
change when an ID can be admitted again:

1. Retire reloaded **exact V1 local** markers after 180 days by the same
   trusted-local-age rule the retention markers use (`receiptAtServerTime`,
   never the marker's remote stamp), never remote or opaque markers. A
   retired marker leaves ordinary validated admission, as an expired retention
   marker does today. This is the reading the 180-day constant suggests.
2. Keep the lifetime policy and remove the dead retirement path and constant,
   so the code states the policy.
3. Keep the policy and raise the budget, with the saved-size consequences the
   capacity envelope documents (`core/BuildCatalog.lua`, BUDGET).

Until one is taken, the shipped behaviour is option 2's policy with option 1's
dead code, as characterized above.
