# Local pool persistence contract (#151)

Status: selected next-release implementation contract, recorded before persistence code. Based on published PR136 `b7b4ff5`. Native checks are NOT_RUN. This contract adds one local per-character pool; it creates no assignment, ownership or action authority.

Implementation qualifications: graph/work/heap formulas below are hypotheses until the fixtures measure them. The startup pump increment must be measured using actual Store metering rather than asserted from edge division alone; cursor/sort/comparison work may dominate. Existing unknown fields already survive module reboot on the baseline, so the meaningful initial RED is missing Save/Load behavior, not an invented loss of manually inserted unknown data. No consumer of a new pool key existed before this feature; snapshot exclusion applies only to that exact newly reserved key. Existing unknown/future fields remain unchanged.

## 1. Decisions on the earlier candidate

| Candidate element | Decision | Rationale |
|---|---|---|
| Additive character-row key `flexiblePlanPoolV1` | **Selected** | The pool is per character, like the class-filtered catalog. `CharMigration`, `FillMissing` and `EnsureStateShape` keep unknown row keys. The Orb archive precedent shows a released build keeps such a key. No settings-version bump and no migration are needed. |
| Top-level root key | **Rejected** | It would be a sidecar root and outside the per-character owner. |
| Five dense, equal-length arrays | **Selected** | Each edge is at most a 3-byte index plus an 8-byte value, so the startup pump caps (64 edges / 2,048 bytes) hold. |
| Packed single string | **Rejected** | One long value would exceed the per-pump 2,048-byte ceiling. The documented exception covers keys only. |
| Captured facts (id, quality, maxStack, groupId with absent = −1) | **Selected** | These are exactly the facts `ValidatePlanDraft` compares. |
| Storing names | **Rejected** | Names are current-catalog decoration only. |
| 256 alternatives | **Kept as application admission only** | It matches the session chooser. It is not a server or storage contract. |
| ≤79 selected ordinary copies | **Kept** | Matches the accepted model. |

## 2. Record format v1

```
chars[ownerKey].flexiblePlanPoolV1 = {
  version=1, ids={...}, quality={...}, maxStack={...}, groupId={...}, counts={...} }
```

**Valid record (all must hold):**
- The root has exactly these six keys.
- All tables are plain, with no metatable.
- The five arrays are dense, with `1..n` keys only.
- All five arrays have the same length, with `0 ≤ n ≤ 256`.
- `n == 0` is never stored; clearing removes the key.

**Field rules:**
- `ids`: distinct integers in 1..2147483647.
- `quality`: integers in 0..255.
- `maxStack`: integers in 1..2147483647.
- `groupId`: −1, or an integer in 0..2147483647.
- `counts`: integers in 0..min(79, maxStack[i]), with Σcounts ≤ 79.
- Zero means the member is unchosen.
- The order of `ids` is the player's insertion order. It is not a priority.

**Classification and what each class allows:**

| Class | Condition | Load | Overwrite (Save/Clear) |
|---|---|---|---|
| `ABSENT` | No key | — | Allowed |
| `CURRENT` | Valid v1 record | Allowed | Allowed |
| `FUTURE` | Raw `version` is an exact integer > 1. Checked before any traversal, like `ClassifyMigrationMarker`. | Refused | Refused |
| `UNSUPPORTED` | v1 with any unknown or missing field | Refused | Refused |
| `MALFORMED` | Bad type, sparse array, unequal lengths, duplicates, non-finite or non-integer numbers, string numbers, a non-1 version, metatable, alias or cycle | Refused | Refused |
| `OVERSIZED` | Past a copy bound (§4) | Refused | Refused |

For every refused class:
- Nothing is rewritten.
- The chooser offers no delete.
- The status line names the class.
- This build keeps the data exactly as found.

Accepted cost: a damaged record blocks Save until it is removed by manual or future recovery. That is preferred over destroying data this build cannot classify.

**Canonical bytes:** `"v1|"` followed by `id,q,max,group,count;` per row. These bytes are used for:
- dirty detection;
- read-back verification;
- consent guards.

## 3. Measured bounds and composition

Let n = 256.

**Graph cost (CharMigration charging rule):**
- Tables: 6 (root plus 5 arrays).
- Edges: 6 + 5n = **1,286**.
- Depth below the row: record = 2, arrays = 3. The cap is 6, leaving headroom of 3.
- Charged bytes:
  - Root keys: 46.
  - Array index bytes: 5 × 660 = 3,300.
  - Values: 1,280 × 8 = 10,240.
  - **Total: 13,586.**
- The row gains one direct key, against the cap of 64.
- No key is wider than 8 bytes, well under the 183-byte rule.

**Startup work:**
- An admitted maximal pool needs ≤ ⌈1,286/64⌉ = 21 edge-capped pumps.
- Each such pump charges at most 704 bytes, under the 2,048-byte cap.
- Test target: the pump delta between a row with and without a maximal pool is ≤ 22.

**Runtime work:**
- The Store copy visits at most 3,871 entries (§4) and aborts at the first exceeded bound.
- Codec decode is ≤ 1,286 entries.
- Allocation is one detached copy: ≤ 6 tables and ≤ 1,280 numbers.
- Asserted ceilings:
  - After a collected GC, heap growth from holding one decoded maximal record is ≤ 64 KB, using `collectgarbage("count")`.
  - 200 repeated reads show no residual growth.
  - The synthetic `F.Serialize` length is ≤ 24 KB. This is labeled as not native SavedVariables bytes.

**Composition (contradiction flag).**
- The Store enforces aggregate source bounds (SGE/SGB) plus per-key width, depth and pump caps.
- The per-row figures of 16,384 edges / 32,768 bytes are architecture notional values. `WithinBounds` does not check them per row.
- The Orb archive design already budgets 28,672 bytes against that notional figure.
- A worst-case Orb archive plus a maximal pool is 42,258 bytes, which exceeds the notional 32,768.
- Lowering the cap to 128 alternatives does not cure this (about 35 KB).
- **Decision:** keep 256. Prove the enforced bounds with a real boot containing a maximal pool and a 28,672-byte sibling bulk key; it must reach READY and durable. Flag the notional-budget conflict for the Ultra Standards review.

## 4. Store seam (core/Store.lua, minimal and justified)

**Why core/Store.lua must change.** Store is the only SavedVariables owner, and the existing helpers cannot serve this feature safely:
- `Store.State` deep-copies the whole row unboundedly, so an in-session cyclic pool loops.
- `ReadStateV1` creates and shapes rows.
- `UpdateStateV1` returns true even for a transient row.
- The UI must not read or write `NexusDB`.

**What changes:**
- The nine public facade methods are unchanged.
- No new mutation entry is added. Writes still go through the counted `UpdateStateV1`.
- New code lives in one `do … end` block, so no file-level local is added (Lua 5.1 ceiling).

**Additions on `MainInternals.StoreAuthorityOwner`:**

1. **`PLAN_POOL_KEY = "flexiblePlanPoolV1"`.**

2. **`PlanPoolReadV1()`** is pure: it creates, shapes and invalidates nothing.
   - It returns `{mode, reason, ownerKey, root, present, copy, refusal, visited}`.
   - `mode` and `reason` are taken from `Store.StateWriteStatus()`, which is already pure, with two exceptions:
     - A read-only root (`ReadOnlyRoot.Class`) whose coordinator is not in a failed state gives `mode="readOnly"`.
     - Coordinator states INVALID, FUTURE_SCHEMA and DISPOSITION_* give `unavailable`.
   - Row resolution is raw: `rawget(chars, ownerKey)`. For known formats 3–5 with no canonical row, the carried `SavedFormat.OwnedNameRow` is used (read only), as `Store.State` does.
   - `root` is a Store-private serial per database identity (weak-keyed). It never exposes a raw reference.
   - `copy` is a bounded detached copy of the field, following `ReadOnlyRoot.BoundedCopy` rules plus an entry budget:
     - ≤ 16 tables, depth ≤ 2 below the record;
     - ≤ 16 root entries and ≤ 257 entries per child;
     - ≤ 3,871 entries visited in total;
     - keys are strings of ≤ 32 bytes or integers; values are number, boolean or string ≤ 64 bytes;
     - no metatables, aliases or cycles.
   - Before traversal, `FUTURE` is detected from the raw version and no copy is made.
   - Iteration uses `next` and `rawget` only; no metamethod is invoked.

3. **`IsDurableStateRowV1(row)`** is true only when all of these hold:
   - `row == NexusDB.chars[CurrentIdentity()]`;
   - the root is writable (not read-only);
   - the coordinator is READY or MUTATION_*.

4. **Snapshot exclusion.**
   - `Store.State` skips `PLAN_POOL_KEY` at the top level when building its snapshot.
   - `UpdateStateV1`'s `SameAsSnapshot` skips the same key at the top level.
   - Effects:
     - Pool saves cause no snapshot churn, and other readers see a stable identity.
     - Hot-path copies and compares do not grow by 1,286 entries.
     - A malformed in-session pool cannot loop `Store.State`.
   - No existing consumer reads this new key.

**Owner check.** Every pool operation requires `StoreAuthorityOwner.owner == injectedStore`. A mismatch refuses with `STORE_OWNER_MISMATCH`. There is no fallback to a global owner or to the injected `Store.State` (stub Stores keep their existing controller fallback for other writes).

## 5. Persistence owner: new `core/FlexiblePlanStore.lua`

It loads in the TOC after `core\FlexiblePlanModel.lua`. It is frame-free and contains no game reads. It exposes `Nexus.FlexiblePlanStore`:

- **`Encode(ids, rows, chosen)`** returns `record, bytes`. Absent groupId is stored as −1.
- **`Decode(copy)`** returns `pool, bytes`, or `nil, class`.
- **`New({store})`** returns a facade with three operations:

**`Read()`**
- Calls `PlanPoolReadV1` and decodes the copy.
- Returns `{mode, ownerKey, root, class, pool, bytes}`.

**`Save(session, observed)`** runs this transaction. `observed` is the prior Read receipt (bytes, owner key and root token), so identical saved bytes on a different character or database do not authorize a write. An unrelated or missing receipt refuses; no public consumer exists yet. The comparison below uses `observed.bytes` as `baselineBytes`:
1. Pre-read. Require all of:
   - `mode == "durable"`;
   - the class is ABSENT or CURRENT;
   - the stored bytes equal `baselineBytes`, or the pool is ABSENT with a nil baseline. A mismatch refuses with `SAVED_CHANGED`.
2. Encode the new record as fresh tables. An empty session encodes to nil, meaning clear.
3. Call `UpdateStateV1(mutator)`, wrapped in pcall. The mutator writes only when all of these hold:
   - `IsDurableStateRowV1(row)`, which rejects the transient fallback;
   - a nested `PlanPoolReadV1` returns the same bytes;
   - and then it captures `old = rawget(row, KEY)` and does `rawset(row, KEY, new)`.
4. Post-read. Require all of:
   - the class is CURRENT with bytes identical to the new record (or ABSENT after a clear);
   - mode is still durable;
   - `ownerKey` and `root` are unchanged.
5. On any failure:
   - A rollback mutator restores `old` only if the live value is still `new`.
   - It reports `SAVE_UNVERIFIED` and whether the restore held.
   - Saved state is never claimed.

A row created by `ResolveStateRowV1` before a mutator-level refusal is the established `FreshState` shape, as for every existing writer. The pre-read makes that path practically unreachable; it is flagged, not hidden.

**`Clear`** is `Save` of an empty session.

**No-side-effect guarantees.** The module never calls:
- the Adapter, `WishlistController`, Sync, Orb or `RegisterCurrentCharacter`;
- `BeginStoreMutationV1`.

## 6. Lifecycle modes

| Mode | Load | Save/Clear | Status |
|---|---|---|---|
| Pre-init, missing identity, or coordinator not ready (`loading`) | Disabled | Disabled | "Saved pools are available once Nexus has loaded." |
| `durable` (supported, or known 3–5 with carry) | Allowed | Allowed. The first write uses the existing carry copy. | Normal |
| `readOnly` (future/unverified/malformed settings format) | Allowed (detached copy) | Refused | "Saved data is read-only (format X); this pool can't be saved." |
| `unavailable` (invalid or disposition lifecycle, container or row) | Refused | Refused | Names the reason |

- **Migration:** none. Older builds keep the unknown key, which §8 test (b) verifies.
- **Format v1 within this build:** never rewritten other than by explicit Save.

## 7. Chooser semantics (`ui/FlexiblePlanChooser.lua`; wiring in `ui/WishlistEditor.lua`)

**Controls and text.**
- New buttons: `NexusFlexiblePlanSave` ("Save pool") and `NexusFlexiblePlanLoad` ("Load saved").
- The title drops "session only".
- The help text says: Hide keeps the pool until reload; Save stores it on this character; Load restores it.
- Reset still clears only the session.

**Status and dirty detection.**
- A persistence status line shows one of: "Not saved", "Unsaved changes", "Saved", "Loaded (k changed in catalog)", or a refusal reason.
- "Dirty" is computed from canonical bytes, recomputed only when `revision` changes. Pending count input also counts as dirty.
- The Store is read only on Show, Save and Load, never in `Refresh`.

**Load is explicit.** There is no auto-load. This keeps the existing session-lifecycle assertions true: after a reload, reopening the chooser shows an empty session until the player presses Load.

**Load procedure.**
1. Build `ids` and captured rows from the record: groupId −1 becomes nil, and the name is current-catalog decoration if the string is ≤ 256 bytes.
2. Build `FlexiblePlanModel.New`, and run `Choose` on the non-empty selection.
3. Assign everything at once only if all steps succeed. Otherwise refuse `LOAD_INVALID` and change nothing.
4. Count stale members against the current catalog: missing, changed quality/maxStack/group, or role fields present.

**Stale data.**
- Load may restore stale captured intent.
- **Open as new Wishlist draft** still goes through `PrepareNewExactDraft`, which refuses `CATALOG_CHANGED` while keeping the pool and counts.

**Editing after Load.**
- Set validates against the captured maxStack.
- Add captures current facts for the new member only.
- Existing members never refresh silently. Remove followed by re-add is the explicit way to adopt current facts, and the status says so.
- Save writes the captured facts unchanged.

**Saving.**
- Save updates the single pool; there is no new identity, fork or Save As.
- Save is refused with `COUNT_PENDING` while count input is pending.

**Dirty Load consent: popup `NEXUS_FLEXIBLE_PLAN_LOAD`.**
- Request fields: `{chooser instance, revision, savedBytes, ownerKey, root}`.
- Accept retires the request first. It installs only when all of these hold:
  - the request is still current;
  - the chooser revision is unchanged;
  - a fresh `Read()` returns the same bytes, owner and root.
  - Otherwise it refuses `LOAD_CHANGED` and preserves everything.
- Cancel retires only its own request.
- A late or replayed callback does nothing.
- A newer request hides the older one by request-identity data only.
- Load never calls any of the following, and never hides their dialogs:
  - `CancelApply`;
  - the controller;
  - `flexiblePlanRequest`.
- The editor's Save confirmation and its spaced retry survive.
- A pending replace request refuses `PLAN_CHANGED` because the revision moved.

**Clear consent: popup `NEXUS_FLEXIBLE_PLAN_CLEAR`.** Saving an empty session over a non-empty saved pool asks for confirmation, using the same single-use guards.

## 8. Vertical plan, paths and tests

All new test files go in `tools/run_prototype_tests.py`. Every listed test boots the real TOC through `tests/prototype/format5_support.lua` with synthetic data and a synthetic host. No private input is used.

**Commit 0 — documentation, before persistence code.**
- Record this contract in `docs/flexible-plans/PERSISTENCE.md`, with the compatibility rationale.
- Update `README.md`, `PLAYER_CHOICE_SLICE.md` and `docs/SAVED_FORMAT_COMPATIBILITY.md` (additive key).
- No behavioral test is needed for documentation.

**Stage A — codec, Store seam, owner Save/Load, reboot bounds.**
- Code: `core/Store.lua` (§4), `core/FlexiblePlanStore.lua`, `Nexus.toc`.
- RED first, on b7b4ff5:
  - The seam is nil.
  - Pool data written by the test is gone after `F.Reload`.
  - Injecting a cyclic table into an in-session row field makes `Store.State()` raise. This is a genuine overflow; the assertion is that no error occurs.

`tests/prototype/flexible_plan_persistence_codec.lua` covers:
- round-trip and canonical bytes;
- 256/257 alternatives, 79/80 copies, the maxStack limit, groupId −1;
- each malformed class;
- version 2 (FUTURE with no traversal) and version 0, `"1"` or missing;
- unknown and missing fields;
- 100k-entry arrays refused with `visited` ≤ budget + 1;
- the edge/byte formula checked against an independent charge count.

`tests/prototype/flexible_plan_persistence_store.lua` covers:
- **Retention:** Save, `F.Reload`, then Load gives equality, on both a v2 database and a format-5 carry database.
- **Byte preservation:** `F.Serialize` of every other key (row, settings, ledger, `genUnknown*`, archive) is byte-identical before and after.
- **Refusals leave data byte-identical:** future, unsupported and malformed records survive Save attempts and a reload unchanged; a read-only root allows Load and refuses Save; pre-init returns `loading`.
- **Transient and owner checks:**
  - Missing identity gives no write and an unpolluted transient row.
  - Re-running `dofile` on Store gives `STORE_OWNER_MISMATCH`.
- **Snapshot behavior:**
  - The snapshot excludes the key.
  - The snapshot identity is stable across Save.
  - A cyclic, aliased or metatable pool is refused by `Read`, while `Store.State` and `UpdateStateV1` keep working.
- **Rollback:** a forced post-read mismatch restores the previous record identity.
- **Startup bounds:** pump delta ≤ 22; a maximal pool plus a 28,672-byte sibling reaches READY and durable.
- **Repeated reads:** 200 `Read`s stay within the visit budget with no heap residue.
- **Downgrade:** following the Orb archive test pattern, the released and current peers keep the key across load, a write, logout and reload.

**Stage B — chooser presentation and dirty consent.**
- RED first: `NexusFlexiblePlanSave` is absent, so the button assertions fail on baseline.

`tests/prototype/flexible_plan_persistence_chooser.lua` covers:
- real entry, Add, Set, Save, Hide, then reload, reopen (empty) and Load;
- every status string;
- dirty Load Accept, Cancel, late and replayed callbacks, including an unrelated editor `PrepareApply` confirmation and a spacing-retry adapter, preserved by identity;
- the interplay with the replace request;
- after Load, a catalog drift makes Open refuse `CATALOG_CHANGED` while keeping the pool and counts;
- editing after Load, and remove + re-add;
- Clear consent;
- no side effects:
  - `H.actions` has no upload, assign, roll or orb-spend entries;
  - the coordinator stays READY with no mutation;
  - the ledger and settings are unchanged.

The existing `flexible_plan_player_choice` and `flexible_plan_editor_handoff` fixtures must still pass unedited, keeping their 863 handoff assertions. If any assertion pins the old "session only" text, stop and report it before editing; truthfulness requires the text change, so the edit would be text only, with the count and meaning kept and disclosed.

**Stage C — full gates.**
1. Run `python tools/ci_check.py` over the full inventory (530-plus tests plus the 3 new ones).
2. Run `python tools/build_package.py --check`, since the TOC changes.
3. Pin the exact final SHA.
4. Independent Opus 5.5 UltraCode Spec and Standards reviews, fixes, and re-review.
5. Coordinate the Store and runner overlap with #132 before composing.

Native client checks stay NOT_RUN; record that in the PR.

## 9. Flags

- **Notional row budget:** a worst-case Orb archive plus a maximal pool exceeds the notional 32,768 bytes per row. Only the aggregate bounds are enforced. 256 is kept; this needs a Standards ruling.
- **Damaged or future records block Save** until manual or future recovery. Nothing is deleted.
- **Store.State exclusion:** any diagnostic that dumps `Store.State` will omit the pool. This is intended; implementation must check row-walkers (SupportReport, DataCompaction, DiagnosticHistory) by search.
- **Facade count:** the comment says "nine exports", but the facade lists ten functions (`StateWriteStatus` included). This change adds none; the discrepancy is pre-existing and flagged only.
- **First-Save row creation:** a Save refused at mutator level may leave an empty row shaped like `FreshState`, the same as every existing `UpdateStateV1` writer.