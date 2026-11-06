# String-literal inventory (L10N-01)

Refs #123. Source pin `18dc5b0313033dbc522bec1ab89c304078aa5645`. Notes below
on `T.Message`, English-text coupling and support wrappers were read later, at
source `66905e7a9be6ee31ead6bb60ef306e9fe5d9f4c9`. They are manual
classification leads and do not refresh the capture, its counts or its pin.

This is a lexical inventory of the Nexus-owned runtime Lua source. It locates
every string literal and records its exact value. It does not decide which
literal a player sees, which one should be translated, or which runtime text
exists only as fragments joined at run time. Those decisions are manual, and
this document only starts them.

## Evidence

Recorded on 2026-10-21 against the pin with `tools/l10n_inventory.py` (sha256
`588064b40e0e223073da4cc32abc5f33572755f0f00e948112b613f563ec04fa`). The
focused fixture tests (`tools/tests/test_l10n_inventory.py`, four tests
including six invalid-input subtests) passed on that tool revision.

| Result | Value |
|---|---|
| Exit status, stderr | 0, empty |
| Files scanned | 87 |
| `literal` records | 25,355 |
| `bytes` records | 4 |
| Input files changed | none (hashes compared before and after) |
| Lua executed | no |
| Validated as complete Lua programs | no (lexical scan only) |

An earlier capture with a previous tool revision stopped at the first `bytes`
value. It is superseded and is not used for any count here.

## Method

The scope is every Lua file that the two TOC files load and that Nexus owns:

- every `.lua` line of `Nexus.toc` (with `\` written as `/`) except
  `third_party/ChatThrottleLib.lua`: 86 files;
- `companion/NexusSupport/Storage.lua`, listed by
  `companion/NexusSupport/NexusSupport.toc`: 1 file.

Excluded:
- `third_party/ChatThrottleLib.lua`, which is third-party code (`THIRD_PARTY.md`);
- `tests/`, `tools/` and `docs/`, which are not loaded by the client.

From the repository root:

    python tools/l10n_inventory.py --root . <the 87 paths>

Output follows argument order, then source order within a file. The recorded
capture passed the paths in sorted order. Each stdout line is one record:

- `{"record": "literal", "path", "line", "column", "text"}`;
- `{"record": "bytes", "path", "line", "column", "hex"}`, for a value that is
  not valid UTF-8. Only decimal escapes can make one. It is listed, not
  converted to text.

The output is about 2.8 MB of generated evidence and is not checked in.

## Coverage by file family

| Family | Files | `literal` records |
|---|---|---|
| `core/` | 52 | 17,581 |
| `ui/` | 23 | 7,244 |
| `logic/` | 8 | 445 |
| `data/` | 3 | 37 |
| `companion/NexusSupport/` | 1 | 48 |
| **Total** | **87** | **25,355** |

Per-file `literal` records:

- **ui/**:
  - CommunityRenderer 1,178; WishlistRenderer 1,085; Panel 1,045; Leaderboard 665
  - JournalTab 638; OrbPanel 621; WishlistEditor 247; LogViewer 208
  - Readout 201; LoadingStatus 199; OrbHistory 164; Theme 129
  - QuickStart 117; OverwriteWarning 107; LayoutMetrics 105; Help 103
  - SupportReport 103; ServerStatus 98; CommunityBuilds 84; WishlistOverlay 71
  - Changelog 46; Nameplate 30; VirtualList 0
- **core/**:
  - BuildCatalog 1,844; SupportReport 1,411; GameAdapter 1,198; Sync 1,125
  - AutomationRuntime 1,010; CommunityController 910; OrbRuntime 841
  - DpsCapture 715; Store 665; WishlistController 604; MainDiagnostics 460
  - Main 394; LegacyDataMigration 355; ViewProjections 349; OrbAdapter 336
  - PeerDebug 289; MainLifecycle 286; Performance 285; CandidateEvidence 274
  - UserText 259; SyncReconciler 255; SyncSession 251; SyncInbound 244
  - SyncTransport 239; DataCompaction 227; RollRecorder 225; DataRetention 214
  - LoadoutEvidence 213; WishlistModel 192; LegacyQualificationRepair 184
  - Identity 176; StutterAlertIntegration 154; SyncWire 140; Updates 135
  - CommunityProjection 131; SyncProtocol 122; BuildHashCache 104
  - SyncCompatibility 99; Codec 97; SyncAdmission 86; MainCommands 83
  - DiagnosticLogs 74; MainViewModel 71; SupportIncidents 42; Errors 41
  - EchoCatalogSource 36; ViewRefresh 36; SyncDiagnostics 32; SyncModePolicy 24
  - DiagnosticHistory 17; Scheduler 17; Revisions 10
- **logic/**:
  - EchoWeaver 131; Model 106; Ratchet 60; OrbGuidance 56
  - Version 38; OrbPolicy 27; Strategy 19; Policy 8
- **data/**: Release 33; BundledBuilds 2; DefaultProfile 2
- **companion/NexusSupport/**: Storage 48

`bytes` records: 4. Two are the UTF-8 continuation-byte pattern
`"[\128-\191]"` at `ui/LayoutMetrics.lua:215` and `ui/LayoutMetrics.lua:365`.
The other two are the UTF-8 tail pattern `"[\192-\255][\128-\191]*$"` at
`ui/OrbPanel.lua:106` and `ui/OrbPanel.lua:1039`. All four match the retained
capture and unchanged source; exact byte values are in
[VALIDATION.md](VALIDATION.md#located-byte-patterns). They are patterns, not
translation targets or native font evidence.

A count measures literals, not visible text. Large counts in `core/` come
largely from data keys, codes, patterns and diagnostics.

## Window families

The descriptions come from each file's own header.

| Window family | Files | Shows |
|---|---|---|
| Main panel (HUD) | `ui/Panel.lua`, with `ui/Readout.lua` (string builders), `ui/LayoutMetrics.lua`, `ui/Theme.lua`, `ui/ServerStatus.lua` (mirrored server HUD values) | setup, progress, completed builds and live Echo rolls |
| First-launch setup | `ui/QuickStart.lua` | the entry paths |
| Help | `ui/Help.lua` | reopenable read-only guide pages |
| Auto overwrite consent | `ui/OverwriteWarning.lua` | explicit consent before Auto can replace a Saved Build |
| Orb window | `ui/OrbPanel.lua`, `ui/OrbHistory.lua` | run controls and the read-only run log page |
| Echo Journal tab | `ui/JournalTab.lua` | the "Nexus Progress" tab inside the game's Echo Journal |
| Wishlist editor | `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua` | the editor, display popup, menus and tooltips |
| On-screen Wishlist | `ui/WishlistOverlay.lua` | the always-visible Wishlist list |
| Build Library | `ui/CommunityBuilds.lua`, `ui/CommunityRenderer.lua` | the community browser, cards and detail |
| Leaderboard | `ui/Leaderboard.lua` | DPS records (Training Dummy, Lich King, both) |
| Unit tooltip | `ui/Nameplate.lua` | the Nexus badge and rank on another player's tooltip |
| Loading status | `ui/LoadingStatus.lua` | read-only startup status |
| Support report | `ui/SupportReport.lua` | reading an incident and preparing a report |
| Log viewer | `ui/LogViewer.lua` | the `/nexus log` copy-friendly text tabs |
| Release note | `ui/Changelog.lua` | the one-time release note |

`ui/VirtualList.lua` has no literal.

Copy is also built outside `ui/`. These sources were confirmed by reading:
- `core/UserText.lua`: player-facing terms, reason text, destinations, counts
  and record scope (header at `core/UserText.lua:1-2`);
- `core/Main.lua`: chat output (`core/Main.lua:23-24`);
- `core/SupportReport.lua`: incident, notice and reason lines that
  `ui/SupportReport.lua` shows, and the capacity lines that `CommandStatus` in
  `core/Main.lua` prints (see Diagnostics and support exports under
  [Exclusions](#exclusions)).

Other `core/` and `logic/` files hold literals of every kind, and which of
them reach a player is not classified here.

The TOC `## Title` and `## Notes` lines (`Nexus.toc:2-3`,
`companion/NexusSupport/NexusSupport.toc:2-3`) are visible in the client's
AddOns list. They are not Lua, so the inventory does not include them.

## Copy kinds with source examples

| Kind | Example | Note |
|---|---|---|
| Help | `ui/Help.lua:8`: `{id="start",title="Getting started",text=[[...` | `id` is invariant; `title` and the long-bracket `text` are visible |
| Setup | `ui/QuickStart.lua:184-241`: `"Welcome to Nexus"`, `"Set up current build"`, `"Open Leaderboard"` | button and title labels |
| Confirmation and consent | `ui/OverwriteWarning.lua:6-8`; `ui/Panel.lua:46-48` | the dialog key `NEXUS_UPDATE_RELEASES` is invariant; its `text` has a `%s` and a URL follows at `ui/Panel.lua:53` |
| Disabled reason and unavailable state | `core/UserText.lua:5-46` (values), `core/UserText.lua:88`, `ui/OrbPanel.lua:267-280` | reasons arrive as codes and are mapped to text; the Orb status line explains disabled controls |
| Tooltip | `ui/Panel.lua:370-387` | includes the count fragment `"  +" .. n .. " more"` at `ui/Panel.lua:381` |
| Full-text tooltip | `ui/LayoutMetrics.lua:270-331` | shows the runtime text of a shortened or overflowing label; its own literals are script and anchor names |
| Chat and status | `core/Main.lua:23-24`, `core/Main.lua:1266`, `ui/Help.lua:240-241` | the colour prefix `\|cff7fd5ffNexus:\|r` is markup around the text |
| Player-facing error | `ui/OrbPanel.lua:346`: `"Orb panel refresh failed. Controls are unavailable."` | |
| Developer error | `ui/OrbPanel.lua:221`: `assert(..., "Orb history projection unavailable")` | not player copy |
| Diagnostic placeholder | `core/Errors.lua:34`, `core/Errors.lua:43` (`"<unprintable "`, `"unknown"`) | retained diagnostics |
| Dynamic label | `core/UserText.lua:161-170` (Saved Build label with a user name), `core/UserText.lua:247-254` (count with unit), `core/UserText.lua:301` (`"%d:%02d fight"`), `core/UserText.lua:47-67` (availability-control names from catalog data), `ui/LayoutMetrics.lua:432` (`"Orb mini panel"` or `"Mini"` by width) | the inventory lists each fragment; the assembled sentence exists only at run time |
| Rewritten status and reason text | `T.Message` returns and `gsub` replacements, for example `"Disabling off-Wishlist "` (`core/UserText.lua:62`), `"Enabling Wishlist "` (`:64`), `"unsupported availability data"` (`:67`), the sentences that begin `"Not saved: "` (`:82-87`), `"This action is not available yet. Check the status or diagnostics. Details: "` (`:88`), `"WISHLIST:"` (`:91`), `"Rolled Echoes this run:"` (`:92`) and `" (server confirmed)"` (`:93`) | displayed; the inputs they match keep their English spelling ([Exclusions](#exclusions); item 4 of [Manual follow-up](#manual-follow-up-before-l10n-02)). A `gsub` replaces only part of a line, and the returns at `:70`, `:73`, `:76`, `:79` and `:88` end with the producer's own English text after `"Details: "`. Examples only; `T.Message` is not completely classified |

## Exclusions

These are decided by reading, not inferred by the tool. Unless a group is
marked as a proposal, each listed item keeps its exact spelling and is never a
translation key to rewrite. A listed example classifies only that literal or
use, not the rest of its file or line range.

**Codes, identifiers and patterns**
- Reason and policy codes: the keys of `core/UserText.lua:5-46` (for example
  `ROOT_MUTATION_PENDING`, `orb state unknown`). Diagnostics keep the original
  codes (`core/UserText.lua:1-2`).
- Matching operands: the Lua patterns and plain search strings that code
  compares with other text. In `T.Message` (`core/UserText.lua:54-104`) they
  include `"^(L%d+ %-%- )(.*)$"` (`:57`),
  `"^disabling off%-wishlist tome lever (%d+)$"` (`:61`), the `gsub` pattern
  `"non%-conformant data"` (`:67`), the plain search `"payload changed"`
  (`:78`), `"^[A-Z][A-Z0-9_]+$"` (`:88`) and the first argument of each `gsub`
  at `:89-102`, such as `"TARGET:"` (`:91`) and `" %(synced%)"` (`:93`). Each
  must keep matching the text its producer writes (manual follow-up item 4).
  The returns and `gsub` replacements of that function are displayed text,
  not exclusions (see the rewritten status row under
  [Copy kinds](#copy-kinds-with-source-examples)), and the other literals of
  `core/UserText.lua:57-102` are not all classified here.
- Other Lua patterns: `ui/LayoutMetrics.lua:209`, `:215` and `:365`, and
  `ui/OrbPanel.lua:106` and `:1039`. These include the four `bytes` records.
- Slash command words: `core/MainCommands.lua:10-20` and `:40-60`. Localized
  command aliases would need their own decision.
- Protocol tokens: the class tokens at `core/SyncProtocol.lua:476-481`, and
  `Release.version` as consumed by Sync protocol 7 (`data/Release.lua:17-18`).
- Frame, global and template names: `CreateFrame("Frame","NexusOrbPanel",...)`
  (`ui/OrbPanel.lua:359`), `_G["ProjectEbonholdEchoJournal"]`
  (`ui/JournalTab.lua:1452`), the font templates (`ui/WishlistEditor.lua:547-584`)
  and the `NexusFont*` objects (`ui/LayoutMetrics.lua:20-24`).
- Settings, enum and release values: `rollingPolicy` `"adaptive"` or
  `"released"` (`data/DefaultProfile.lua:47-49`); the release identity and URL
  (`data/Release.lua:6-15`); catalog versions (`data/BundledBuilds.lua:7-9`).
- Lookup keys whose values are text: the keys of `T.Terms` and `COUNT_UNITS`
  (`core/UserText.lua:327-337`, `:236-242`).

**English-name matching** (behavior, not presentation)
- `anchorNames = { "Adaptive Power" }` (`data/DefaultProfile.lua:71`) is
  matched against Wishlist Echo names.
- `RARITY_WORDS` (`logic/Model.lua:31-34`) strips an English rarity suffix
  from recorded names.
- `logic/Model.lua:26` folds U+2019 to `'`.

Translating these would change behavior. How they behave under a client that
reports non-English names is UNKNOWN; this is recorded for L10N-04.

**User-authored and player data**
- Wishlist names and descriptions, Saved Build names, character and owner
  names and shared listings arrive at run time.
- They pass through `T.SafeName` (`core/UserText.lua:147-159`) into templates
  (`core/UserText.lua:161-230`).
- They are never keys and are never translated or transliterated.

**Game data**
- Echo and spell names and IDs, qualities, roles and availability-control
  names come from the game catalog at run time (`core/UserText.lua:47-53`).
- Localized game names need verified client data (L10N-04).

**Diagnostics and support exports** (proposal; each surface needs a decision)
- Payload bytes: the copied summary and the prepared report file that
  `core/SupportReport.lua` builds (`M.Summary`, `M.Prepare`), and diagnostic
  text in `core/PeerDebug.lua`, `core/DiagnosticLogs.lua` and
  `core/Errors.lua`, have their own byte and decoder contracts
  (`docs/agents/domain.md`, issue #25). The summary is shown in the support
  page's copy box, but it is that payload.
- Visible wrappers from `core/SupportReport.lua`: `ui/SupportReport.lua` shows
  `M.IncidentLines` on its page; `M.WrittenNotice` and `M.FilePathHint` (a file
  path) after a report is prepared; reasons returned by `M.Store`,
  `M.StorageStatus` and `M.Prepare`, for example
  `"the support component refused the report"`, inside its own
  `"Not prepared: "` and `"Support storage: "` lines; and the report's
  `omissions` after `"This report is partial: "`. `CommandStatus` in
  `core/Main.lua` prints `M.CatalogCapacityLines` through `Print`.
- Some of these lines are payload as well: `M.IncidentLines` also writes the
  incident into the summary and the report, `M.StartupLines` includes
  `M.CatalogCapacityLines` in both, and `omissions` is part of the stored
  report's header. Translating their visible use would also change the
  payload unless the two uses are separated first.
- Proposal: keep the payload bytes out of the first translation scope, and
  decide each visible wrapper's surface before translating it. The labels of
  `ui/SupportReport.lua` stay in scope. Visible text of `core/PeerDebug.lua`,
  `core/DiagnosticLogs.lua` and `core/Errors.lua` is not classified here; this
  proposal does not show that their text is never displayed.

**Never translated**: URLs, numbers and colour codes.

## Scanner limits

False positives: a listed literal that is not player text. Every record is
unclassified, so the total includes:
- table keys written as strings and codes;
- event, API, frame and template names;
- Lua patterns and format fragments;
- settings and SavedVariables field names and protocol tokens;
- developer `assert` or `error` messages and diagnostic text.

False negatives: player text that has no literal of its own.
- Sentences assembled at run time by concatenation or `string.format`. Only
  the fragments are listed.
- Text from game APIs, the catalog or the server, and user-authored text.
- Client global strings referenced by name.
- TOC `## Title` and `## Notes`.
- Anything in `third_party/`, `tests/` or `tools/`.

Lexical bounds:
- Lua 5.1 rules for short strings, escapes, long brackets, comments and line
  breaks.
- Long-string line breaks are reported as `\n`. Columns are characters at the
  opening delimiter.
- The `[[` nesting check that is a Lua 5.1 build option is not applied.
- LuaJIT and Lua 5.2 escapes (`\x`, `\z`, `\u{}`) are treated the Lua 5.1 way.
- The source is not parsed as a program.

Not established: which literals are visible, which are translatable, and
whether every runtime text is statically represented.

## Manual follow-up before L10N-02

1. Classify the `ui/` window families, `core/UserText.lua` and the visible
   support wrappers of `core/SupportReport.lua` into visible, invariant and
   diagnostic literals, and record the context for each visible one
   ([KEYS_AND_GLOSSARY.md](KEYS_AND_GLOSSARY.md)).
2. List runtime-assembled sentences (fragments such as
   `ui/Panel.lua:381`, the templates in `core/UserText.lua`) for full-sentence
   templates in L10N-04.
3. Decide how the English-name matching above works under a localized client.
4. English-text coupling: some English text that Nexus produces is matched
   again by other Nexus code. Translating such a producer alone can stop a
   match and silently change what a player sees. Localize a coupled producer
   only together with every consumer that matches it; until then the matching
   inputs keep their exact English spelling. This inventory requests no
   runtime change. Representative examples, not a complete list:
   - `T.Message` (`core/UserText.lua:54-104`) maps exact reasons (`:5-46`),
     parses prefixes and tome-lever messages (`:57-67`), wraps or replaces
     messages that contain known fragments or look like codes (`:68-88`) and
     rewrites parts of the rest (`:89-102`). `Print` (`core/Main.lua:23-24`),
     the `onStatus` callback that `EnsureAutomationRuntime` passes in
     `core/Main.lua`, `Readout.Status` and the non-`plain` `AddLine` calls in
     `ui/JournalTab.lua` pass their text through it. It matches the whole
     message, so interpolated text such as a Wishlist name can match as well.
   - `CommandStatus` (`core/Main.lua`) prints `"TARGET: ..."` lines and
     `"OWNED this run: %d echoes (%s)."` with `"synced"` or
     `"not synced yet"`. They are shown as `"WISHLIST: ..."` and as
     `"Rolled Echoes this run: ..."` with `(server confirmed)` or
     `(waiting for current Echo data from the server)`. The `undemote`
     callback in `EnsureMainCommands` prints
     `"flag demotions cleared (they re-arm on fresh evidence)"`, which is
     shown as its `reasons` value (`core/UserText.lua:45`).
   - `ui/JournalTab.lua` reads its provider's sections (written by
     JournalData, per its comments) only in their exact English form:
     `Section` finds the titles `"Target"`, `"Notes"` and
     `"Extra copies compared with the plan"`; `Summarize` reads the
     `"Pending"` title prefix, `"^Pending %((%d+)%)$"`, the
     `"No wishlist set"` prefix, `TARGET_COUNTS`, `"^Wishlist '(.*)'(.*)$"`
     and `TARGET_TAGS`; `EstimateLine` needs `NOTES_FIRST` and the
     `NO_ESTIMATE` texts; `SplitOffLine` removes `OFF_SUFFIXES`; and
     `TOME_REQUESTS` identifies the request section. A provider line in
     another form can leave family progress unknown or the summary
     unavailable, drop the estimate, or show a whole off-Wishlist line as its
     row label.
   - `ui/Readout.lua`: `HOLD_TEXT` (`AutoHoldText`) and `HELP_HINT`
     (`AutoHelpHint`) are keyed by exact English reasons, for example
     `"manual mode"` in `HOLD_TEXT` (also returned by `AutoAllowed` in
     `core/Main.lua`) and `"user acting"` in both. `AutoHelpHint` gives no
     hint for a reason containing `"no confirmed result for"` and its Orb hint
     for one containing `"Orb"` or `"orb"`. `CardTarget` parses `CardLine`
     output: it removes the `"[Guaranteed offer] "` prefix and looks for a
     `QUALITY_NAMES` word (`"Common"` to `"Legendary"`) in parentheses. A
     guaranteed-offer prefix written another way stays inside the target that
     `RecommendationWithTarget` appends; a quality written another way drops
     that target.
5. Keep the four located byte patterns invariant (see
   [VALIDATION.md](VALIDATION.md#located-byte-patterns)).
6. Decide whether the TOC `## Title` and `## Notes` text is in scope.
