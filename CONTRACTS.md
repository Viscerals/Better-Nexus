# Nexus — internal module contracts (v1.20.0-beta.5)

Binding interface spec for all modules. Authored from `WISHLIST_REALIZER_BUILD_PROMPT.md`
+ `WISHLIST_REALIZER_SPEC_ADDENDUM.md` + `WISHLIST_REALIZER_DESIGN.md` (the addendum wins
conflicts). Every `logic/*` and `data/*` file: plain Lua 5.1, NO WoW API, NO
SavedVariables, NO `ProjectEbonhold.*` — loadable under bare LuaJIT. All cross-module
data is plain tables produced by `core/GameAdapter.lua` (the only IO module).

Global namespace: `Nexus` (each file: `Nexus = Nexus or {};
local M = {}; Nexus.<Name> = M`). Version: `Nexus.VERSION = "1.20.0-beta.5"`
comes from `data/Release.lua`; .toc `## Version: 1.20.0-beta.5` stays in lockstep.

Lua 5.1 rules: no `goto`, no `#` on non-sequences, `unpack` global, sort pairs for
deterministic output, forward-declare every closure-captured local BEFORE the closure,
`math.floor(x + 0.5)` before `%d` formats.

## Shared data shapes (produced by GameAdapter; logic treats all as read-only)

```lua
catalog = {
  rows = { [spellId] = { spellId=n, name=s, maxStack=n, classMask=n, minLevel=n,
                         quality=n, groupId=n, requiredSpell=n } }, -- validated echo rows only
  familyOf   = { [spellId] = familyKey },  -- "g<groupId>" when >1 row shares groupId, else "s<spellId>"
  familyMembers = { [familyKey] = { spellId, ... } },       -- sorted ascending
  familyName = { [familyKey] = s },                          -- display
  levers = { [requiredSpell] = { lever=requiredSpell, conformant=bool,
                                 members={spellId,...}, tomeName=s|nil } },
  playerMask = n,   -- corrected class mask (PerkClassMasks.DRUID is a client bug; adapter derives)
}

wishlist = nil | {           -- nil => advisor-only mode
  name = s,
  entries  = { { spellId=n, quality=n, stacks=n, family=s } , ... },  -- stacks >= 1
  byFamily = { [familyKey] = { targetStacks=n, wishedQuality=n, spellId=n } },
}

owned = {                    -- granted ∪ locked ∪ adapter-recorded picks
  bySpell  = { [spellId] = count },
  byFamily = { [familyKey] = count },
  synced = bool,             -- false => engine must not auto-act at level > 1
}

board = nil | {              -- nil => no board (wait)
  cards = { { spellId=n, quality=n, family=s, isFrozen=b, isCarried=b,
              isGuaranteed=b, justFrozen=b } , ... },  -- 1..3 entries
  guaranteedIndex = n|nil,   -- found by scanning isGuaranteed; nil is VALID (4-card trim)
  signature = s,
}

charges = { banish=n, freeze=n, reroll=n, trustworthy=bool }  -- min(client, ledger), >=0

slots = nil | {              -- nil => SS 540 not arrived
  bySlot = { [slot] = { slot=n, name=s, verified=b, verifiedFieldPresent=b,
                        suspectParse=b,   -- echoes empty though entriesStr wasn't
                        echoes = { { spellId=n, stacks=n, locked=b, family=s }, ... } } }, -- SPARSE; pairs() only
  activeSlot = n,            -- 0 = none
}

flags = { DISABLE_SUPPRESSES_GUARANTEE = true|false,  -- true (user-confirmed) unless runtime-demoted
          REROLL_HOLDS_GUARANTEED = true|false|nil }  -- nil = conservative

plan = Strategy.Compile output (below).
queue = Ratchet.PredictQueue output (below).
```

## logic/Model.lua — `Nexus.Model`

Fork from EchoOptimizer/logic/Model.lua VERBATIM: `NormName`, `StripRaritySuffix`,
`CanonicalKey`, `BuildDistribution(entries,nBins,floor)`, `EmaxK(dist,k)`,
`EmaxGivenK(dist,c,k)`, `WithoutKey(dist,key)`. New functions:

- `Model.Support(catalog, owned, level, disabledLevers, plan)` → array of
  `{ spellId, family, quality, value }` — free-slot draw support: row passes iff
  `bit-and(classMask, playerMask) ~= 0` (implement via arithmetic, no bit lib in logic:
  `Model.MaskMatch(mask, playerMask)` using modular arithmetic), `minLevel <= level`,
  its lever (if any, `requiredSpell~=0` and lever exists) is not in `disabledLevers`
  (set keyed by lever id), and not exhausted (`owned.bySpell[spellId] or 0) < maxStack`
  — plus for maxStack==1 rows any owned FAMILY member exhausts the whole family's other
  qualities for coverage purposes but NOT pool presence (pool removal is per-spellId).
  `value` = `Model.Delta(...)` for that spellId.
- `Model.Delta(plan, owned, spellId, catalog, params)` → number. Ordinal scale
  (`params` from data/DefaultProfile): uncovered wished family → `params.coverage`
  (+ `params.qualityBonus * quality`); wished stackable below targetStacks →
  `params.coverage * (remaining/target)` decreasing; anchor spellId itself uncovered →
  `params.anchorUnlock`; unique new family while anchor owned → `+params.diversity`;
  duplicate of an owned maxStack==1 family → `params.duplicate` (≈0/negative);
  off-wishlist non-duplicate → `params.filler` (negative). Pure function, no state.
- `Model.FreeDist(support)` → `BuildDistribution` over support with UNIFORM probs
  (θ unmeasured); nil-safe on empty support (return nil → callers treat E as 0).

## logic/Strategy.lua — `Nexus.Strategy`

- `Strategy.Compile(catalog, wishlist, settings)` → plan:
  ```lua
  plan = {
    targets = wishlist and wishlist.byFamily or {},
    wishedFamilies = { [familyKey]=true },
    anchorSpellId = settings.anchorSpellId (nil unless the row exists in catalog & on wishlist),
    leverPlan = {
      disable = { leverId, ... },  -- conformant AND every member's family off-wishlist
      keep    = { leverId, ... },  -- has a wishlist-family member
      skippedNonConformant = { leverId, ... },  -- NEVER toggled (e.g. requiredSpell=9)
    },
    advisorOnly = (wishlist == nil),
  }
  ```
  Lever conformance comes from `catalog.levers[l].conformant` (adapter computes via the
  name-exact "Tome of <member name>" rule); Strategy only partitions. Deterministic
  ordering (sort lever ids ascending).

## logic/Ratchet.lua — `Nexus.Ratchet`

- `Ratchet.PredictQueue(activeEchoes, owned, plan, flags, disabledLevers, catalog)` →
  `{ entries = { { spellId, family, wanted=bool }, ... } }` in given order, skipping
  entries whose FAMILY is owned (family-aware subtraction, addendum §B2), and — iff
  `flags.DISABLE_SUPPRESSES_GUARANTEE` — skipping members of disabled levers.
  Prediction is planning/UI-only; never coverage.
- `Ratchet.Dominates(candidateOwned, incumbentEchoes, plan, catalog)` → `ok, detail` —
  candidate's wished-family coverage ⊇ incumbent's AND candidate's off-wishlist family
  set ⊆ incumbent's AND ≥1 strict improvement. `incumbentEchoes` = slot echoes array.
- `Ratchet.ScoreSlot(slotEchoes, plan, catalog)` → number (wished families covered −
  `0.25 ×` off-wishlist families) and `Ratchet.BestSlot(slots, plan, catalog)` →
  `slot|nil` over genuinely-verified rows only (`verified and verifiedFieldPresent and
  not suspectParse`), sparse-safe (pairs).
- `Ratchet.RunsEstimate(plan, owned, queue, support)` → `{ text = s, unknown = bool }` —
  with θ unmeasured return `unknown=true` and text like "~N wishlist echoes pending
  (rate unmeasured)"; never fabricate a number labeled as fact.

## logic/Policy.lua — `Nexus.Policy`

- `Policy.Decide(state)` where `state = { board, owned, charges, plan, queue, flags,
  level, horizon, support, params }` → action:
  `{ type = "take"|"reroll"|"banish"|"wait", spellId=?, index=?, reason = s }`
  plus `annotations = { [cardIndex] = "wanted"|"guaranteed"|"duplicate"|"filler"|"junk" }`.
  Rules (§5.5 greedy + addendum):
  1. Compute `Model.Delta` for each card. Guaranteed card = `board.guaranteedIndex`
     (may be nil — then branch 2 skipped).
  2. Tight-regime check: `wantedInQueue >= horizon` → take guaranteed when present &
     wanted; never divert.
  3. Take best free card if its Δ > guaranteed's Δ and Δ > 0.
  4. Else take guaranteed when present.
  5. Else (junk board): banish proposal — only when `charges.banish > 0`, target the
     worst NON-guaranteed/frozen/carried/justFrozen card whose removal raises
     `EmaxK(FreeDist without it, 1)`-style expectation, `type="banish"` (Main fires at
     most one per fresh run-data push; Policy needn't know) — else reroll proposal when
     `charges.reroll > 0` AND (no guaranteed present, or guaranteed Δ low
     (< params.rerollHoldThreshold), or `flags.REROLL_HOLDS_GUARANTEED == true`) AND
     `EmaxGivenK(dist, bestCurrentΔ, 2) - params.rerollCost > bestCurrentΔ` — else take
     the least-harmful card (max Δ, break ties toward non-filler, lowest quality).
  6. Freeze is scoped to ONE case (step 2b): a scarce wished family
     (guarantee already exhausted, still short of stack target) sharing a
     board with no other card worth taking outright, and only with a
     banish/reroll charge in hand to spend on the rest of the board.
     Everything else in the decision tree still NEVER returns type
     "freeze". NEVER banish/reroll-target index of a guaranteed/frozen/
     carried/justFrozen card.
  7. `board == nil` or `owned.synced == false` (with level>1) → `{type="wait", reason}`.
  Pure function; same input → same output.

## data/DefaultProfile.lua — `Nexus.DefaultProfile`

Pure table: `params` (coverage=100, qualityBonus=2, anchorUnlock=150, diversity=5,
duplicate=-5, filler=-15, rerollCost=8, rerollHoldThreshold=25), `defaultSettings`
(autoPick=true, autoActivate=true, autoDisable=true, autoSave=true, autoBanish=true,
anchorSpellId=nil, leverOptOut={}), `defaultFlags` (DISABLE_SUPPRESSES_GUARANTEE=true
-- user-confirmed 2026-07-23, runtime-demotable; REROLL_HOLDS_GUARANTEED=nil).

## core/Store.lua — `Nexus.Store` (SavedVariables: `NexusDB`)

`Store.Init()` (ordered additive migrations, recursive missing-default fill, then
idempotent BuildCatalog migration), `Store.Settings()`,
`Store.State()` (per-char keyed subtable: tomeTogglePending per lever w/ timestamps,
priorAutoAccept, flagDemotions, recordedPicks for the current session). Char key from
`UnitName("player")` guarded — if unavailable, defer (never latch "Unknown").

## core/Errors.lua — `Nexus.Errors`

`Errors.Init()`, `Record(source, value)`, `History()`, `Latest()`, `Clear()`,
`Format()`, and `Limit()`. The module sanitizes SavedVariables, retains the newest
20 timestamped `{source,message}` entries oldest-to-newest, returns defensive
copies, and keeps `Nexus.lastError` as a latest-value compatibility surface.
Stringification, persistence, render, and clear paths are recursion-guarded and
must never authorize gameplay actions. The Errors log tab clears only this
history; a full diagnostic clear may clear it alongside other diagnostic logs.

## core/Revisions.lua — `Nexus.Revisions`

In-session counters start at zero for `BUILD_LIBRARY_CHANGED`, `DPS_CHANGED`,
`SYNC_CHANGED`, and `CATALOG_CHANGED`. `Get(event)`, `Snapshot()`,
`Subscribe(event, callback)`, `Advance(event, detail)`, and `Events()` expose the
bus. Mutations advance only after represented data commits; duplicate/rejected
traffic, reads, last-seen/timer updates, visibility, and logs do not. Subscribers
run synchronously in registration order, and callback failures are isolated and
recorded without rolling back or interrupting the originating mutation. Build
details use `{scope="record",id=...}` for one represented build/tombstone and
`{scope="all"}` for catalog-wide changes. DPS details use
`{scope="record",category=...,player=...}` only when the wire-winning row changes;
local/metadata-only changes remain explicit non-hash invalidations.

## core/LoadoutEvidence.lua — canonical exact-loadout data

`Nexus.LoadoutEvidence.Init(db)`, `Normalize(echoes)`, `Fingerprint(echoes)`,
`Intern(echoes, claimedReference)`, `Resolve(reference, inline)`,
`Reference(record)`, `ReferenceDpsRow(row)`, `ResolveDpsRow(row)`,
`ResolveBuildRow(row)`, `Snapshot()`, `Stats()`, `Conflicts()`,
`RegisterReferenceProvider(name, callback)`, and `CollectGarbage(db)` own the
content-addressed `NexusDB.loadoutEvidence.entries` pool. Identity is the full
canonical spell/quality/stack/locked tuple string, never a short hash or caller
claim. Equal canonical arrays share one stored entry; a mismatched claim or
corrupt stored key is retained as a bounded in-session conflict and never
overwrites another exact array. Public resolution always returns a defensive
copy.

Additive references are introduced before the verified compaction migration;
only byte-for-byte canonical overlay/DPS arrays remove their inline duplicate;
all others remain inline. Pool-only reads and outgoing build/DPS payloads
materialize the same offline evidence; bundled baseline rows are neither interned
nor mutated. GC performs a complete durable-reference scan plus registered
runtime providers before deleting anything, and any provider failure blocks the
delete pass. The module owns no revisions, transport, scheduler, GameAdapter
access, or automation authority. A future evidence schema is readable but not
writable; even an opaque future `entries` shape is preserved without repair.

## core/DataCompaction.lua — conservative evidence migration and retention

`Nexus.DataCompaction.Init(db)`, `Enabled(db)`, `CompactBuildRow(row)`,
`CompactDpsRow(row)`, `CollectGarbage(db, dryRun)`, `Stats(db)`, and `Version()`
own the ordered version-1 compaction. Store runs it only after LoadoutEvidence
and BuildCatalog bind the current SavedVariables table. The migration interns,
resolves, and deeply compares each candidate before removing an inline array;
malformed, noncanonical, full-reference-conflicting, or semantic-fingerprint-
conflicting rows remain intact inline and are counted. A completed version stamp
makes repeated Store initialization byte-for-byte stable, while later canonical
BuildCatalog/DPS writes compact through the same verifier.

BuildCatalog materializes a pool-only overlay before durable comparison with a
new bundled baseline, so a later catalog version can still prune an exact
redundant overlay without changing the public build shape.

There is no build-count limit and no personal, peer, DPS, automatic-page,
filter, or tombstone eviction. Only unreachable pool entries are collectable
after the full reference scan. Sync registers its retained hot-build window as a
runtime reference owner. Compaction may advance the existing build/DPS revision
events with `{scope="all"}`; it has no scheduler, GameAdapter, or automation
authority.

## core/BuildHashCache.lua — revision-cached Sync compatibility hashes

`Nexus.BuildHashCache.Delta()`, `Legacy()`, and `Stats()` retain the established
eight-bucket hash strings. First read builds both maps from BuildCatalog's
lightweight identity summaries without materializing Echo arrays; unchanged
reads reuse them without another catalog walk or sort. A record-scoped build
revision refreshes only that ID and dirties its one deterministic delta/legacy
bucket. Unknown, catalog-wide, missed, or failed invalidation state discards the
whole cache and rebuilds only on the next read. Failed warm-up never publishes
initialized state. The module owns no transport queue or gameplay authority.

## core/ViewProjections.lua — defensive revision/filter view caches

`Nexus.ViewProjections.Builds(filters)` and `Leaderboard(category, filters)`
read only public BuildCatalog/DpsCapture defensive shapes. Build projections use
display/identity summaries without Echo arrays; Community Builds hydrates exact
records only for the bounded visible-card window. One last-good
projection per view is keyed by represented build/DPS revisions plus normalized
scope, class, search, sort, category, and current-owner identity. Unchanged reads
perform no catalog/DPS walk or ordering pass, and every caller receives a
defensive copy. Status, timers, visibility, Sync queues, and diagnostic activity
are not cache inputs.

Construction is publish-after-success. If a represented revision changes while
a projection is building, the module retries once against the new snapshot; an
error or second unstable pass publishes nothing. The module owns no frames,
SavedVariables, revisions, transport, GameAdapter access, scheduler work, or
automation authority.

## ui/VirtualList.lua — fixed-height visible windows

`Nexus.VirtualList.Window(count, rowHeight, viewportHeight, offset, overscan)`
is pure Lua 5.1 math. It clamps invalid/tiny/end offsets and returns the exact
visible-plus-overscan index range, content height, and maximum scroll offset.
It owns no frames or state.

Community Builds retains one current defensive projection and binds only this
window into its existing reusable cards. Scrolling rebinds that window without
requesting another projection or refreshing detail/status controls; viewport
size changes use the same bounded rebind path. A failed bind reclaims every
checked-out card before surfacing the error, so a corrected data revision can
reuse the pool. Selection remains keyed by the exact build ID even when its card
is offscreen. Read-only virtual counters report created/active/peak cards and
data/scroll/resize bind passes; virtualization never mutates SavedVariables,
transport, revisions, or gameplay.

Leaderboard uses the same fixed-height window over one current defensive
projection. `RefreshData()` is the only path that requests a projection,
rebinds rows, reconciles stable-key selection, renders detail, and updates
category/filter controls. `RefreshStatus()` reads only Sync status and updates
the status label; its periodic ticker performs no DPS/catalog read, projection,
row/detail bind, or theme-tree traversal. Scroll and resize rebind only the
visible-plus-overscan rows, while offscreen selection retains the exact record
used by Copy into Editor and Open Build. Read-only counters expose these paths.

## core/Main.lua and ui/Panel.lua — materialized HUD display snapshots

Main is the sole owner of HUD-facing update, server-summary, character/target
DPS, player-level, progress, card, recommendation, and auto-state reads. It
passes Panel a defensive materialized snapshot and retains a separate defensive
base input for noncritical display refreshes. Rebuilding this snapshot may read
display services but never enters Policy, Ratchet, GameAdapter transport, or
automation actions.

Panel rendering performs no direct data-service reads. It retains its own copy
and compares length-prefixed stable layout, performance, update-notice, status,
and auto signatures. Unchanged snapshots do no widget/layout work; status, notice,
performance, and auto-only changes update only their bounded controls. Full
adaptive layout remains reserved for represented layout changes.

`Nexus.Theme.StyleTree(root)` marks a completed static subtree, and repeated
calls stop at that root. `StyleVirtualRow(row, controls)` applies the shared
border and styles its bounded child-button list once. Community and Leaderboard
call it only when a new pooled row is created. Theme/HUD counters are read-only diagnostics and
never affect visibility, selection, SavedVariables, transport, or gameplay.

## core/Scheduler.lua and core/ViewRefresh.lua — noncritical timing only

`Nexus.Scheduler.After(key, delay, callback)`, `Every(key, interval, callback)`,
and `Cancel(key)` own keyed debounce, background retry, maintenance, and
coalescing. Reusing a key replaces its task. Due callbacks run in deterministic
due-time/key order, repeaters skip missed intervals, and each frame executes at
most 32 callbacks. Callback failures are isolated and retained by `Nexus.Errors`.
`Nexus.ViewRefresh` uses the scheduler only for Community Builds, Leaderboard,
and repainting the panel from its last cached model. Status-only panel updates
remain immediate through `Panel.SetStatus()` and never rebuild strategy data.

The scheduler is never an automation authority. Main calls `GameAdapter.Poll()`
on its direct 0.2-second safety heartbeat. The expensive plan/owned/slots/panel
step runs only after consumed adapter dirtiness, a known action deadline, an
explicit refresh, or the five-second self-healing fallback. Combat/run latches,
in-flight action resolution, action deadlines, and all gameplay mutations remain
outside scheduler callbacks. Adding one of those paths to a scheduler callback
is a contract violation even if the callback uses a unique key.

## core/GameAdapter.lua — `Nexus.GameAdapter` (sole IO; my file)

Exposes to Main: `Init(callbacks)`, `Catalog()`, `Board()`, `Charges()`, `Owned()`,
`Wishlist()`, `Slots()`, `DisabledLevers()`, `DiscoverySynced()`, `Level()`, `Horizon()`,
`InFlight()`, `Take(spellId)`, `Banish(index)`, `Reroll()`,
`ToggleLever(leverId, wantDisabled)`, `Activate(slot)`, `Save(slot, name)`,
`SetSoloPicker()`, `RestoreAutoAccept()`, `RivalDetected()`, `RequestSlots()`,
`RequestGranted()`, `Poll()`, and `ConsumeDirty()`. `Poll()` retains direct safety
latch/retry checks and cheaply detects unhooked auto-accept/rival transitions;
`ConsumeDirty()` atomically returns and clears accumulated board, owned, slots,
level, catalog, and settings invalidations. All per design doc §4 (deep copies,
ledger, gate v2 latch-polling, run-boundary, self-check demotion hook).

## ui/*

- `ui/Readout.lua` — `Nexus.Readout`: pure-ish formatting: `Readout.Status(model)`,
  `Readout.CardLine(card, annotation, delta)`, `Readout.QueueLines(queue, n)`. No IO.
- `ui/Panel.lua` — `Nexus.Panel`: movable frame `NexusPanel`:
  status line, up to 3 card lines + recommendation, AUTO ON/OFF button (calls
  `callbacks.ToggleAuto()`), version string. `Panel.Init(callbacks)`, `Panel.Render(model)`,
  `Panel.SetStatus(status)`, `Panel.Refresh()`.
  model = { status, cards={ {text, highlight} }, recommendation, auto, version }.
- `ui/JournalTab.lua` — `Nexus.JournalTab`: lazy install by hooking
  `ProjectEbonhold.EchoJournal.Show/Toggle` via hooksecurefunc (journal frames DO NOT
  exist at login), `PanelTemplates`-based 4th tab "Optimizer", soft-fail contract
  (pcall everything; failure = no tab, no error). Content (text lines are fine for v1):
  wishlist decomposition counts + names (owned/pending/filler), lever list with
  per-lever state, runs estimate, terminology note ("targets the ACTIVE loadout —
  set via 'Play with' in Loadouts"), VERSION. `JournalTab.TryInstall(dataProvider)`,
  re-asserted on journal Show. UI files may read `ProjectEbonholdEchoJournal` frames
  (presentation-layer exception, documented) but NEVER PerkService — all data through
  the provider callback.

## data/BundledBuilds.lua — `Nexus.BundledBuilds`

Immutable release data with `schemaVersion`, `catalogVersion`, `sourceVersion`,
`generatedAt`, deterministic `generation` counts, and `builds`. The tracked
`tools/export-bundled-builds.js` parser reads only the literal
`NexusDB.communityBuilds` table, validates complete canonical loadouts, and emits
an explicit shareable-field allowlist. Account settings, DPS stores, filters,
personal Saved Build mirrors, tombstoned/incomplete rows, and transient UI/cache
fields are never emitted. Runtime modules must not read or mutate `builds`
directly; all merged access goes through `Nexus.BuildCatalog`.

## data/Release.lua, logic/Version.lua, core/Updates.lua

`Nexus.Release` separates the local development identity from the last stable
base and exposes only the stable releases-page URL. `Nexus.Version.Parse` accepts
an optional `v`, one to three numeric components (missing components normalize to
zero), and valid SemVer prerelease/build identifiers; `Compare` ignores build
metadata. Only versions with neither prerelease nor build metadata are eligible
published candidates. `Nexus.Updates` observes versions only after Sync accepts a
recognized message, persists the highest candidate newer than `baseVersion`, and
emits at most one enabled chat notice per session. Opt-out hides chat/UI without
erasing the candidate. No module performs an update network request or install.

## core/BuildCatalog.lua — `Nexus.BuildCatalog`

`BuildCatalog.Init(db, bundled)`, `Get(id)`, `All()`, `Summaries()`,
`DeltaSummaries()`, `IsAuthor(name)`, `ForEach(visitor)`, `Count()`,
`Put(build)`, `RemoveOverlay(id)`, `RemoveOverlayBatch(ids)`,
`SetTombstone(id, tombstone)`, `ClearTombstone(id)`,
`RemoveTombstonesBatch(ids)`, `HasBaseline(id)`, `OverlaySnapshot()`, `DeltaSnapshot()`, and
`TombstoneSnapshot()`. Returned records/tables are defensive copies; summary
surfaces deliberately omit Echo arrays. Rebinding the same database and immutable
bundle is an idempotent allocation-bounded fast path. Read precedence is
authorized tombstone, then a personal or at-least-as-new overlay row, then the
bundled row. `DeltaSnapshot()` contains only overlay rows that win that selection;
stale hidden rows and bundled-only rows are excluded. During the staged consumer
cutover, `NexusDB.communityBuilds` is the canonical overlay backing table.
Overlay writes establish `evidenceKey`; after compaction is enabled, only an
exact deep round trip removes the inline duplicate. Merged and snapshot reads
hydrate a missing inline array from `LoadoutEvidence` without mutating
SavedVariables. A newer `buildCatalog.schemaVersion` binds the catalog read-only:
metadata, overlay rows, and tombstones are preserved without migration, and all
catalog mutation APIs reject writes until a supported database is rebound.

## core/DataRetention.lua — bounded durable mesh state

`DataRetention.Init(db)` performs an idempotent startup pass and `Request(reason)`
coalesces later noncritical passes through `Scheduler`. It never automatically
removes `isMine`, `importedSavedBuild`, or a build owned by any account character
seen by Nexus. Dummy and Lich King each retain the top 100 overall plus the top
15 per represented class. The derived Average board retains its top 50 overall
plus top 10 per class by protecting both contributing raw rows. These clamped
limits are saved/configurable and account-owned rows never consume them.
Unrelated community posts have a separate 75-row recency budget and 12-per-author
limit. Superseded unreferenced `autoDps` rows are removed locally without
broadcasting a delete for another author. Personal/build-best fingerprint maps
remain bounded while fingerprints selected by a retained rank are protected.

Local eviction markers prevent the same stale rows from churning back through
Sync. Markers themselves compact to a monotonic build-revision floor. Exact
tombstones remain for pending deletes and bundled IDs; eligible old tombstones
compact to a monotonic delete floor so stale peers cannot resurrect removed IDs.
`AllowsRemoteRevision(author, stamp, db, id)` is the Sync admission boundary.
Future retention schemas are read-only. Evidence garbage collection runs only
after represented durable rows are removed.

## core/SyncPolicy.lua — saved transport policy

`SyncPolicy.Mode()` normalizes the additive saved `syncMode` setting to `off`,
`manual`, or `automatic`. `ContextBlock()` suspends transport while configured
combat, instance, or non-resting conditions apply. `Sync` owns session state and
clears volatile queues/partial transfers when policy becomes blocked; durable
tombstones and local DPS/build data remain available for a later safe session.
Off never joins or accepts protocol traffic. Manual joins only after `Sync Now`
and leaves when convergence finishes. Automatic reconnects and converges once a
safe resting context resumes.

## core/Sync.lua — release-aware build reconciliation

Current `WLRQ` build hashes contain eight overlay/tombstone bucket hashes followed
by a hex encoding of `BuildCatalog.CatalogVersion()`. Peers with the same catalog token send
only selected overlay rows and authorized tombstones. Legacy eight-bucket peers
and peers advertising another catalog token retain full merged-catalog recovery
for missing IDs, including exact bundled loadouts. Existing identities still
require an author-originated update: catalog tokens are compatibility hints, not
ownership authentication. A baseline-equivalent legacy payload is accepted
without copying it into `NexusDB.communityBuilds`. `Sync.Stats()` exposes
`baselineSkipped` and `overlaySent` for this boundary. Normal build and DPS hash
reads use revision caches; `Sync.GetCanonicalBuildHashes()` and
`DpsCapture.GetSyncHashUncached()` are explicit read-only verification paths and
must not be used by normal Sync scheduling.

## Post-review amendments (binding, from the pre-deploy adversarial pass)

- **Index bases:** `Policy` `action.index` is **1-based** into `board.cards`;
  `GameAdapter.Banish(index0)` takes the client's **0-based** perk index. `Main`
  converts at the seam (`action.index - 1`).
- `board` additionally carries `idSignature` (spellIds only, comma-joined) — the
  in-flight select resolution compares idSignatures like-for-like (the flag-suffixed
  `signature` would misread a failed select as success).
- **`Ratchet.Dominates` filler axis is COUNT-based**, not set-subset: every board
  forces a take, so per-run filler sets always differ and subset never holds; the
  spec's own potential Φ = coverage − ρ·fillerCount is count-based. Coverage stays
  set-superset. Advisor mode (no wishlist) NEVER saves.
- `Store` per-char `tomeTogglePending[lever] = { t = sentAt, want = bool }`; the
  ordered migration converts legacy bare numbers with `want=true`. Existing
  preferences, unknown fields, safety latches, demotions, and `priorAutoAccept`
  survive version bumps.
- `GameAdapter.DisabledLevers()` values are `"confirmed"` (server mirror) or
  `"pending"` (our unconfirmed request) — both truthy for pool math; only
  `"confirmed"` may drive the DISABLE_SUPPRESSES_GUARANTEE self-check demotion.
- Per-latch watchdog: a client `pending*` latch stuck >10s is declared dead for the
  session (per-action, mirroring the client's own failure mode), excluded from the
  whole-loop gate, its charges zeroed, status surfaced; recovers if the latch clears.
- Run boundary (`A.RunBoundaryReset`, called on every arrival at level 1): recorded
  picks void; owned-sync trust suspended until the client-reported owned set CHANGES
  from its at-reset snapshot (dead-run ghost protection).
- Level 80 with a live board runs the board FIRST; save only after the final board
  is spent. After any save, the slot cache is re-requested (~3.5s) for verification.
- Seeding saves only into an empty slot within `GetServerUnlockedSlots()`.
- `Panel.Toggle()` exists. `/wr undemote` clears flag demotions.

## tests (mine)

`tests/harness.lua` (stub extensions per design §10) + `tests/run_integration.lua`
(scenario asserts). Run: `luajit tests/run_integration.lua` from the addon root; exits
non-zero on failure. A red suite blocks deploy.

Build-catalog foundation: `tests/run_build_catalog.lua` and
`tests/run_build_catalog_migration.lua`. They cover merged precedence, defensive
copies, lossless legacy migration, redundant-baseline pruning, and idempotence.
