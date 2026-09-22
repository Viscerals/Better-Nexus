# Saved-data formats 3 to 5 (Good Enough Nexus and earlier Better Nexus test builds)

## Problem

A tester on test.9033 reported "Saved format 5; Supported 2" after using Good Enough Nexus 1.96. This build writes settings format 2. Every saved format above 2 was treated as written by a newer version. Local reads and writes then used a temporary copy, and Orb Start refused with "Saved data was written by a newer Nexus version".

Format 5 is not newer. The earlier Better Nexus test line (archived commit `58b815b`) wrote formats 3 to 5. Good Enough Nexus forked from that line and still writes format 5. The comparison reference is Good Enough Nexus v1.96.6, commit `7bd6b86f7a4ece4c819b2a229167b621da36a407`, `core/Store.lua` blob `f3f43e418850d369726ad21f1a051c57d6599429`. It is identical to the archived `58b815b` Store except for one line. This reference is not proof of the exact archive a tester used.

## What changed

| Step | Behavior |
|---|---|
| Classification | Saved format 3, 4 or 5 is accepted only when the data shows what those formats' migrations produce: `syncMode` is off, manual, automatic or absent; the community-retention numbers are whole numbers of 0 or more; the account ledger is a table (4 and up); and the ledger has no `name@unknown` rows (5). This build also requires, for format 5, string ledger keys, table ledger rows and at most 4096 ledger rows. |
| Accepted ("known") | Local reads and writes are durable. The saved marker stays at its value; it is not lowered or raised. As for every profile this build opens, start-up also adds missing default settings keys and missing empty character sub-tables, and writes its own storage-migration receipt (`nexusStoreMigrations`). Before this change, none of that happened for formats 3 to 5. |
| Not accepted ("unverified") | The data stays unchanged and read-only. Messages name the saved format, the supported format and the first failing field. |
| Format 6 and higher ("future") | Unchanged and read-only, as before. |
| Format 2, 1, 0 and unversioned (marker absent) | Unchanged behavior. |
| Malformed marker | A marker that is present but not a finite whole number of 0 or more: fractions such as 6.5, negative values, NaN and infinities, every string (including a numeric string such as "5"), booleans, tables and other types. The data stays unchanged and read-only, like a future format: no default filling, stamping, conversion or character writes. The message names the marker's type and, for a number, boolean or short string, its value. This build and the older converter both refuse it. Treating numeric strings as malformed is an intentional tightening: test.9034 and earlier read "5" as 5. |

The message "written by a newer Nexus version" is replaced by the real markers, for example: "Saved data format 6 is not supported. This build writes format 2 and reads formats 3 to 5 after a check. The data is kept unchanged and read-only."

## Upgrading from a build that kept the data read-only

test.9033 and earlier kept formats 3 to 5 read-only. In that state the Store built no Store-data wrapper. The catalog still saved its data bundle, with an empty Store-data placeholder in it. test.9034 and test.9035 then refused that placeholder: start-up failed with `STORE_INVALID`, and the displayed reason had no further detail. This is reproduced on the exact sources: synthetic format-5 data started on test.9033 (`487eaa9`), then on test.9035 (`753e384`).

From the build after test.9035:

- **The empty placeholder is accepted as a first admission.** When the bundle holds exactly the empty placeholder and the saved format is an accepted 3 to 5, the Store builds its data wrapper as a first admission does. Start-up adds only the usual missing defaults; no saved value is changed or removed. Any other invalid wrapper still fails, and so does the placeholder for any other format. The placeholder stays in the saved bundle until a later catalog save replaces the bundle; until then each start-up builds the wrapper again in the same way, which changes nothing else.
- **Start-up failures state their cause.** A failed start-up keeps its failure code (for example `STORE_INVALID`). `/nexus status` (and any command while start-up has failed) adds one line with the retained facts: stage, cause, detail, owner, a bounded one-line error, the selection row, and the saved-format verdict. These are session-only. Reading them binds, retries and writes nothing.

## Character rows

Formats 3 to 5 keep each character's row under the plain character name (`chars["Name"]`). This build uses `chars["name@realm"]`. The first write for a character copies the plain-name row to `name@realm` only when ownership is established:

- the character has no `name@realm` row yet;
- exactly one plain-name key matches the name (no case variants, and no key with a `-Realm` suffix);
- the account ledger lists this exact `name@realm`, and no other realm, for that name;
- start-up has admitted the rows (the bounded cycle, alias and size checks passed).

The copy does not change the original plain-name row, so the other addon can still read it (start-up may add missing empty sub-tables to it, as it does to every row). An existing `name@realm` row is never merged or replaced. Any other case is ambiguous: the plain-name row stays unchanged and unread, and the character starts with a new row, as a missing row always did. The copy records its source in `savedFormatCarry`.

## Field comparison

| Field (format 5 meaning) | In this build |
|---|---|
| `settingsVersion` = 5 | Kept as 5. |
| `settings.syncMode`, `syncOnlyWhileResting`, `syncSuspendInCombat`, `syncSuspendedInstanceTypes`, `syncDirectExperimental` (Good Enough Nexus Sync controls) | Stored and kept unchanged. From the build after test.9034, `syncMode` Off and Manual are honored; the other controls are still **not applied**. See "Sync: stored versus effective" below. |
| `settings.autoSave` (default off there, on here) | The saved value is kept. |
| `settings.autoPick` (stored Take preference; same meaning in both addons) | Kept as saved. It is not the Automation master switch. |
| Automation master switch (`autoEnabled`) | Not a saved setting in either addon. It is a session-only switch that starts OFF in every session and turns on only through the panel button or `/nexus auto`. No saved data can turn it on. |
| `settings.autoFreeze`, `settings.autoReroll` (absent there) | Added with this build's defaults, as for every profile that lacks them. |
| `settings.communityRetention*` | The shared keys are read with this build's limits. `MaxTotal`, `MaxPerClass` and `CharacterBest` are kept and not read. |
| `accountCharacters` (`name@realm` rows) | Same key format; kept. This build does not add or update ledger rows for these formats. |
| `chars["Name"]` rows | Copied with established ownership as described above; otherwise kept unread. |
| `loadoutWishlists[slot]` = `{slot, key, name, echoes}` | Readable. If a Wishlist lists the same Echo in two separate rows, the two versions compute its key differently. That assignment is kept but is not used until it is assigned again. |
| `lockDesignTargetsBySlot[key]` = `{[spellId]=true or replaced spellId}` | Readable, with the same key caveat. |
| `tomeTogglePending`, `flagDemotions`, `recordedPicks`, unknown fields | Carried unchanged. |
| Account and DPS storage | The older account/DPS converter is not started for these formats. Its commit replaces those tables and keeps no archive. DPS storage is handled as in test.9033. |

## Sync: stored versus effective

| Good Enough Nexus setting (its meaning) | Stored in this build | Effective in this build |
|---|---|---|
| `syncMode` = `off` (no Sync traffic) | Kept | **Honored** from the build after test.9034 (test.9034 did not honor it). Nexus sends no Sync message of any kind: no requests, answers, Share sends, capability handshakes or `/nexus probe` whisper. Sync Now and Share say that the saved Sync mode is Off; a Share is saved locally and marked "not sent". Records already shared earlier are not withdrawn, and this is not network isolation: the client still receives. |
| `syncMode` = `manual` (traffic only during a Sync the user starts) | Kept | **Honored** from the build after test.9034. Idle: no automatic login Sync, no answers to other players, no handshakes. Sync Now (`/nexus sync` or either Sync Now button) sends its own requests and follow-up fetches, only until that Sync ends, at its existing fixed lifetime (300 seconds at most); pending work does not extend it. A confirmed Share (also of an edited record) sends its summary without a separate Sync Now, and answers other players that fetch that record (its Echo list, and DPS records carrying that build) until the Share's own 120-second expiry. That expiry counts from when the Share was queued, not sent: a Share held back (for example by combat) leaves less time for these answers. `/nexus probe` is allowed. Other queued work is not released. Because handshakes are not answered, directed traffic uses the channel route. |
| `syncMode` = `automatic` or absent | Kept | Unchanged automatic behavior. |
| `syncOnlyWhileResting` (default on: Sync only in rest areas) | Kept | **Not honored.** Sync runs anywhere. |
| `syncSuspendedInstanceTypes` (default: party, raid, pvp, arena, scenario) | Kept | **Not honored.** Sync runs in instances. |
| `syncSuspendInCombat` (default on) | Kept | Not read. This build's Sync channel and addon traffic always waits during combat, and that wait cannot be switched off. The manual `/nexus probe` whisper does not wait. |
| `syncDirectExperimental` | Kept | Not applicable: this build has no such transport. |

The Build Library status line states an Off or Manual mode. The saved value is never rewritten; this build has no control to change it. Profiles in format 2, unversioned profiles and read-only formats keep automatic behavior, even if they store a `syncMode` value.

## Limits

- In formats 3 to 5 a plain-name row is shared by every character of that name on the account. A same-name character on another realm that used the row before the ledger existed (format 4), and has not logged in since, cannot be detected. The ledger then lists only this realm, and the copy goes ahead.
- The format check result is kept for the session per saved table. A later change inside the settings or the ledger during the same session is not re-checked; this build writes neither the checked settings nor the ledger for these formats.
- Up to test.9034, a malformed marker (for example 6.5) was read as unversioned and stamped 2. From the build after test.9034 it stays unchanged and read-only (see "Malformed marker").
- The check is offline, with synthetic data built from the reference layout. It has no native evidence and no tester profile behind it.
- Returning to the other addon later is not tested. Changes made here go to the `name@realm` row, which that addon does not read.
