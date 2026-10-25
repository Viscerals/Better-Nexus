# Local pool persistence contract (#151)

Status: implementation contract for the [#151](https://github.com/Viscerals/Better-Nexus/issues/151) next-release extension. It extends the session-only chooser published with PR #136 (`b7b4ff5`), which remains the historical first milestone of [#47](https://github.com/Viscerals/Better-Nexus/issues/47) ([player-choice slice](PLAYER_CHOICE_SLICE.md)). This contract states behavior, the saved format, measured bounds and native limits. Merge and release state, check counts, pass results and review outcomes belong to the PR evidence for the exact source pin, not here. Native behavior is NOT_RUN (see Limits). This extension alone does not complete #47.

## Scope

This extension covers one active ordinary planning pool per character, with its explicit chosen counts. The pool is saved and loaded only by explicit player action.

A saved or loaded pool is planning state only. It is not ownership evidence, an assignment or authority to act.

Out of scope:

- actions: assign, upload, share, roll and spend;
- locked planning pools;
- shared or forked pool identity, Save As, and import/export;
- ranking, substitution and ties;
- migration.

## Record v1

The pool is stored as the raw key `flexiblePlanPoolV1` on the current character row, `chars[ownerKey]`:

```
{version=1, ids={...}, quality={...}, maxStack={...}, groupId={...}, counts={...}}
```

Shape:

- The record has exactly these six keys.
- All tables are plain: no metatable, alias or cycle.
- The five arrays are dense `1..n` arrays of equal length, with `1 <= n <= 256`.
- An empty pool is never stored. Removing the pool deletes the key.

Field rules:

- `ids`: distinct integers 1..2147483647, in the player's insertion order. The order is not a priority.
- `quality`: 0..255.
- `maxStack`: 1..2147483647.
- `groupId`: an integer 0..2147483647, or -1 for no group.
- `counts`: 0..min(79, maxStack), with a total of at most 79. 0 means not chosen.
- Names are not stored. A current catalog name of at most 256 bytes is display decoration only.

Canonical bytes are `"v1|"` followed by `id,quality,maxStack,group,count;` per row, with -1 for an absent group. These bytes drive dirty detection, read-back verification and the consent guards.

`Decode` classifies a record by the first defect it finds:

| Class | Condition | Load | Save or remove |
|---|---|---|---|
| `ABSENT` | No key | Nothing to load | Allowed when durable |
| `CURRENT` | Valid v1 record | Allowed | Allowed when durable |
| `FUTURE` | Raw `version` is an exact integer above 1. Checked before any traversal. | Refused | Refused |
| `UNSUPPORTED` | v1 with an unknown or missing field | Refused | Refused |
| `MALFORMED` | Bad type, metatable, missing or non-1 version, alias, sparse, unequal or empty arrays, bad value, duplicate ID, a count above `maxStack`, or a total above 79 | Refused | Refused |
| `OVERSIZED` | An array past 256 entries or index 256 | Refused | Refused |

A record past a Store copy bound is refused before decoding.

Refused records are kept exactly as found. The chooser offers no removal for them, so a future or damaged record blocks Save until it is removed outside this build.

## Data owner

`core/Store.lua` stays the only SavedVariables owner and owns the raw key. This extension changes none of the following:

- the public Store facade, which gains no method;
- the write path: writes use the existing counted `UpdateStateV1`, with no new mutation entry;
- the settings format, profile version and catalog schema;
- any native or shared protocol version.

`MainInternals.StoreAuthorityOwner` carries three additions:

- `PLAN_POOL_KEY`, which is `"flexiblePlanPoolV1"`.
- `PlanPoolReadV1()`, which is pure: it creates, shapes and invalidates nothing.
  - It returns the mode, the reason and the owner key.
  - It returns a Store-private root token, never a raw reference.
  - It returns row presence and a carried-row flag.
  - It returns either a bounded detached copy or a refusal.
  - It iterates with `next` and `rawget` only, and detects `FUTURE` before any traversal.
- `IsDurableStateRowV1(row)`. It is true only for the live current-character row of a writable root whose coordinator is ready or mutating. It rejects the transient fallback row.

Saved input is untrusted, so the copy has these bounds:

- 16 tables, at most two levels: the record and one level of child tables (a table inside a child table is refused as `MALFORMED`);
- 16 root entries and 257 entries per child;
- 3,871 entries visited in total;
- keys: strings of at most 32 bytes, or integers;
- values: numbers, booleans, or strings of at most 64 bytes.

`Store.State` and the `UpdateStateV1` snapshot comparison skip only the exact top-level row key `flexiblePlanPoolV1`. Everything else is copied, compared and kept as before, including:

- a same-named key nested elsewhere;
- other row keys;
- unknown and future fields;
- all other data.

Readers of the `Store.State` snapshot therefore do not see the pool.

| Mode | When | Load | Save or remove |
|---|---|---|---|
| `durable` | Settings format 2, or an accepted format 3 to 5 under the unchanged character-row rules | Allowed | Allowed |
| `readOnly` | Future, unverified or malformed settings format | A valid record loads as planning state | Refused; nothing is written |
| `loading` | The Store has not finished loading | Refused | Refused |
| `unavailable` | Invalid or disposition lifecycle, owner mismatch, missing seam, or failed read | Refused | Refused |

## Persistence facade (`Nexus.FlexiblePlanStore`)

The facade lives in `core/FlexiblePlanStore.lua`. It is frame-free and makes no game, catalog or adapter reads.

**`Encode(ids, rows, chosen)`** returns one of:

- `record, bytes`;
- `nil, nil` for an entry-free session, which means removal;
- `nil, code`.

The refusal codes are `INVALID_INPUT`, `ALIASED_INPUT`, `INVALID_IDS`, `TOO_MANY_ALTERNATIVES`, `INVALID_ID`, `DUPLICATE_ID`, `ROW_MISMATCH`, `INVALID_ROW`, `ALIASED_ROW`, `UNSUPPORTED_ROLE`, `UNKNOWN_FIELD`, `NOT_IN_POOL`, `INVALID_COUNT`, `STACK_LIMIT` and `ORDINARY_LIMIT`. Nothing is trimmed, clamped or substituted.

**`Decode(record)`** returns `pool, bytes, "CURRENT"` or `nil, class, detail`.

- `pool` is `{ids, rows, chosen}`, built from fresh tables.
- An absent group is nil.
- Only counts above 0 appear in `chosen`.

**`New({store})`** returns a facade, or `nil, "INVALID_STORE"`. Each call requires `StoreAuthorityOwner.owner` to be exactly that store. Otherwise the call refuses with `STORE_OWNER_MISMATCH`. There is no fallback to `Store.State`, a global owner or a transient row.

**`Read()`** returns a fresh receipt on each call:

```
{mode, reason, class, detail, ownerKey, root, pool, bytes, visited,
 carried, rowPresent, loadable, saveable}
```

- `class` is nil while the mode is `loading` or `unavailable`.
- `loadable` is true for a `CURRENT` record while durable or read-only.
- `saveable` is true for `ABSENT` or `CURRENT` while durable.

**`Save(session, receipt)`** takes `session = {ids, rows, chosen}`. It returns the result table:

```
{state, reason, detail, bytes, unchanged, restored, receipt}
```

`state` is `saved`, `refused` or `unverified`.

**`Clear(receipt)`** is a Save of an empty session.

Save applies these guards:

1. **The receipt must be one this facade issued**, by `Read` or an earlier Save.
   - The facade keeps the receipt's owner, mode, owner key, root, class and bytes privately, and all must still hold.
   - Editing the receipt's fields changes nothing.
   - Equal bytes on another character or root do not authorize a write.
   - Refusal reasons include `RECEIPT_UNKNOWN`, `RECEIPT_NOT_DURABLE`, `OWNER_CHANGED`, `ROOT_CHANGED`, `SAVED_CHANGED`, `SAVED_<class>`, `READ_ONLY`, `LOADING`, `UNAVAILABLE`, `INVALID_SESSION`, `NOT_DURABLE`, `STORE_OWNER_MISMATCH`, `READ_FAILED`, `WRITE_FAILED` and `WRITE_ERROR`.
   - A refusal writes nothing.
2. **Unchanged bytes** return `saved` with `unchanged = true`, and nothing is written.
3. **The write.** Inside `UpdateStateV1`, the single `rawset` runs only when both hold:
   - the row is the live durable row;
   - a nested read still shows the pre-read facts.

   The true result of `UpdateStateV1` is not trusted.
4. **`saved`** is returned only after a durable read-back of the exact bytes, owner key and root, both inside the mutator and again after it.
5. **Otherwise the result is `unverified`**, with reason `SAVE_UNVERIFIED`.
   - The detail is `VERIFY_MISMATCH`, `VERIFY_ERROR`, `POST_READ_MISMATCH`, `POST_READ_ERROR` or `UPDATE_ERROR`.
   - Rollback restores the earlier record only while the live value is still this Save's record under the same owner. A newer record is never overwritten.
   - `restored` is true only when the earlier state reads back. Otherwise it is false.

The facade never calls the adapter, controllers, Sync, Orb, character registration or the coordinator mutation machine.

## Chooser (`ui/FlexiblePlanChooser.lua`)

The chooser adds two visible controls, `NexusFlexiblePlanSave` ("Save pool") and `NexusFlexiblePlanLoad` ("Load saved"), and a persistence status line in plain player text.

### Return shapes

`M.SavePool()` and `M.LoadPool()` return `phase, code`. This shape is distinct from the facade's result table.

| Phase | Code |
|---|---|
| `saved` | nil, or `UNCHANGED` |
| `loaded` | nil |
| `confirm` | `LOAD_CONFIRM` or `CLEAR_CONFIRM` |
| `unverified` | `SAVE_UNVERIFIED` |
| `refused` | A chooser code (`NO_PERSISTENCE`, `COUNT_PENDING`, `NOT_OBSERVED`, `INVALID_SESSION`, `NOTHING_SAVED`, `LOAD_INVALID`, `LOAD_CHANGED`, `PLAN_CHANGED` or `SAVED_<class>`), or a facade reason |

`M.PersistenceState()` returns fresh scalar metadata and reads no saved data:

```
{available, phase, code, dirty, pending, stale, mode, class, saved,
 loadable, saveable, restored, catalogChanged, confirming}
```

### Reads and dirty state

- Each Show, each Load saved and each explicit Reset after the first Show reads the saved data once.
- Save and removal read only inside the facade.
- Typing, search, scrolling, hover and redraws read and write nothing.
- The first Show binds the session to its receipt. Later reads only report staleness; they never authorize a write.
- A Save before any read refuses `NOT_OBSERVED` and then reads.
- The session is dirty when count input is pending, or when its canonical bytes differ from its clean baseline. The baseline is initially the empty pool, and the bytes are encoded once per revision.
- Save is refused with `COUNT_PENDING` while input is pending.
- Nothing loads automatically.

### Load and removal

- **Load saved.** A clean session loads at once. A dirty session asks first with `NEXUS_FLEXIBLE_PLAN_LOAD`.
  - Loading rebuilds a detached model and re-encodes it to the exact saved bytes.
  - It then installs everything at once. Otherwise it refuses `LOAD_INVALID` and changes nothing.
- **Remove.** Saving an empty session while the bound receipt is `CURRENT` asks first with `NEXUS_FLEXIBLE_PLAN_CLEAR`.
  - An empty session with nothing saved returns `saved`, unchanged.
  - Future and unreadable saved records refuse without asking.

### Consent requests

- Each request is single-use.
  - A Load request carries the revision, saved bytes, owner key and root.
  - A removal request carries the bound receipt.
- Accept retires the request first. It then refuses `LOAD_CHANGED` or `PLAN_CHANGED` if the revision or the saved facts moved.
- Cancel retires only its own request, and a newer request retires only the former one.
- Late or replayed callbacks do nothing.
- Pool requests never hide or change any of the following:
  - the editor draft, its name and its contexts;
  - the editor's Save confirmation and its retry;
  - the replacement request. That request keeps its own revision guard, which refuses `PLAN_CHANGED` after the pool changes.

### Unverified and stale outcomes

- An unverified outcome never rebinds the session and never shows Saved. Save stays refused as stale until Load saved or Reset.
- The refusals `SAVED_CHANGED`, `OWNER_CHANGED` and `ROOT_CHANGED` also mark the session stale.
- A stale session never shows a finished Saved or Loaded status.

### Catalog changes

- Load keeps the saved ID, quality, maxStack, group and counts even when the catalog changed.
- It counts the changed members: missing, a changed quality, maxStack or group, or role fields present.
- **Open as new Wishlist draft** still passes through `WishlistController.PrepareNewExactDraft`. That call refuses `CATALOG_CHANGED` and keeps the pool, the counts and the saved record.
- Members never refresh silently. An explicit Remove and then Add captures the current facts, with 0 chosen.

## Measured bounds

These are offline synthetic measurements on one pinned LuaJIT runtime. They can differ with the runtime and the source revision; the revision and runtime of each measurement belong to the PR evidence. They are not native, storage or server contracts. All figures are for a maximal record of 256 rows.

**Graph:**

- 6 tables and 1,286 edges.
- 13,586 charged bytes and 9,988 canonical bytes.
- Two levels: the record and its five arrays.
- The row gains the 18-byte key and one edge.

**Store read and Save of a valid maximal record:**

- A read visits 1,286 entries and takes 157,100 VM count-hook instructions.
- A Save takes 398,000 instructions.
- A held read retains 50,264 bytes.
- 200 repeated reads left a bounded residue of 4,608 bytes. This is a bounded residue, not zero growth.

**Codec:** a held record is 6,848 bytes and a held session is 52,760 bytes.

**Startup**, comparing a row with and without the maximal pool:

- Charge pumps rise from 2 to 22 (+20).
- Coordinator pumps rise from 8 to 28.
- The largest single pump took 12,400 instructions.
- The frontier charges edges and bytes only; it does not charge sorting or comparison work. The instruction counts are the observed measure of that work.

**Composition:**

- The Store enforces aggregate source bounds plus per-key width, depth and pump caps.
- It does not enforce the notional per-row figures of 16,384 edges and 32,768 bytes.
- A maximal pool beside a 28,672-charged-byte sibling key makes the whole row 42,752 bytes. That is above the notional row figure.
- The enforced aggregate measured 43,584 bytes, below the SGB bound of 135,065,600.

**Admission bounds:** 256 alternatives is a local application admission bound, and 79 is the ordinary-choice compatibility bound. Neither is a universal server or storage cap.

## Validation

**Fixtures:**

- The offline fixtures are `tests/prototype/flexible_plan_persistence_*.lua`: the codec, Store, retention and chooser fixtures.
- The `flexible_plan_player_choice` and `flexible_plan_editor_handoff` fixtures are unchanged.
- All of them boot the real TOC with synthetic data and a synthetic host.
- Retention uses the real `F.Serialize` and an `F.Boot` module reboot. A module reboot is not a native client reload or login.
- Retention of the unknown key by an older build is tested for released build 9049 and the current build. Intermediate builds were not run.

The chooser fixture covers:

- coexistence with the real editor's retry, replacement request and unconfirmed Save;
- every visible button, and the reboot and Clear controls;
- after a write, restoration of an unverified Save, and no clobbering of a newer record;
- no stale Saved status;
- read-only format 6: a valid Load, with Save blocked;
- future, unsupported and sparse records kept;
- a loading owner not yet bound;
- refusals for a foreign root and a foreign owner with the same bytes;
- the catalog-changed Open refusal, and the exact Remove and Add;
- zero reads and writes for typing, search, scrolling and hover;
- one read each for Show, Load and Reset.

Check counts, pass results, the full suite, the package check and the independent Spec and Standards reviews belong to the PR evidence for the exact source pin; this contract records none of them.

## Limits

- Native frames, StaticPopup pooling, return handling, timing, fonts, pixels and server behavior are NOT_RUN. No exact versioned client/export reference was supplied.
- In a session, a character row can share a table with a copy in the saved bundle, and serialization can separate them.
  - The sequence Save A, reload, Save B, reload, Clear, reload reads correctly for the active row.
  - Earlier copies held elsewhere in saved data are not promised to be erased.
- Future and unreadable records block Save until they are removed outside this build. Nothing deletes them.
- Readers of the `Store.State` snapshot, including diagnostics, do not see the pool. This is intended.