# #144 family inventory: editors, build sharing, records and unit tooltip

Refs #144, #148. Dependencies: #142, #47, #132. Status: **documentation
evidence only**. This is a measured source inventory with a reachability
classification and a first-cohort proposal for Root review. The proposal is
**ADOPTION HELD**. No key, pack entry, consumer, test or runtime change is made
or implied, and all five families stay `PENDING`.

The machine-readable records, per-family totals, state indexes, passivity
dependencies and the proposal are in
[FAMILY_144_INVENTORY.json](FAMILY_144_INVENTORY.json). This page summarizes
them. Where the two differ, the JSON is authoritative.

This revision corrects the reviewed commit `9e5ca1aa` (JSON SHA-256
`0751adb9…`) against two independent reviews, Spec and Standards
(`reviewCorrections` in the JSON). No record ID, English text, source span,
class, worker label or exclusion was changed or removed.

## Source binding

| | Commit | Tree |
|---|---|---|
| Inventory head (reviewed documentation union) | `75178765a90c772c0521829708d365cc7dc3eb35` | `84b230e035a6d2853f48dc26666bf6c7510856e0` |
| Runtime evidence | `8393f5f4b61a0d62b5043b861539be868ebf80f6` | `8c1397ba8856d6d6973d5dd28e7fa0aecebb4ada` |

`git diff --name-only 8393f5f4..75178765` lists only `docs/` paths, so every
runtime, data, loader, test and tool blob cited here is the `8393f5f` blob.
Line numbers are git blob (LF) line numbers. Nothing here establishes new
runtime, native, linguistic or package acceptance.

**UI14 boundary:** the owner has approved 14 UI usability changes (all except
the Auto OFF rename) in other isolated worktrees. They do not change this
frozen `75178765` inventory, and this page does not claim they are complete.
Before any key is adopted, the affected English, layout and consumer facts
must be rebound to the accepted UI14 source, keeping the original Main Panel
and Setup references.

## Scope

The scope is the original
[#144](https://github.com/Viscerals/Better-Nexus/issues/144) body, read in full
from the saved GitHub read. The current cohort ledger explains only status.
#144 asks for the following in each family:

- ordinary, empty, loading, stale, invalid, refused, unavailable and success
  states, including dynamic rows, scope labels, counts, tooltips and detail
  text;
- presentation-only change: IDs, exact quality and role matches, saved
  identity, user text, encoded links, wire values and English matching
  operands stay unchanged;
- **reading, selection, language change or cancellation cannot assign, save,
  publish/share, send Sync, delete or spend resources**;
- long-text access, and unknown kept distinct from zero.

This inventory does not narrow, reinterpret or waive the no-action criterion.
Where current source breaks it, the break is recorded as an UNRESOLVED
dependency (see Passivity dependencies). Reporting a break does not pass the
gate.

The five families keep their `KEY_CONTEXT.windowFamilies` IDs:

| ID | Family | Declared paths |
|---|---|---|
| `editor` | Wishlist editor | `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua` (plus the editor, chooser and projection boundaries it actually reaches) |
| `overlay` | On-screen Wishlist | `ui/WishlistOverlay.lua` |
| `library` | Build Library | `ui/CommunityBuilds.lua`, `ui/CommunityRenderer.lua` (plus the controller, projection and Sync paths it actually reaches) |
| `leaderboard` | Leaderboard, including record detail | `ui/Leaderboard.lua` |
| `unit_tooltip` | Unit tooltip | `ui/Nameplate.lua` |

## Current localization state (at `8393f5f`)

- **English base:** 28 keys, 27 static texts and 1 template
  (`readout.charge_counts`).
- **Draft packs:** six packs of 27 `draft_unreviewed` entries each, for
  frFR, deDE, esES, plPL, ptBR and ruRU (162 entries in total).
- **Missing fallback:** `panel.button.options` is in no pack. It resolves to
  English as a counted `missing_candidate` fallback.
- **Cap:** `MAX_BASE_ENTRIES = 64` (`core/Localization.lua:147`). With 28
  used, 36 more fit. The 60-new-key dispatch limit in #144 does not raise that
  total.
- **Templates:** `SCHEMAS` (`core/Localization.lua:232-235`) holds one
  code-owned schema, and all its placeholders are typed `count`.
- **Status:** all 15 window families are `PENDING`. Competent language review
  is `UNASSIGNED` and localized native testing is `NOT_RUN`. English
  screenshots and the current 599 Lua / 84 Python checks are not linguistic or
  native acceptance.
- **Adopted keys:** each of the five families has **0 adopted keys**. That is
  the current key-adoption and consumer state only. Separately:
  - **One same-meaning reuse is proposed, not adopted.** ED-WR-1570-a (the
    "Assign Wishlist" hover heading at `ui/WishlistRenderer.lua:1570`) would
    reuse `panel.tooltip.assignment_heading`.
  - **The editor `notify` path cannot reach the seam at this source.**
    `UserText.Message` runs twice on it (`core/WishlistController.lua:163-165`
    and `ui/WishlistEditor.lua:158`). It reaches `Localization.Text` only in
    three cases: an exact `localizedReasons` key (`core/UserText.lua:96`), or
    after the exact prefix `^L%d+ -- ` (`:97-104`) or `^waiting: `
    (`:105-106`).

    All 69 `notify(...)` producers in `core/WishlistController.lua` begin with
    a literal `|cff…Nexus:|r` prefix, and `options.notify` is called only from
    `WC:163-165`. For example, `WC:1353-1354` wraps the adapter reason with the
    Nexus colour prefix and a final period. The English substring rewrites
    (`:114-125` and later) run on both passes but never call the seam. The real
    English coupling and the doubled "Details:" text remain.
  - **`Readout.AutoHoldText` can reach the seam.** Its path is
    `ui/WishlistRenderer.lua:2892-2910` → `ui/Readout.lua:424-429`. It passes
    the raw, unprefixed hold reason (`core/AutomationRuntime.lua:3029-3032`)
    into `UserText.Message`. A hold reason that is one of the five mapped
    codes would therefore reach `Localization.Text`. Which codes actually
    occur as hold reasons is **UNKNOWN**: it was not traced through
    `actionHold.SelectWait`.

  The worker-reported wrapper entries, including the two contradictory
  `WE:158` claims, are kept as `sharedWrappersAsReported` and are superseded
  by `families.ED.sharedWrappers`.

## Method

Units:

- A **lexical literal** is a Lua string literal outside comments. It is a lead
  only.
- A **source record** is one span producing one candidate text unit: a label,
  a tooltip line, a status sentence or one composed row. It sits at its origin
  `file:line`. There are 1,484 records, all retained.
- **Record IDs** have the form `<family>-<file>-<anchor>-<ordinal>`. The
  anchor lies within `[line, lineEnd]` and equals `line` except for
  **ED-WR-3132-a**. That record's documented interior anchor names `WR:3132`
  inside the full composed span `WR:3130-3133`, which is kept whole.
- **Worker visibility label** (`confirmed` or `conditional`) is kept as
  evidence but is **not used for counting**.
- **Reachability**, assigned per record from the predicates below, is the
  basis for every visible, state and independent-static total.

| Reachability | Predicate | Records |
|---|---|---:|
| `reachable` | worker label `confirmed`, with no qualifying note | 509 |
| `reachable_branch` | worker label `conditional`, with a stated ordinary branch predicate (refusal, failure, fallback, state) and no qualifier | 886 |
| `not_displayed` | verified by the author against source at `75178765` | 35 |
| `unknown` | not proven reachable or unreachable | 54 |

Sub-kinds of `not_displayed` (35 records):
- `hidden_before_render` (18):
  - The tracking line and candidate buttons are set at `WR:2304-2418`
    (including `candidateButtons[1]:Show()` at `WR:2412`). Later in the same
    synchronous `RefreshView` (`WR:2078`), with no return in between, they are
    hidden in both branches (`WR:2502-2513`).
  - ED-WC-1622-a is included because its only path is `AssociateCandidate`
    (`WC:1616-1664`), whose only callers are the hidden handlers `WR:2347` and
    `WR:2392`.
- `overwritten_in_bound_composition` (9):
  - The tab labels at `CR:3453/3459/3469` and `LD:1246-1248` are overwritten
    by `FullUIWorkspaces.BindTabs` (`FU:17-23`, `Nexus.toc:99`).
  - The button labels at `WR:1415/1424` are overwritten too. The same bytes
    passed at `WR:1416/1425` stay visible in the LoadingStatus hover
    (`LS:176-180`), so those two records remain reachable.
- `shadowed_declared_label` (3): `WE:258` and `WE:269` (the only show site,
  `WR:229-233`, sets `button1` first) and `WE:639` (re-set at `WE:414` before
  `WE:708`).
- `dead_branch` (1): `WR:816`. The loop runs `1..max(1,#candidates)` and
  there is always at least one candidate (`WR:718-764`).
- `legacy_hidden_no_show` (4): `CR:2012/2024/2034/2046` are hidden at
  `CR:2053-2057` and never shown.

Sub-kinds of `unknown` (54 records):
- `qualified_unverified` (13): notes that say practically, probably, appears,
  rarely or masked.
- `counterfactual_dependency_absent` (23): text shown only if a loaded module,
  function or projection is absent, or a developer assertion fires.
- `external_entry_only` (13): the Lock-in path, which has no in-addon caller.
- `initial_label_unverified` (5): `CR:1967/2091/2203` and `WR:1502/1591`.
  These are unknown because I did not prove the first-display order.

The 54 records the reviewer audited by keyword were re-triaged, not assumed
dead. 34 of them are now `not_displayed` and 20 `unknown`. Another 35 records
outside that audit are `not_displayed` or `unknown`. That the `unknown` total
is also 54 is coincidence; the JSON `reviewCorrections.qualificationCrossTab`
has the cross-table.

**Visible candidates** are the `reachable` and `reachable_branch` records:
1,395. They are candidates, not proven displays:
- 1,426 records are worker-reported and byte-verified, but their reachability
  was not re-derived one by one.
- 58 are author-read: the overlay and unit-tooltip records and the 35
  `not_displayed` records.

How the records were produced:
- I read and classified the Unit tooltip and On-screen Wishlist families
  myself.
- Five read-only workers classified the editor, library and leaderboard
  against one schema.
- Merge and correction steps are listed in the JSON `method.procedure`.
- Every record's literal fragments match the `75178765` blob at its span:
  1,467 exact and 17 composed.

## Measured totals

Lexical lead, a separate unit from the records (literals counted on the git
blobs):

| File | Blob | Lines | Literals | With space and word |
|---|---|---:|---:|---:|
| `ui/WishlistEditor.lua` | `643d6126` | 1,310 | 334 | 97 |
| `ui/WishlistRenderer.lua` | `07d9f436` | 3,529 | 1,168 | 378 |
| `ui/WishlistOverlay.lua` | `9fc8ce51` | 522 | 71 | 11 |
| `ui/CommunityBuilds.lua` | `90f54040` | 427 | 86 | 9 |
| `ui/CommunityRenderer.lua` | `4710a9e4` | 4,723 | 1,532 | 316 |
| `ui/Leaderboard.lua` | `e61fc3b9` | 1,699 | 722 | 139 |
| `ui/Nameplate.lua` | `e6dd9d87` | 170 | 30 | 5 |
| **Total** | | **12,380** | **3,943** | **955** |

Source records by reachability. The last three columns cover visible
candidates only:

| Family | Source records | reachable | reachable_branch | not_displayed | unknown | **Visible candidates** | Distinct English (visible) | Static / template / fragment join / wrapper (visible) | Independent static¹ (visible) |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| editor | 649 | 261 | 354 | 24 | 10 | **615** | 548 | 316 / 103 / 191 / 5 | 195 |
| overlay | 14 | 12 | 2 | 0 | 0 | **14** | 13 | 7 / 1 / 6 / 0 | 4 |
| library | 584 | 165 | 372 | 7 | 40 | **537** | 426 | 404 / 45 / 83 / 5 | 370 |
| leaderboard | 228 | 62 | 158 | 4 | 4 | **220** | 168 | 77 / 35 / 108 / 0 | 61 |
| unit_tooltip | 9 | 9 | 0 | 0 | 0 | **9** | 9 | 4 / 4 / 1 / 0 | 1 |
| **All** | **1,484** | **509** | **886** | **35** | **54** | **1,395** | **1,092** | | **631** |

¹ Independent static means a static record with no dependency, no coupling and
no exception. The 631 visible-candidate records hold 487 distinct English
texts. Over all source records the figures are 677 independent static records
and 1,147 distinct English texts.

Other totals:
- 135 excluded coupled literals.
- 21 origin spans shown by more than one family: 15 Sync reasons shared by the
  library and leaderboard, and 6 `FullUIWorkspaces` navigation texts shared by
  three families.
- **Shared-key reuse:** 0 adopted and 1 proposed (ED-WR-1570-a →
  `panel.tooltip.assignment_heading`).

Visible-candidate records per state. These indexes are derived only from
record `states`; a state with records is not a completed state:

| Family | ordinary | empty | loading | stale | invalid | refused | unavailable | success |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| editor | 260 | 38 | 41 | 56 | 66 | 147 | 95 | 42 |
| overlay | 9 | 1 | 1 | 0 | 0 | 0 | 5 | 1 |
| library | 202 | 28 | 85 | 23 | 72 | 118 | 70 | 31 |
| leaderboard | 77 | 9 | 21 | 8 | 48 | 22 | 43 | 4 |
| unit_tooltip | 9 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |

The JSON also keeps `stateRecordCountsAllSource` and `stateIndexNotVisible`.
- **Editor invalid:** 73 over all source records, as the records state; 66 of
  them are visible candidates. ED-WR-2036-a is the "unknown reason" fallback
  inside the `Unavailable:` hover line (`WR:2035-2036`). It stays
  `unavailable` only, and is no longer indexed as invalid. The old 74 came
  from a worker-supplied list, which is kept as `stateCoverageAsReported`.
- **Overlay:** has no stale, invalid or refused texts. Loading or an
  unreadable plan shows the same "No wishlist set" as having no Wishlist
  (WO:372-373).
- **Unit tooltip:** unknown players get no lines (NP:81).

**Candidate surfaces:** each worker-reported candidate surface now carries
`derivedFromRecordIds` (records, static, non-static, visible candidates,
not-displayed-or-unknown) computed from its `recordIds`. The worker's own
`staticCount`/`dynamicCount` are kept under `workerDeclared` with their unit
marked unspecified. These six mismatches were named in review:

| Surface | Worker declared (static + dynamic) | Derived from `recordIds` |
|---|---|---|
| editor role picker | 28 + 7 | 41 records: 24 static, 17 non-static |
| editor Import/Export | 14 + 8 | 24: 10 / 14 |
| editor Manage/selectors | 10 + 22 | 35: 4 / 31 |
| editor confirmations | 14 + 2 | 20: 10 / 10 |
| library toolbar | 40 + 1 | 40: 40 / 0 |
| unit tooltip lines | 2 + 6 | 2: 2 / 0 |

To reproduce:

```sh
python -I -c "import json,collections as c;d=json.load(open('docs/localization/FAMILY_144_INVENTORY.json',encoding='utf-8'));R=d['records'];V=[r for r in R if r['reachability'] in('reachable','reachable_branch')];print(len(R),c.Counter(r['reachability'] for r in R),len(V),len({r['english'] for r in V}))"
```

## Passivity dependencies (UNRESOLVED)

These are pre-existing source behaviours that conflict with the strict #144
criterion. Each stays UNRESOLVED until Root resolves it or explicitly scopes
the criterion. The planned controls are expected to fail (red) at
`75178765`; none was run.

- **PD-1 (library, entry from leaderboard):** opening a build from the
  Leaderboard (`LD:940-946`) calls `CommunityBuilds.ShowBuild`
  (`ui/CommunityBuilds.lua:401-411`).
  - For an existing build with no Echoes it calls `RequestLoadout` (`:409`),
    then `CommunityController.RequestLoadout` (`CC:846-849`), then
    `Sync.RequestLoadout` (`core/Sync.lua:2078-2085`), which calls
    `Session.QueueLegacyRecovery`. It **queues** one background recovery
    request rather than transmitting directly.
  - A queued request is still Sync work caused by opening, so it violates the
    criterion as written.
  - This is separate from `CR:2640-2642` (a detail render with
    `hasLoadout=false`), whose reachability under the projection is UNKNOWN.
  - Owner: Root, with the Sync owner.
- **PD-2 (overlay; shared GameAdapter read):** the read path is
  `WishlistOverlay.Refresh` (`WO:368`) → `AcquirePresentation` (`:289`) →
  `ReadAssignedPlan` (`:243-248`) → `GameAdapter.AssignedWishlist`
  (`GA:3877-3878`) → `ReadAssignedWishlist` (`:3859`) → `A.Wishlist`.
  - The write fires when all of these hold:
    - the slots are known (`GA:3673`);
    - the active slot is in range (`GA:3680-3685`);
    - no association resolves for that slot (`GA:3708-3709`) and none is
      stored (`GA:3723-3727`);
    - it is not a kept Saved Build, the loadout is populated, and a first-run
      starter resolves with a storable record (`GA:3733-3737`).
  - Then `UpdateStoreState` persists `loadoutWishlists[activeSlot]`, clears
    `firstRunWishlist`, records `WishlistRoles.Wrote` twice and marks the
    projection dirty (`GA:3738-3745`).
  - This is a conditional persisted association mutation on a display read,
    not an approved SavedVariables exception.
  - Owner: Root, with the #132 assignment owner.
- **PD-3 (leaderboard):** selecting a row with an incomplete record queues the
  same recovery request (`LD:386-391`).
- **PD-4 (unit tooltip):** a hover can be the first caller of one-time local
  DPS SavedVariables migrations (`core/DpsCapture.lua:3581-3584`).

## Dependencies and overlaps

- **#142** (426 source records): user-text and game-name placeholders, nested
  reasons, k/M number formats (NP:30-31, LD:146-148, CR:560-569), ordinals
  (NP:35-41), plurals (WE:363, WC:532, CC:3045), and time and date.
- **#47** (editor 14, library 1): Plan alternatives and the
  FlexiblePlanChooser refusals reached from the editor, and the Share
  role-limit refusal at CC:3002.
- **#132** (editor 106, library 22):
  - assignment and upload-context refusals and save-result lines;
  - the Auto-ON consent popup (JT:110-114);
  - the Share role refusals (CC:2015-2094, 2191-2198);
  - the persisted English mirror title and description (CC:1287, 1373, 1379);
  - PD-2.

## Coupled surfaces (not repaired)

- **Unit tooltip caption.** `ui/Nameplate.lua:45` defines
  `BADGE = "|cff7fd5ffNexus user|r"`. It is both the caption (NP:94/96) and
  the duplicate marker that NP:89 compares by prefix, and a test helper
  prefix-matches "Nexus user". It is not an independent safe static key (D3).
- **Sync mode sentences** (SM:27-28) are compared byte for byte (SM:163-164;
  CR:2304). "sync queue full" and `find('full')` are compared at SS:714/717,
  ST:444, SY:1585/1656 and DpsCapture:3201.
- **Copy reasons.** CE:459/469/478 are compared at LD:1055-1058.
- **Editor rewrites.** The `T.Message` English substring rewrites and the
  double pass apply on the editor `notify` path. The save-result map at
  WR:3165-3207 is keyed by the writer's English reasons.
- **Labels that are also values.**
  - "Saved Build" is both a label and a matched value (CC:2018, 2188).
  - "Community" is both a title and a window key (CB:415, 420).
  - CC:3076 searches for "too large", and `%.+$` strips English sentence
    periods.
- **Search and sort.** These run over game names (WR:144-177, 2627-2636;
  WO:399-406), and the operands stay game data.
- **Navigation labels.** `FullUIWorkspaces` relabels the tabs, so the
  overwritten labels are `not_displayed`.

## Pre-existing findings for Root routing (not repaired)

- **No-action:** PD-1 to PD-4 above, plus:
  - CR:2104-2106: an explicit Copy queues `RequestLoadout`;
  - CR:2640-2642: reachability UNKNOWN;
  - the library link box saves when Enter is pressed;
  - admin removal has no confirmation;
  - editor selector, undo and Confirm rows change state without confirmation.
- **Unknown shown as zero:**
  - overlay: unread ownership shows as 0;
  - Leaderboard: unknown DPS becomes 0 (LD:146, DpsCapture:3348), and unknown
    and zero durations both show "—";
  - library: `DpsText` (CR:561) turns a missing value into 0;
  - editor: the Manage and delete-confirm rows use `or 0`, "Locked (0/6)"
    and "Showing 0-0 of 0" appear for unknown data, and an unknown quality is
    labelled "Common".
- **Long text cut off with no alternative:**
  - overlay rows and the 90-row cap;
  - the unit-tooltip title, cut at 28 characters;
  - Leaderboard cells;
  - library card lines;
  - the Share-form status box (334×96).
- **Dead, stale or misleading text:**
  - the `not_displayed` records;
  - "Saved Build 'None'" (WR:652);
  - the old "Load into Editor" button name (CC:3994);
  - "Both records records" in the Leaderboard;
  - the doubled "Details:" text;
  - list failures that show no error.

## Known gaps

- CandidateEvidence reasons reaching WC:1277 are not traced.
- FlexiblePlanChooser screens beyond the refusals are not inventoried.
- Raw Sync, transport and catalog reasons are sampled.
- Whether library `SetFilter` persists its setting is not traced.
- The native slider Low/High text is unverified.
- Help pages and LoadingStatus phases belong to other families.
- Reachability of the 1,426 worker-reported records is not re-derived one by
  one.
- Which hold reasons reach `AutoHoldText` is UNKNOWN.

## First-cohort proposal (ADOPTION HELD; nothing adopted)

**Family `library`, bounded surface: the Build Library detail status panel**
(`ui/CommunityRenderer.lua:2447-2498`, `DETAIL_STATUS` and
`ShowDetailStatus`).

Why this surface:
- All texts are static, with no user, game, wire or identity value, no markup
  and no `|` byte. Runtime code never compares, parses, stores or sends them.
- The texts are selected by code: `CommunityProjection.Detail` returns
  `unavailable`, `invalid` or `incomplete` (CP:443-457), and the renderer adds
  `pending` and `none` (CR:2507-2531).
- It covers four #144 states through the actual renderer.
- Existing English tests pin it (`community_cursor_readers.lua:148, 193-194,
  224`).
- It has no #142, #47 or #132 text dependency.

It is **not** dependency-free: its entry points carry PD-1.

| Proposed key | English (exact bytes) | Source | Kind codes |
|---|---|---|---|
| `library.heading.detail_loading` | Loading build details... | CR:2451 | pending |
| `library.body.detail_loading` | The build library is still being prepared. The selected build appears here when it is ready. | CR:2452 | pending |
| `library.heading.detail_unavailable` | Build not available | CR:2453, CR:2455 | unavailable, invalid, unknown-kind fallback |
| `library.body.detail_not_in_library` | This build is not in your build library. It may have been removed, not received yet, or not accepted. | CR:2454 | unavailable, unknown-kind fallback |
| `library.body.detail_invalid` | The selected build record is invalid and cannot be shown. | CR:2456 | invalid |
| `library.heading.detail_incomplete` | Build not available yet | CR:2457 | incomplete |
| `library.body.detail_incomplete` | The full Echo list for this build is still arriving. | CR:2458 | incomplete |
| `library.heading.no_selection` | No build selected | CR:2460 | none |
| `library.body.no_selection` | Select a build on the left to see its Echoes, DPS records and owner. Selecting a build only reads it; nothing is sent, saved or assigned. | CR:2461 | none |

- **Size:** 9 proposed English keys, giving 28 + 9 = 37 of 64 with 27
  remaining. Splitting the shared heading (D2) would make 10 keys and 38 of
  64.
- **Packs:** no pack entries are commissioned. The six packs would resolve
  these keys to English as 54 counted `missing_candidate` fallbacks.
- **Last body text:** the last body states a consequence that PD-1 currently
  contradicts for one entry point. Its English and meaning are unchanged here.

Entry points this cohort must cover:

| Entry point | Path | Kinds | Known side effect |
|---|---|---|---|
| Build Library open | `CommunityBuilds.Show` (CB:394-399) → `RefreshDetailPanel(SelectedId())` (CR:4668) | all five | none found |
| List refresh while pending | CR:4213, CR:4243 | pending | none found |
| **Open from Leaderboard: `ShowBuild(id)`** | LD:940-946 → CB:401-411 | incomplete, unavailable, invalid, pending | **CB:407-410 queues `RequestLoadout` (PD-1): expected baseline RED for `incomplete`** |
| Detail render with `hasLoadout=false` | CR:2640-2642 (only after `HideDetailStatus`) | none | `RequestLoadout`; reachability UNKNOWN |

State coverage:
- **Covered:** empty, loading, unavailable and invalid.
- **Excluded:** ordinary (needs #142), stale (no such state), refused and
  success (other surfaces).
- Build Library stays `PENDING`.

Proposed future work (not done here): a consumer that keys `DETAIL_STATUS` by
the unchanged kind codes and resolves `{headingKey, bodyKey}` when
`ShowDetailStatus` runs, falling back to the current English; 9 English data
rows and `KEY_CONTEXT` rows; the unchanged `community_cursor_readers.lua`; a
new focused renderer test registered in `tools/run_prototype_tests.py` that
drives all five kinds, an unknown kind and every entry point above; and
catalog/validator rows under the #147 plan.

Acceptance predicate for Root review:

1. **P1:** these 9 keys (or 10 under D2), contract-valid, with English
   byte-equal to CR:2451-2461, and a base of 64 entries or fewer.
2. **P2:** under English, every title and text is byte-identical for all kinds
   and the fallback. Existing tests pass unchanged.
3. **P3:** a fixture pack reaches `ShowDetailStatus` through the real renderer.
   Missing entries fall back to English and are counted. No draft text is
   added.
4. **P4:** `status.kind`, the kind codes, the projection reason codes and the
   selection identity are unchanged.
5. **P5 (strict no-action; the original #144 criterion, unchanged):** for
   every entry point and kind, opening, selecting, refreshing, cancelling and
   changing language make no `Sync.RequestLoadout` call or other Sync send or
   queue, and no SavedVariables write beyond the existing selection state.
   They assign, save, share, delete and spend nothing.
   - The `ShowBuild`/incomplete case is expected RED at the base.
   - P5 passes only after Root resolves PD-1 or explicitly scopes the
     criterion. Reporting the violation does not pass P5.
6. **P6 (long text):** a 256-byte fixture body stays word-wrapped and
   `GetText()` returns the full text. Native fit is `NOT_RUN`.
7. **P7:** the family stays `PENDING`. Competent review stays `UNASSIGNED` and
   localized native stays `NOT_RUN`.
8. **P8:** full CI on the final source pin, then independent Spec and
   Standards review with fixes and re-review.
9. **P9:** rebind the English, layout and consumer facts to the accepted UI14
   source before any adoption.

Alternatives considered and not chosen:
- **Editor Display Settings:** covers only the ordinary state. The hover
  sentence is split across WR:1695-1696 (D9).
- **Overlay controls:** WO:197 contains the invariant `/nexus overlay` command,
  and the rows need #142.
- **Leaderboard chrome:** about 41 keys, which is over the cap. It is
  ordinary-only, and its tab literals are `not_displayed`.
- **Library Sync mode dialog:** byte-coupled mode sentences, and #142.
- **Library Edit Build popup:** its outcomes need #142.
- **Unit tooltip:** 9 records, of which 4 are static and only **1** is
  independent static (UT-NP-0121-a). UT-NP-0123-a has a test-helper prefix
  coupling, UT-NP-0045-a has the NP:89 marker coupling, and UT-NP-0103-a
  depends on #142.

## Future controls (requirements only; not executed)

- **Identity:**
  - English byte identity for adopted texts;
  - codes, IDs, Echo names, authored text, player names, encoded strings and
    wire values unchanged under a fixture pack;
  - search, filter and sort results unchanged.
- **No action:** hooks on `Nexus.Sync.RequestLoadout`, the Sync queue and the
  Store writer for every entry point, including `ShowBuild`/incomplete,
  overlay refresh under the PD-2 preconditions, Leaderboard row selection and
  first hover. The expected baseline RED cases are planned, not run.
- **Long text:** 256-byte fixtures keep the existing wrap, scroll or full-text
  tooltip.
- **Unknown versus zero:** the unknown form, never 0.
- **Ownership:**
  - Root assigns each family's work.
  - The #132 and #47 owners are consulted for their sites.
  - Sync owners supply reason codes (D5).
  - The FullUIWorkspaces labels need one owner (D10).

## Root decisions

- **D1:** accept, amend or reject the held cohort.
- **D2:** one or two "Build not available" headings.
- **D3:** the unit-tooltip caption marker.
- **D4:** cap allocation. 36 entries remain for #143, #144 and #145. The
  visible candidates hold 1,092 distinct English texts (487 of them
  independent static), so the 64-entry cap cannot hold #144.
- **D5:** reason codes for the byte-coupled texts.
- **D6:** with #132, the persisted English mirror titles.
- **D7:** `not_displayed` literals are excluded from adoption. Whether to
  remove them is outside localization.
- **D8:** route the pre-existing findings.
- **D9:** the editor split sentence, if that alternative is chosen.
- **D10:** the owner of the shared navigation labels.
- **D11:** resolve or explicitly scope PD-1 to PD-4. The cohort stays held
  until PD-1 is decided.

## Checks

Run (mechanical, schema, privacy and consistency; the scripts stay outside the
repository):
- HEAD and tree, and runtime-blob identity.
- English and pack counts.
- The lexical scan.
- ID pattern and uniqueness. The anchor lies within its span, and the only
  exception is ED-WR-3132-a.
- Byte verification of every record against the `75178765` blob.
- Record IDs, English, spans, classes, worker labels, states and exclusions
  unchanged from the reviewed JSON.
- Every family total, state index, candidate subcount, the measured totals and
  the reuse summary recomputed from the records.
- Wrapper classification is consistent.
- Cohort hold, P5 and the cap arithmetic.
- Passivity items are UNRESOLVED.
- The current-state facts are retained.
- This page's headline numbers match the JSON.
- Privacy scan.

Not run:
- the 599 Lua / 84 Python suite;
- the planned red controls;
- native client testing;
- linguistic review;
- package and TOC checks.
