# #144 family inventory: editors, build sharing, records and unit tooltip

Refs #144, #148. Dependencies: #142, #47, #132. Status: **documentation
evidence only**. This is a measured inventory and a first-cohort proposal for
Root review. No key, pack entry, consumer, test or runtime change is made or
implied. All five families stay `PENDING`.

The machine-readable record set, per-family totals, state lists and the
proposal are in [FAMILY_144_INVENTORY.json](FAMILY_144_INVENTORY.json). This
page summarizes them; the JSON is authoritative where they differ.

## Source binding

| | Commit | Tree |
|---|---|---|
| Inventory head (reviewed documentation union) | `75178765a90c772c0521829708d365cc7dc3eb35` | `84b230e035a6d2853f48dc26666bf6c7510856e0` |
| Runtime evidence | `8393f5f4b61a0d62b5043b861539be868ebf80f6` | `8c1397ba8856d6d6973d5dd28e7fa0aecebb4ada` |

`git diff --name-only 8393f5f4..75178765` lists only `docs/` paths, so every
runtime, data, loader, test and tool blob cited here is the `8393f5f` blob.
Line numbers are git blob (LF) line numbers. Nothing here establishes new
runtime, native, linguistic or package acceptance.

## Scope

The scope is the original
[#144](https://github.com/Viscerals/Better-Nexus/issues/144) body. It was read
in full from the saved GitHub read, and the current cohort ledger explains only
status. #144 asks for the following in each family:

- ordinary, empty, loading, stale, invalid, refused, unavailable and success
  states, including dynamic rows, scope labels, counts, tooltips and detail
  text;
- presentation-only change: IDs, exact quality and role matches, saved
  identity, user text, encoded links, wire values and English matching
  operands stay unchanged;
- no-action reading, selection, language change and cancellation;
- long-text access, and unknown kept distinct from zero.

The five families keep their `KEY_CONTEXT.windowFamilies` IDs:

| ID | Family | Declared paths | Traced where actually reached |
|---|---|---|---|
| `editor` | Wishlist editor | `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua` | WishlistController, GameAdapter, WishlistModel, FlexiblePlanChooser, JournalTab consent, UserText, Panel, LoadingStatus, FullUIWorkspaces, Readout |
| `overlay` | On-screen Wishlist | `ui/WishlistOverlay.lua` | none needed |
| `library` | Build Library | `ui/CommunityBuilds.lua`, `ui/CommunityRenderer.lua` | CommunityController, CommunityProjection, ViewProjections, Identity, SyncModePolicy, SyncSession, Sync, SyncTransport, LoadingStatus, FullUIWorkspaces |
| `leaderboard` | Leaderboard, including record detail | `ui/Leaderboard.lua` | UserText, Identity, DpsCapture, CandidateEvidence, Sync*, ViewProjections, FullUIWorkspaces |
| `unit_tooltip` | Unit tooltip | `ui/Nameplate.lua` | DpsCapture, SyncSession, BuildCatalog, Identity |

## Current localization state (at `8393f5f`)

- **English base:** 28 keys, 27 static texts and 1 template
  (`readout.charge_counts`).
- **Draft packs:** six packs of 27 `draft_unreviewed` entries each, for
  frFR, deDE, esES, plPL, ptBR and ruRU (162 entries in total). I verified
  these counts by parsing `data/LocalizationEnglish.lua` and
  `data/LocalizationPacks.lua`.
- **Missing fallback:** `panel.button.options` is in no pack. It resolves to
  English as a counted `missing_candidate` fallback.
- **Cap:** `MAX_BASE_ENTRIES = 64` (`core/Localization.lua:147`). With 28
  used, 36 more English entries fit. The 60-new-key dispatch limit in #144
  does not raise that total.
- **Templates:** `SCHEMAS` (`core/Localization.lua:232-235`) holds one
  code-owned schema, and all of its placeholders are typed `count`. Any other
  placeholder type needs code work under #142.
- **Status:** all 15 window families are `PENDING`. Competent language review
  is `UNASSIGNED` and localized native testing is `NOT_RUN`. English
  screenshots and the current 599 Lua / 84 Python checks are not linguistic
  or native acceptance.
- **Adopted keys:** each of the five families has 0 adopted keys. That figure
  is the current key-adoption and consumer state only. It does not mean these
  windows never show seam text. `UserText.Message` resolves five reason codes
  through `Nexus.Localization.Text` (`core/UserText.lua:52-61`, `:78-93`). The
  editor's notify path calls it twice
  (`core/WishlistController.lua:165`, `ui/WishlistEditor.lua:158`), and it is
  also reached through `Readout.AutoHoldText` (`ui/WishlistRenderer.lua:2908`).

## Method

The units are deliberately separate:

- A **lexical literal** is a Lua string literal outside comments. It is a lead
  only and is never counted as visible or translatable.
- A **record** is one source span that produces one player-visible text unit:
  a label, a tooltip line, a status sentence or one composed row. A composed
  sentence is one record, with a `{placeholder}` for each runtime value. A
  record sits at its **origin** `file:line`, which can be a traced `core/` or
  shared `ui/` file, under the family whose surface shows it. Each record
  carries:
  - its exact English, or a reproducible byte shape;
  - its surface, states and class (`static`, `template`, `fragment_join` or
    `shared_wrapper`);
  - its argument schema and identity exclusions;
  - any coupling (matching or branching on its bytes);
  - its producer-to-sink path, dependencies, shared-key reuse and exception
    justification.
- **Visibility** is either `confirmed`, meaning the normal path reaches a
  sink, or `conditional`, meaning the text appears only in an identified
  branch (refusal, failure, fallback or debug) or is shadowed or hidden in the
  current composition. Both are visible-reachable. Neither is lexical-only.
- An **excludedCoupled** entry is a literal that must not be translated
  because code matches, keys, stores or sends it.

Procedure:

1. I read and classified `ui/Nameplate.lua` and `ui/WishlistOverlay.lua` in
   full myself.
2. Five read-only workers classified the editor, library and leaderboard
   files against one written record schema. The editor was split at
   `ui/WishlistRenderer.lua` line 1100 and the library at
   `ui/CommunityRenderer.lua` line 2360.
3. A merge step made these changes:
   - It merged 49 IDs that both halves of a family recorded. Their states and
     dependencies were combined; four of them differed only in placeholder
     names.
   - It moved 7 records cited one line off to the line that holds their bytes:
     ED-WC-0628-a, ED-WC-0657-a, ED-WC-1719-a, ED-GA-2634-a, ED-GA-3242-a,
     ED-GA-3248-a and LD-DC-3348-a.
   - It corrected 3 records:
     - ED-WC-2064-a: wrong line range.
     - ED-WR-3308-a: an inlined variable value restored as `{again}`.
     - LB-CR-2555-a: origin constant at CR:12.
   - It restored decoded newlines to the source escape form.
4. Every record was checked byte for byte against the git blob at its cited
   lines. Of the 1,484 records, 1,467 are **exact** (the text is contiguous in
   source) and 17 are **composed** (the text is assembled from literal pieces
   that code joins inside the span). None failed.
5. I spot-checked these spans against source myself:
   - Library and projection: CR:2092-2108, CR:2450-2533, CR:2612-2643,
     CP:440-458, CC:1285-1288.
   - Leaderboard: LD:145-148, LD:386-391, LD:1055-1058.
   - Editor: WE:156-159, WC:163-166, WR:836-1010, WR:1684-1698.
   - Shared: SM:160-166, FU:8-25, SyncSession:224-240.
   - Unit tooltip: all of NP, plus DpsCapture:3581-3600 and its migrations.
   - Overlay: all of WO.

   Every claim I checked held. The rest of the visibility, state, coupling
   and dependency classification is worker-produced and byte-verified, but I
   did not re-derive it record by record. It is reviewable evidence, not
   acceptance.

## Measured totals

Lexical lead, from a Lua 5.1 string-literal scan of the git blobs. These are
not visible-text counts:

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

The historical 25,355-literal lead in [INVENTORY.md](INVENTORY.md) used
another pin and scanner and is not comparable.

Visible-text records, a separate unit:

| Family | Records | Confirmed | Conditional | At family paths | At traced origins | Distinct English | Static / template / fragment join / wrapper | Independent static¹ | Coupled | Excluded coupled |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| editor | 649 | 261 | 388 | 409 | 240 | 573 | 332 / 114 / 198 / 5 | 209 | 112 | 44 |
| overlay | 14 | 12 | 2 | 14 | 0 | 13 | 7 / 1 / 6 / 0 | 4 | 5 | 4 |
| library | 584 | 165 | 419 | 357 | 227 | 455 | 444 / 48 / 87 / 5 | 397 | 34 | 62 |
| leaderboard | 228 | 62 | 166 | 148 | 80 | 175 | 82 / 36 / 110 / 0 | 66 | 5 | 19 |
| unit_tooltip | 9 | 9 | 0 | 9 | 0 | 9 | 4 / 4 / 1 / 0 | 1 | 6 | 6 |
| **All** | **1,484** | **509** | **975** | | | **1,147** | | **677** | | **135** |

¹ Independent static means a static record with no dependency, no coupling
and no exception. Distinct across all families: 514.

21 origin spans are shown by more than one family:
- 15 Sync reasons from `core/SyncModePolicy.lua`, `core/SyncSession.lua`,
  `core/SyncTransport.lua` and `core/Sync.lua`, shown by both the library and
  the leaderboard;
- 6 navigation labels and descriptions from `ui/FullUIWorkspaces.lua:9-11`,
  shown by the editor, library and leaderboard.

None of the 28 existing keys has the same meaning as any record. Shared-key
reuse is 0.

Records per state. A state with records is **not** a completed state:

| Family | ordinary | empty | loading | stale | invalid | refused | unavailable | success |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| editor | 273 | 40 | 42 | 56 | 74 | 153 | 98 | 46 |
| overlay | 9 | 1 | 1 | 0 | 0 | 0 | 5 | 1 |
| library | 222 | 35 | 90 | 23 | 73 | 126 | 76 | 33 |
| leaderboard | 82 | 9 | 22 | 8 | 48 | 23 | 44 | 4 |
| unit_tooltip | 9 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |

The JSON gives the source evidence for each missing state:
- **Overlay:** has no stale, invalid or refused texts. An empty assigned
  Wishlist hides every row with no text. Loading and an unreadable plan show
  the same "No wishlist set" text as having no Wishlist (WO:372-373).
- **Unit tooltip:** unknown players get no lines (NP:81). It has no loading,
  refused or success state.

### Reproduce

```sh
python -I -c "import json,collections as c;d=json.load(open('docs/localization/FAMILY_144_INVENTORY.json',encoding='utf-8'));R=d['records'];print(len(R),c.Counter(r['id'][:2] for r in R),c.Counter(r['visibility'] for r in R),len({r['english'] for r in R}))"
```

The lexical totals come from the scanner described in `method.lexicalScanner`,
run on `git cat-file -p HEAD:<path>`.

## Dependencies and overlaps

- **#142** (426 records: editor 170, overlay 7, library 115, leaderboard 128,
  unit tooltip 6). These records need placeholder types or grammar that the
  seam does not have yet:
  - user-text names and titles;
  - game Echo names;
  - nested reason fragments;
  - number abbreviations k/M (NP:30-31, LD:146-148, CR:560-569);
  - ordinals (NP:35-41);
  - plurals (WE:363, WC:532, CC:3045);
  - time and date (Leaderboard).

  Resumes when #142 accepts a placeholder-type and grammar contract beyond
  `count`.
- **#47** (editor 14, library 1): Plan alternatives and the FlexiblePlanChooser
  refusals reached from the editor (FC:25-36, 118-127, 157-161, 280-292 via
  WE:1039), and the Share role-limit refusal at CC:3002.
- **#132** (editor 106, library 22):
  - assignment and upload-context refusals and save-result lines;
  - the Auto-ON consent popup (JT:110-114, reached from WE:770);
  - the Share role refusals (CC:2015-2094, 2191-2198);
  - the persisted English mirror title and description (CC:1287, 1373, 1379),
    which CC:1354 and ViewProjections:801 also use.

## Coupled surfaces (not repaired)

- **Unit tooltip caption.** `ui/Nameplate.lua:45` defines
  `BADGE = "|cff7fd5ffNexus user|r"`. It is both the visible caption (NP:94/96)
  and the duplicate-augmentation marker that NP:89 compares by prefix.
  `tests/prototype/tooltip_marker_name_guild.lua:49` also prefix-matches
  "Nexus user". It is **not** an independent safe static key: the emitted
  bytes and the comparison operand must be one session-resolved value, and a
  translation must not collide with name or guild lines. NP:123 has a
  different colour prefix and is not the marker, but the same test helper's
  plain-text match would also accept it.
- **Sync mode sentences** (SM:27-28) are shown and also compared byte for byte
  (`IsModeReason`, SM:163-164; CR:2304). "sync queue full" and `find('full')`
  are compared at SS:714/717, ST:444, SY:1585/1656 and DpsCapture:3201.
- **Copy reasons.** "historical locked evidence is not current copy authority"
  (CE:459/469/478) is shown after "Copy unavailable:" and compared at
  LD:1055-1058.
- **`T.Message` rewrites.** `T.Message` rewrites controller messages by English
  substring, and it runs twice on the editor path (WC:165 and WE:158). The
  save-result reason map at WR:3165-3207 is keyed by the writer's English
  reasons.
- **Labels that are also values.**
  - "Saved Build" is both a source label and a matched value (CC:2018, 2188).
  - "Community" is both a title and a window key (CB:415, 420).
  - CC:3076 searches a Sync reason for "too large", and four sites strip
    English sentence periods with the pattern `%.+$`.
- **Search and sort.** Echo-name search and sort use ASCII `lower`, plain
  `find` and byte order over game names (WR:144-177, 2627-2636; WO:399-406).
  The operands stay game data.
- **Navigation labels.** `ui/FullUIWorkspaces.lua:23` relabels the tabs as
  Plan, Explore and Records. This hides the literals at CR:3453/3459/3469 and
  LD:1246-1248.

## Pre-existing findings for Root routing (not repaired)

- **No-action risks:**
  - Selecting a Leaderboard row with an incomplete record queues
    `Sync.RequestLoadout` and shows no notice (LD:388-390).
  - Rendering a library detail with `hasLoadout=false` requests the loadout
    (CR:2640-2642). The worker assessed this as normally unreachable, but if
    it is reached it contradicts the no-selection text.
  - A unit-tooltip hover can be the first caller of one-time local DPS
    SavedVariables migrations (DpsCapture:3583-3584).
  - Library: pressing Enter in the link box saves the link, and admin removal
    has no confirmation.
  - Editor: the undo row, both selector rows and the locked-target Confirm
    change state without a confirmation.
- **Unknown shown as zero:**
  - Overlay: unread ownership shows as 0.
  - Leaderboard: unknown DPS becomes 0 (LD:146, DpsCapture:3348), and unknown
    and zero durations both show "—".
  - Library: `DpsText` (CR:561) turns a missing value into 0.
  - Editor: the Manage rows and the delete confirmation use `or 0`;
    "Locked (0/6)" and "Showing 0-0 of 0" appear for unknown data; an unknown
    quality is labelled "Common".
- **Long text cut off with no full-text alternative:**
  - overlay rows and the 90-row cap;
  - the unit-tooltip title, cut to 28 characters;
  - Leaderboard title, DPS, count and status cells;
  - library card lines and DPS cells;
  - the library Share-form status box (334×96), which receives refusals over
    400 characters.
- **Dead or stale text:**
  - shadowed tab labels;
  - labels replaced before display (WE:258, 269, 639);
  - the always-hidden tracking line (WR:2304-2418);
  - unreachable rows (WR:816, CR:1639);
  - "Saved Build 'None'" (WR:652);
  - a reference to the old "Load into Editor" button name (CC:3994);
  - "Both records records" in the Leaderboard;
  - the doubled "Details:" from the double `T.Message` pass.
- **Errors not shown:** Leaderboard and library list failures leave the old
  rows, or a blank list, with no error or stale marker.

## Known gaps

The inventory is measured but **not complete**:
- CandidateEvidence reasons reaching WC:1277 are not traced.
- FlexiblePlanChooser screens beyond the refusals the editor reaches are not
  inventoried.
- Raw Sync, transport and catalog `{reason}` values are sampled, not
  enumerated.
- Whether library `SetFilter` persists its setting is not traced.
- The native Low/High text of the slider template is unverified.
- Help pages and LoadingStatus phase strings belong to the Help and Loading
  status families.

## First-cohort proposal (for Root review; nothing adopted)

**Family `library`, bounded surface: the Build Library detail status panel.**
This is the explicit state shown in place of a build detail
(`ui/CommunityRenderer.lua:2447-2498`: `DETAIL_STATUS`, `ShowDetailStatus`).

Why this surface:
- All texts are static. They contain no user, game, wire or identity value,
  no markup and no `|` byte, and runtime code never compares, parses, stores
  or sends them.
- The texts are already selected by code. `CommunityProjection.Detail`
  returns `unavailable`, `invalid` or `incomplete` (CP:443-457), and the
  renderer adds `pending` and `none` (CR:2507-2531).
- The panel exercises four #144 states through the actual renderer.
- Existing English tests already pin it
  (`tests/prototype/community_cursor_readers.lua:148, 193-194, 224`).
- It has no #142, #47 or #132 dependency.

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

- **Size:** 9 new English keys, bringing the base to 37 of 64 with 27
  remaining. I checked all nine against the key shape, the 3-64 byte key and
  1-256 byte text limits, the ban on `|` and control bytes, and the exact
  source bytes, and confirmed they collide with no existing key.
- **Shared heading:** `library.heading.detail_unavailable` serves both
  `unavailable` and `invalid` because the meaning and the English are the
  same; the body carries the reason. Root may split it (decision D2), which
  makes 10 keys and 38 of 64.
- **Packs:** no pack entries are commissioned. Until a separately reviewed
  draft exists, the six packs resolve these keys to English as 54 counted
  `missing_candidate` fallbacks.
- **Last body text:** `library.body.no_selection` states a consequence, so it
  must stay complete in every language.

State coverage:
- **Covered:** empty (`none`), loading (`pending`, `incomplete`), unavailable
  (`unavailable` and the unknown-kind fallback) and invalid (`invalid`).
- **Explicitly excluded:**
  - ordinary: the shown detail needs #142 placeholders and shares the CP:378-417
    origins;
  - stale: the panel has no stale state, and list failures are silent;
  - refused and success: Share, Copy, Edit and Remove outcomes live on other
    surfaces that depend on #142 and #132.

Build Library stays `PENDING`. This cohort completes only the detail status
panel.

Proposed future work (not done here):
- **Consumer:** `DETAIL_STATUS` keeps the same kind codes but holds
  `{headingKey, bodyKey}`. The text is resolved with
  `Nexus.Localization.Text` when `ShowDetailStatus` runs, not at file load,
  with the current English as the fallback when the seam is absent (as
  `LocalizedReason` does). `status.kind`, the fallback to `unavailable`
  (CR:2491-2492) and the projection codes do not change.
- **Data:** 9 rows in `data/LocalizationEnglish.lua`, the matching
  `KEY_CONTEXT.json` key rows, and the library entry in `adoptedKeys`.
- **Tests:**
  - `community_cursor_readers.lua` stays unchanged and green;
  - a new focused test, registered in `tools/run_prototype_tests.py`, drives
    `none`, `pending`, `unavailable`, `invalid`, `incomplete` and an unknown
    kind through the real TOC-loaded renderer;
  - the catalog and validator rows belong to the #147 validator plan.

Acceptance predicate for Root review:

1. **P1:** exactly these 9 keys (or 10 under D2), each passing the key and
   text contract, with English byte-equal to CR:2451-2461 at the reviewed
   source, and a base of 64 entries or fewer.
2. **P2:** with English active, every status title and text is byte-identical
   to the current output for all five kinds and the unknown-kind fallback.
   The existing English tests pass unchanged.
3. **P3:** a non-English fixture pack reaches `ShowDetailStatus` through the
   real renderer for all five kinds. A missing entry falls back to English and
   is counted. No draft pack text is added.
4. **P4:** `status.kind`, the kind codes, the projection reason codes and the
   selection identity are unchanged.
5. **P5 (no action):** in every kind, selecting, refreshing, cancelling and
   changing language make no `Sync.RequestLoadout` call or other Sync send and
   write no SavedVariables beyond the existing selection state. They assign,
   save, share, delete and spend nothing. The CR:2640-2642 request is either
   shown unreachable for these kinds or reported.
6. **P6 (long text):** a 256-byte fixture body stays word-wrapped and
   `GetText()` returns the full text. Native fit is `NOT_RUN`.
7. **P7:** the family stays `PENDING` with these exclusions restated.
   Competent review stays `UNASSIGNED` and localized native stays `NOT_RUN`.
8. **P8:** full CI on the final source pin, then independent Spec and
   Standards review with fixes and re-review. Existing merge, native and
   release authority is unchanged.

Alternatives considered and not chosen (details in the JSON):
- **Editor Display Settings and On-Screen Wishlist popup:** covers only the
  ordinary state. Its hover sentence is split across WR:1695-1696, and joining
  it changes the English rendering (D9).
- **Overlay controls:** WO:197 contains the invariant command `/nexus overlay`,
  and every row needs #142.
- **Leaderboard chrome:** about 41 keys, which is over 36. It is
  ordinary-only, its labels are hidden by FullUIWorkspaces, and its tab names
  are reused inside templates.
- **Library Sync mode dialog:** its mode sentences are byte-coupled, and its
  dynamic half needs #142.
- **Library Edit Build popup:** its outcomes need #142.
- **Unit tooltip:** the caption is coupled to the duplicate check, and the
  rank line needs #142.

## Future controls and ownership (requirements only; not executed)

- **Identity:**
  - English byte identity for every adopted text (the existing English tests
    are listed in the JSON `couplingHighlights`);
  - codes, IDs, Echo names, authored text, player names, encoded build
    strings and wire values unchanged under a fixture pack;
  - search, filter and sort results unchanged.
- **No action:** open, select, hover, cancel and language change make no Sync
  send, no SavedVariables write beyond existing UI state, and no assignment,
  save, share, delete or spend. Hooks on `Nexus.Sync.RequestLoadout` and the
  Store writer prove it.
- **Long text:** 256-byte fixtures keep the existing wrap, scroll or full-text
  tooltip. A surface that cuts text with no alternative needs an access
  decision before adoption.
- **Unknown versus zero:** a count adopted later shows the unknown form,
  never 0.
- **Ownership:**
  - Root assigns each family's work. The library goes first (this proposal).
    The leaderboard and overlay follow #142, and the unit tooltip follows the
    caption-marker decision D3 and #142.
  - The #132 and #47 owners are consulted for their sites.
  - The FullUIWorkspaces labels need one owner (D10).
  - The Sync owners supply reason codes first (D5).

## Root decisions

- **D1:** accept, amend or reject the first cohort.
- **D2:** one shared or two separate "Build not available" headings.
- **D3:** the unit-tooltip caption marker. Either a code-owned marker that is
  independent of the caption, or one session-resolved caption used for both.
  Until then UT-NP-0045-a cannot be adopted.
- **D4:** cap allocation. The 36 remaining entries are shared by #143, #144
  and #145. This inventory alone holds 1,147 distinct English spans, 514 of
  them independent static texts, so **the 64-entry cap cannot hold #144**.
  Any cap change is separate reviewed engineering work.
- **D5:** who supplies reason codes for the byte-coupled Sync, CandidateEvidence,
  save-result and `T.Message` texts.
- **D6:** with #132, whether to render the persisted English mirror titles and
  descriptions at display time (CC:1287, 1373, 1379) or keep them as data.
- **D7:** shadowed and unreachable literals are excluded from adoption. Whether
  to remove them is outside localization.
- **D8:** route the no-action, unknown-versus-zero and long-text findings to
  their owners.
- **D9:** if the editor alternative is chosen, approve joining WR:1695-1696
  into one line.
- **D10:** the owner and key group for the shared navigation labels.

## Checks

Run (mechanical, schema and privacy):
- verified HEAD and tree, and confirmed the runtime blobs are identical;
- verified the English and pack counts;
- ran the lexical scan;
- checked record ID pattern, uniqueness and ID-to-line agreement, and the
  class and state vocabulary;
- byte-verified every record (spanCheck);
- confirmed that state and candidate references resolve;
- checked the proposed keys against the key and text contract;
- ran a privacy scan of record text (only "token", as in command or class
  token, matched);
- confirmed the JSON parses.

Not run:
- the 599 Lua / 84 Python suite (not commissioned for an inventory with no
  source change);
- native client testing;
- linguistic review;
- package and TOC checks.
