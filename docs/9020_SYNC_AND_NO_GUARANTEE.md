# test.9020 follow-up: Sync admission, withdrawal refusal, no inferred guarantees

Baseline: `test.9020-b49afd2`. All evidence below is synthetic and offline
(LuaJIT 2.1 / Lua 5.1 route). Nothing here is native WoW verification.

## Sync

| Defect on the baseline | Correction |
|---|---|
| `Catalog.Put` answers `false, ROOT_MUTATION_PENDING` with no ticket while another transaction owns admission. Sync counted that as a storage failure and discarded a valid inbound summary or full record. | `core/Sync.lua` retains the validated item in a bounded, session-only owner (64 total, 16 per sender, one per kind and ID). At the next ordinary admission turn the complete inbound handler runs again, so owner, revision, pending replacement and tombstone state are rechecked. Only the ticket from that one submission reports success. |
| A retained item could cross a database or binding change. | Each item captures its Sync session, catalog, bound database, SavedVariables table, binding generation and local player. A change cancels it as a storage refusal. |
| Stop Sharing was refused while the catalog was busy. | `core/CommunityController.lua` retains one exact-ID approval, rechecks scope, owner and the approved revision, and submits once. |
| The originating Stop Sharing refused the wire as `REMOTE_TOMBSTONE_ORDER_UNPROVEN`, but the responder later emitted `WLRD`. | The responder refuses tombstone candidates too. No local path emits `WLRD`. |
| An inbound direct-owner `WLRD` hid a stored row behind an `OPAQUE_BLOCK_ALL` reservation at any stamp. | A new inbound withdrawal never creates a reservation and never hides a stored row. Existing reservations are unchanged. |

### Limits

- **Remote withdrawal is not supported.** A `WLRD` carries an ID, a clock stamp
  and an author. It carries no target revision and no order comparable with a
  row edit (edits use `max(now, previous + 1)`, a tombstone uses the clock). No
  order rule is claimed. Stop Sharing removes the local record only. Peers keep
  their copy until the protocol carries a comparable edit/delete order.
- **Fixed deadline.** A retained item expires `PENDING_MAX_AGE` (300 s) after its
  own arrival. Other catalog work never extends it.
- **Large catalogs, demonstrated at 100 rows.** One catalog transaction rebuilds
  the whole root in per-frame slices. With 100 synthetic 79-entry rows, the
  preserved 60-second probes still fail at their bound, and a second retained
  item expires at 300 s while the first is being admitted
  (`sync_deferred_admission`, case 5b). No budget or deadline was changed.
- **Native-size behavior is an inference, not a measurement.** No receipt exists
  for a catalog near the historical authority-map size of 964 rows. If rebuild
  cost grows with row count, an item that arrives while such a catalog is busy
  is likely to expire before its turn. This must be measured before any claim.

## Rolling

The user-supplied current-game contract is: there are no guaranteed future Echo
rolls. This code change applies that contract. It does not prove the game
mechanic.

| Consumer | Correction |
|---|---|
| `logic/Policy.lua` dispatch on `snapshotVerified` | Removed. Every ordinary board uses `EchoWeaver`, which keeps its own incomplete-state refusals. The historical scoring is reachable only without that planner and then sees an empty queue. |
| `logic/Ratchet.lua` `PredictQueue` | Always empty. The obsolete expansion is `HistoricalGuaranteeQueue`, with no production caller. |
| `logic/Ratchet.lua` `RunsEstimate` | Counts known deficits only. |
| `core/AutomationRuntime.lua` board preparation and `JournalData` | No verification flag and no inferred queue reach the policy or the estimate. |
| `core/UserText.lua`, `ui/Help.lua` | No text says an unproven offer returns. |

Unchanged: saved-build identity, contents and ownership verification, observed
held, frozen and server-marked cards, Ratchet comparison and save protection,
permanent locks, and all Orb logic.

`tests/prototype/policy_adapter.lua` loads the real pure modules in production
TOC order. `tests/prototype/policy_compare.lua` is a deterministic decision
battery. It holds no draw weights, quality odds or redraw behavior, so it gives
decisions at fixed states only, not completion rates or efficiency.
