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

### What Sync sends, and the Share confirmation (UX M5)

This section is a source trace of the current files and is shown to players in the same words. It is not native verification.

**Sync mode and the player's choice (14d, LP-12).**

- **Effective reader.** `core/Store.lua` `SavedFormat.SyncMode` (seam `MainInternals.SavedSyncModeV1`, read by `SyncModePolicy.Mode`) applies this order:
  1. the player's valid explicit choice `settings.nexusSyncModeChoice` ("automatic", "manual" or "off"), read only for a supported (format ≤2) or accepted known (3-5) root;
  2. without one, today's rule: "off" or "manual" from an accepted saved format 3-5 `syncMode`;
  3. otherwise "automatic".

  A dormant format-2 `syncMode` stays dormant. Future, unverified and malformed roots ignore any explicit value and keep their graph and behaviour.
- **The one control.** "Sync mode..." beside Sync Now in the Build Library (`ui/CommunityRenderer.lua` `SyncModeDialog`).
  - Opening it makes an uncommitted draft of the current mode.
  - Cancel, X, Escape, closing the Library, reopening and a stale draft discard it and write nothing.
  - Apply calls `SyncModePolicy.ApplyChoice`, the one new caller of the existing counted-private `StoreAuthorityOwner.UpdateSettingsV1`. For this key, `UpdateSettingsV1` validates first and writes only into an initialized, writable root (`SavedFormat.ChoiceStatus`). Anything else is refused with its reason, with no session-only override.
  - Apply writes the explicit choice even when the inherited mode is the same. Only an identical stored explicit choice is a no-op.
  - The result shown is read back from the Store.
- **Unchanged.** settingsVersion 2, the 3-5 classifications, the old `syncMode`, migrations, defaults, the Store facade exports and the two private mutation entries.
- **What Apply does not do.** It calls no RequestSync, Share, probe, Init, Reset or pump.
  - Later traffic follows the new mode through the existing queue-admission and final-submit `SyncModePolicy.Allows` checks and the existing convergence stop.
  - Already submitted messages cannot be recalled.
  - Automatic resumes only through its ordinary scheduler.
- **Where the mode is stated.** The Build Library status (sized to its rows by `LayoutMetrics.Community`), both Sync Now tooltips, the Welcome and Help.

**What each mode can send without a click:**

| Mode | Sends without a click | Source |
|---|---|---|
| Automatic | The login Sync request for shared builds and DPS records | `core/SyncSession.lua` `UpdateAutoSync` |
| Automatic | Answers to other users' requests, with the shared builds and records this client holds | `core/Sync.lua` `permitResponse` → `SyncModePolicy.Allows` |
| Automatic | Each new personal DPS best, with player name, realm, class, level, Echo list, locked Echoes, category, DPS, duration and time | `core/DpsCapture.lua` new-best branch → `Sync.BroadcastDpsRecord` |
| Automatic | That best's automatic "<Class> Record Loadout" build page: a build summary with **no Echo list** (title, owner, class). Its Echo list goes only in later answers to players who ask. | `core/DpsCapture.lua` new-best branch → `CommunityBuilds.EnsureDpsBuildForEchoes` → controller `SaveBuild` (commit) → `BroadcastIfPossible` → `Sync.BroadcastBuildSummary` (a "bulk" queue entry with no operation kind) → queue admission (`SyncModePolicy.Allows`). Manual always refuses it. Its queue entry carries only the build ID, the bulk class and its times: no requester, no Sync Now grant and no Share operation (`core/Sync.lua` `BroadcastBuildSummary`). A Share grant for the same build admits only follow-up answers to players who request it (`ShareFollowUp` needs a requester). Off refuses it. |
| Manual | Nothing without a click. Only what the player starts: Sync Now and its grant, an explicit Share and its follow-ups, the diagnostic probe whisper | `core/SyncModePolicy.lua` `Allows` |
| Off | Nothing | `core/SyncModePolicy.lua`, `sync_saved_mode_off` |

In every mode, `Sync.Init` joins the hidden channel `wrbuildssync`, and inbound messages are handled. `core/SyncInbound.lua` has no mode gate.

**Superseded Record Loadout page, local only.** When a newer best replaces this character's automatic page, `DpsCapture` `RemoveSupersededPage` calls `DeleteBuild`, which reaches `Sync.BroadcastDelete`.

- It stores the local tombstone. While the catalog is still committing it, the first return is `ROOT_MUTATION_PENDING` with the local removal marked pending. That is an intermediate result, not the final one.
- Once the tombstone is committed, it refuses `REMOTE_TOMBSTONE_ORDER_UNPROVEN` before any encoding or `Enqueue`, so zero bytes reach the wire.
- That final reason arrives in the completion receipt of the same local ticket (local removal done, queue not admitted) and in `Sync.GetDeleteStatus`. It is the first return only when the tombstone commits at once. Nothing is submitted again.
- No peer removal or recall is sent or claimed. Players who received the page keep it.

**Vocabulary.** These words are kept distinct:

- queued: waiting to send;
- sent: left this client, receipt not confirmed;
- received: arrived here;
- stored: kept by this client after its checks.

A listed record is one this client stored. It says nothing about which other players hold it.

**Share of your own Saved Build** (`ui/CommunityRenderer.lua`):

- It is a separate action at the right of the detail actions. "Copy into Editor" only makes a draft and never shares.
- It opens `NEXUS_SHARE_SAVED_BUILD`, which states that a shared build cannot be recalled and that receipt is not confirmed. It also states that the summary is queued only if the saved Sync mode and its size allow, and that the Echo list goes only to players who ask.
- The confirmation binds one build: its owner and the content fields title, description, Echoes, locked Echoes and publication. The link `PublishImportedBuild` copies from the existing listing is outside that binding (M5R-NB01, M7).
- Accept is single-use. It re-reads the build and shares nothing when any of that changed or the Build Library was closed.
- Cancel, Escape and closing the Library do nothing.
- After Accept, `PublishImportedBuild` (`core/CommunityController.lua`) first commits the listing and the mirror's publication in one catalog maintenance commit. Only then, and only when the player, saved data, catalog and its binding are still those of the confirmation (as `EditBuild`), does it hand the listing to `Sync.BroadcastBuildSummary` as an explicit Share (`{explicit=true}`). That is operation kind "share" with its key and a 120-second expiry, and no queue-full retry. Otherwise it queues nothing ("player or catalog changed").
  - Automatic and Manual admit it. Manual does so through its existing `operationKind="share"` rule; the policy is unchanged. Once it is admitted, answers to players who request that listing are permitted until that expiry (`NoteExplicitShare`).
  - Off refuses it at admission. If Off is applied while it waits, the final-submit check drops it.
  - A summary over 247 escaped bytes (`CHAT_LIMIT` 255 minus `CHAT_SAFETY` 8) is refused as "summary too large" before any queue entry. A missing Sync entry is "sync unavailable". Both are final; nothing is retried.
- The completion line states that actual result: "…locally as your shared listing and queued its summary. Queued is not sent…", "…— not sent: your saved Sync mode is Off." or "…— not queued, so nothing was sent: <reason>." A completion that reports no result claims nothing about the queue. A local save is not network admission, and queued is not delivery.
- The summary (`SyncCompatibility.SummaryEncode`) carries id, title, author, owner, class, time, Echo hash, link hash, Echo count and the automatic flag. It has no Echo list and no description. Those go only in the full record answered to a player who asks (`WLLQ` → `WLRB`).
- The DPS-best hand-off after the commit (`DpsCapture.BroadcastBestForBuild`, no Share options) is unchanged. It creates no record, and Manual still refuses its bulk entries.
- Retry Share, the Share form and every Share status sentence are unchanged.
- One approval starts at most one Share. It does not make sending exactly-once, and it does not pause the independent background Sync.

**Not done here:**

- unifying the live state words "Listening…" (Build Library) and "Syncing • N receiving" (Leaderboard) (M5R-NB18, M7);
- the "bundled + overlay" count sentence, which an existing test pins.

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
