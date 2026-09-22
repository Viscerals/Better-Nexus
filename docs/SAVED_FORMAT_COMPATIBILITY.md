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
| Format 2, 1 and unversioned | Unchanged behavior. |

The message "written by a newer Nexus version" is replaced by the real markers, for example: "Saved data format 6 is not supported. This build writes format 2 and reads formats 3 to 5 after a check. The data is kept unchanged and read-only."

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
| `settings.syncMode`, `syncOnlyWhileResting`, `syncSuspendInCombat`, `syncSuspendedInstanceTypes`, `syncDirectExperimental` (Good Enough Nexus Sync controls) | Kept, but not read. Better Nexus Sync has its own behavior, so a Sync "off" or "manual" choice made there is **not applied** here. |
| `settings.autoSave` (default off there, on here) | The saved value is kept. |
| `settings.autoFreeze`, `settings.autoReroll` (absent there) | Added with this build's defaults, as for every profile that lacks them. The Automation switch (`autoPick`) is not changed. |
| `settings.communityRetention*` | The shared keys are read with this build's limits. `MaxTotal`, `MaxPerClass` and `CharacterBest` are kept and not read. |
| `accountCharacters` (`name@realm` rows) | Same key format; kept. This build does not add or update ledger rows for these formats. |
| `chars["Name"]` rows | Copied with established ownership as described above; otherwise kept unread. |
| `loadoutWishlists[slot]` = `{slot, key, name, echoes}` | Readable. If a Wishlist lists the same Echo in two separate rows, the two versions compute its key differently. That assignment is kept but is not used until it is assigned again. |
| `lockDesignTargetsBySlot[key]` = `{[spellId]=true or replaced spellId}` | Readable, with the same key caveat. |
| `tomeTogglePending`, `flagDemotions`, `recordedPicks`, unknown fields | Carried unchanged. |
| Account and DPS storage | The older account/DPS converter is not started for these formats. Its commit replaces those tables and keeps no archive. DPS storage is handled as in test.9033. |

## Limits

- In formats 3 to 5 a plain-name row is shared by every character of that name on the account. A same-name character on another realm that used the row before the ledger existed (format 4), and has not logged in since, cannot be detected. The ledger then lists only this realm, and the copy goes ahead.
- The format check result is kept for the session per saved table. A later change inside the settings or the ledger during the same session is not re-checked; this build writes neither the checked settings nor the ledger for these formats.
- A saved marker that is not a whole number (for example 6.5) is still read as unversioned and stamped 2. This was already so before this change.
- The check is offline, with synthetic data built from the reference layout. It has no native evidence and no tester profile behind it.
- Returning to the other addon later is not tested. Changes made here go to the `name@realm` row, which that addon does not read.
