# Nexus — internal module contracts (v1.20.0-beta.1)

Binding interface spec for all modules. Authored from `WISHLIST_REALIZER_BUILD_PROMPT.md`
+ `WISHLIST_REALIZER_SPEC_ADDENDUM.md` + `WISHLIST_REALIZER_DESIGN.md` (the addendum wins
conflicts). Every `logic/*` and `data/*` file: plain Lua 5.1, NO WoW API, NO
SavedVariables, NO `ProjectEbonhold.*` — loadable under bare LuaJIT. All cross-module
data is plain tables produced by `core/GameAdapter.lua` (the only IO module).

Global namespace: `Nexus` (each file: `Nexus = Nexus or {};
local M = {}; Nexus.<Name> = M`). Version: `Nexus.VERSION = "1.20.0-beta.1"`
comes from `data/Release.lua`; .toc `## Version: 1.20.0-beta.1` stays in lockstep.

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
  entries  = { { spellId=n, quality=n, stacks=n, family=s,
                 locked=b|nil, sourceRole="ordinary"|"locked"|nil } , ... },
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

Presentation progress is exact-spell/tier aware. `Model.WishlistEntryProgress`
groups duplicate rows by `(sourceRole, spellId)`, applies each owned copy once,
and reads ordinary progress only from `Owned().bySpell` and locked progress only
from `LockedOwned().bySpell`. Family totals remain grouping/planning metadata;
they never complete a sibling tier. Explicit ordinary and locked roles remain
independent even when both request the same exact spell ID.
Automation targets that carry exact `qualityTiers[].spellId` use the same
spell-qualified quotas in `TargetProgress`, `QualityOfferNeeded`, and Policy;
quality-only targets retain the legacy compatibility path. Policy merges
permanent ownership only when `LockedOwned()` is fully synced and count-valid.
`Model.LockedProjection(locked, catalog?, maximumCopies?)` is the single pure
admission owner for that evidence: spell IDs and counts are positive finite
integers, canonical aliases and totals above six fail closed, and catalog-bound
callers additionally require exact derived `byFamily` coherence. Policy consumes
this owner directly; WishlistModel exposes thin spell-only/catalog-bound wrappers
for controller, renderer/export, Main/HUD, and automation consumers.
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

## core/Identity.lua — canonical authority and public presentation identity

`Identity.PublicRecordKey(record, field)`, the synchronous
`Identity.PresentPublicRecords(rows, field, options)`, and the incremental
`NewPublicPresentation`/`IndexPublicRecord`/`PresentPublicRecord` path are
presentation-only
consumers of the established `VerifiedOwnerKey` authority. Verified identities
are keyed and labeled by exact canonical `name@realm`; ambiguous records retain
their typed raw player/realm/claim/relay evidence tuple and never gain authority
through short-name similarity. Labels use a stable typed discriminator, reject
unsafe durable presentation text, and never depend on traversal order or a
Community list page. A public character batch may shadow an ambiguous
same-short-name row when a verified representative is visible, but it does not
mutate or delete the durable source. Community build batches retain distinct
build records while applying realm-qualified verified author labels and explicit
collision-safe `legacy/unverified` labels. Async callers index/present one owned
row per normal bounded acquisition step; no completion callback rescans the full
result set. This policy does not call or broaden `SamePlayer()` and owns no score,
loadout, persistence, transport, or paging rule.

`Identity.DisplaySafeText(value, maxBytes, allowEmpty, allowLineBreaks)` is the
display-only boundary for untrusted plain text entering WoW rich-text widgets.
It validates the raw wire/storage value, then doubles each literal pipe. Raw
wire, SavedVariables, hashes, diagnostic export, and explicit export values
remain lossless. Copyable diagnostic and link fields expose the reversible
doubled-pipe serialization and never restore raw rich text on focus. Public presentation copies expose `displayTitle`,
`displayDescription`, and display-safe identity labels. Ordinary Community,
Leaderboard, tooltip, Panel, and diagnostic/export surfaces consume those
projections or apply the same helper at their final widget boundary.

`WishlistRenderer` keeps the editable Wishlist name's raw value separate from
its rich-text display projection. `SetNameText` stores the exact raw value and
writes only the doubled-pipe projection to the EditBox. `NameText`, save,
refresh, and promotion paths read the raw value. An explicit user edit is
decoded from the doubled-pipe display representation and immediately
reprojected, so repeated open/save cycles do not expand pipes and edited text
stays inert in the widget.

## core/Store.lua — `Nexus.Store` (SavedVariables: `NexusDB`)

`Store.Init()` owns a two-phase legacy-name decision before its existing
ordered additive migrations. A valid non-empty `WishlistRealizerDB` is rebound
by exact table identity only when `NexusDB` is absent or an empty table; a
non-empty current table is authoritative and is never merged with a distinct
legacy table. A non-nil non-table value under either name blocks the decision
without mutation. The same table under both globals is an interrupted adoption
retry. Settings/default normalization, LoadoutEvidence, BuildCatalog, and
DataCompaction finish before Store adds the versioned
`nexusStoreMigrations.wishlistRealizerDB` completion marker and releases the
legacy global. A malformed legacy value, malformed marker, incompatible marker
namespace, or downstream owner failure leaves the marker unpublished and the
legacy value recoverable. Main keeps a Store initialization failure session-only
and does not initialize persistent diagnostics until Store succeeds, preventing
fallback writers from bypassing this recovery boundary. The independently
scheduled Changelog likewise remains persistence-passive
until `NexusDB` is a table. `Nexus.toc` continues declaring both SavedVariables
names pending a separate compatibility decision.

`Store.Settings()`, `Store.State()`, `Store.CurrentOwnerKey()`,
`Store.RegisterCurrentCharacter()`, `Store.IsAccountOwnerKey(ownerKey)`, and
`Store.AccountCharacters()`. Durable mutable character state is keyed only by a
canonical local `name@realm`. Until both name and realm are available, `State()`
returns one session-only transient table and creates no durable short-name or
`name@unknown` key; that transient table and preserved legacy short-key rows are
never promoted into canonical state. Existing canonical state remains authoritative
and is filled only for missing owned shape fields. Registration writes only a
coherent exact current-character row, preserves contradictory and `@unknown`
evidence, and stands down before allocating account storage when Store settings,
legacy-migration metadata, or a downstream read-only owner is future/active.

## core/LegacyDataMigration.lua — `Nexus.LegacyDataMigration`

The ordered bounded converter stages account and DPS data before one atomic table
swap. Canonical account map keys are authoritative only when their row evidence is
coherent. An unresolved/short source may move to a canonical owner only through one
explicit coherent `source.ownerKey` bridge, only when no canonical source row or
competing bridge already owns that destination. Existing canonical fields always
win; distinct ambiguous sources remain under deterministic collision-safe recovery
keys with unknown nested fields retained. The exact account-table owner is rechecked
before commit, so source replacement restarts staging without an unbounded whole-save
copy or comparison. `AccountWritesAllowed(database)` is checked before Store allocates
account storage and rejects active/incompatible migration metadata plus every settings
schema newer than `Store.SettingsVersion()`.

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
`RegisterReferenceProvider(name, callback)`, `DurableStore(database)`, and
`CollectGarbage(db)` own the content-addressed evidence `entries` pool. That
pool is the `loadoutEvidence` field of the durable authority bundle once
`NexusDB.authorityBundle` is occupied; the PR #68 `NexusDB.loadoutEvidence`
location is a preserved read-only admission input only while the bundle is
absent, and is never consulted as a fallback after occupancy. The module
performs no durable write of its own: `DurableStore(database)` returns the
store the commit coordinator installs inside the next complete bundle pointer,
which RAW-01 makes the sole durable payload write, and it returns nil for any
database that is not the bound one so a detached authority instance can never
borrow this module's state. A malformed or absent store is shape-repaired into
a detached replacement, never in place, so a preserved legacy input keeps its
table identity and its bytes and a live nested bundle field is never mutated.
Identity is the full canonical spell/quality/stack/locked tuple string, never a
short hash or caller claim. Equal canonical arrays share one stored entry; a
mismatched claim or corrupt stored key is retained as a bounded in-session
conflict and never overwrites another exact array. Public resolution always
returns a defensive copy.

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

Construction is publish-after-success. A cold `Builds(filters)` read never
walks the catalog in one call: it returns `nil, nil, "pending"` and retains one
persistent job that `RequestBuilds`/`PumpBuilds` advance through the bounded
BuildCatalog summary cursor and the resumable DpsCapture eligibility cursor;
only an atomically published result is served, and a represented-revision
change or cursor error cancels the job and publishes nothing. A publication
made by the retained job counts as current for `BuildsCurrent` only after a
`Builds`/`RequestBuilds` read has served it, so a consumer's last-good copy
is reported stale until it re-reads. Leaderboard
construction keeps the synchronous retry-once form: if a represented revision
changes while it builds, the module retries once against the new snapshot, and
an error or second unstable pass publishes nothing. The module owns no frames,
SavedVariables, revisions, transport, GameAdapter access, scheduler work, or
automation authority.

## core/WishlistModel.lua — pure Wishlist draft calculations

`Nexus.WishlistModel.New()` constructs the single stateless calculation owner
used by `Nexus.WishlistEditor`. It accepts captured catalog rows, real locked
ownership, committed lock targets, draft tables, class token, and name values;
it returns new draft maps, canonical upload/export entries, reconciliation
results, and lock-commit plans without mutating caller inputs.

The model owns Echo name/family identity, max-stack and 79-copy totals, the
six-copy explicit-evidence envelope, the six-slot replacement budget,
trusted/untrusted import normalization, quality
and family collision handling, immutable add/remove/stack/lock transitions,
canonical upload ordering, export-entry construction, fulfilled-target
reconciliation, name trimming, and the exact desired lock-target map. Counted
lock-target records retain `{ version=1, copies, replaces, rows }`, including duplicate
exact rows and unknown/provenance fields, across reconcile, commit, reopen,
export, progress, and automation planning. Current-schema tables require dense
positive rows for the containing exact spell whose stack total equals `copies`;
when present, row quality is a finite nonnegative integer, and catalog-bound
admission requires or projects the exact catalog quality. Malformed and future table
contracts fail closed, while legacy `true` and positive-integer replacement-ID
one-copy targets remain compatible; other scalar types/ranges are invalid. The
complete target map is admitted atomically: canonical key aliases, unknown catalog
identities, self/invalid replacement IDs, and aggregate totals above six fail closed.
Counted rows retain every validated replacement pairing, while their top-level
`replaces` field remains a compatibility pointer to one member of the canonical,
numerically sorted replacement set. Catalog-bound consumers pass their captured
catalog into the same atomic model admission; mixed known/unknown maps fail
closed for automation, HUD progress, and Tome readiness. Admitted values,
catalog rows, counted records, nested rows, and unknown provenance fields are
cycle-safe defensive copies, so admission, reopen,
fulfillment, and commit results cannot mutate caller or historical evidence. It does
not parse or encode EBH1 bytes: `core/Codec.lua` remains the sole wire owner.
It does not read production lock intent: `AutomationRuntime.LockDesignTargetsFor`
remains the established automation reader.

WishlistController captures live values and delegates every calculation to this
single model instance. WishlistModel contains no SavedVariables, Store, Adapter,
Project Ebonhold, transport, print, frame, or gameplay path, and no replaced
calculation fallback remains in the editor or controller.

## core/WishlistController.lua — Wishlist draft/session/action owner

`Nexus.WishlistInternals.Controller.New(options)` constructs the sole mutable
Wishlist controller. WishlistEditor injects the existing WishlistModel instance,
Store facade, late-bound account root, GameAdapter facade,
notifications, and Community navigation intention. Repeated adapter binding
preserves the current draft and pending retry.

The controller owns ordinary and locked-design draft maps, fulfilled targets,
candidate/edit/create association contexts, assignment mode, filter and bounded
scroll offsets, content-key snapshots, Store lock-target migration/commit,
canonical apply preparation, exact Adapter upload/association calls, and the
bounded spacing retry. The first spacing payload is retained by identity, at
most 12 retry uploads are made, and the next pump expires without another
upload. Another explicit spacing request still reaches the Adapter but does not
replace that pending payload; success or any non-spacing failure clears it.

WishlistEditor retains public facade names, confirmation/import/export and
display-popup assembly, and messages tied to presentation. WishlistRenderer owns
the main frame, switch menus, callbacks, tooltips, and fixed visible-row pools.
Rendering and status reads submit no gameplay or association actions. The
controller creates no frames, uses no Project Ebonhold global, and mutates
gameplay only through GameAdapter; Store remains the persistence owner and
unknown account/character preference fields are preserved.

## ui/WishlistRenderer.lua — Wishlist main-editor presentation

`Nexus.WishlistInternals.Renderer.New(options)` constructs the single main
Wishlist editor renderer. It consumes controller-published catalog, ownership,
locked, wishlist, candidate, loadout, preference, draft, and session projections;
all clicks emit controller or facade intentions. It owns `NexusEditorFrame`,
`NexusWishlistEditorSwitchMenu`, `NexusWishlistEditorLoadoutMenu`, the named
search/name inputs, tooltips, scrolling, and exactly 19 available plus 18 pending
visible rows. Refresh and scrolling rebind those fixed pools without allocating
one frame per catalog or draft result.

The renderer contains no SavedVariables root, Store, transport, association,
upload, or gameplay-mutation path. The controller contains no frame API.
`WishlistEditor.lua` constructs exactly one model/controller/renderer chain and
keeps `NexusDisplayPopup` and its overlay controls for the final bounded popup
checkpoint.

## core/CommunityProjection.lua — Community list/detail composition

`Nexus.CommunityInternals.Projection.New(options)` is an internal, frame-free
constructor. Its list path normalizes copied filter values and composes the
established `ViewProjections.Builds`/`BuildsCurrent` readers. It never performs
a parallel catalog walk, DPS identity join, ordering pass, or SavedVariables
normalization. A current list read returns the same borrowed immutable snapshot
without another defensive full-result copy; Community rendering must not mutate
that snapshot.

The selected-detail path reads one exact BuildCatalog record and captured
player/admin/owned/Details values, then materializes exact-loadout availability,
missing Echo state, ownership actions, locked-Echo evidence, and DPS labels. It
is keyed by typed selection, represented build/DPS revisions, and only the
captured values relevant to that build. Unchanged detail reads perform no exact
load, board scan, leaderboard read, or personal-best read. Dependency failures
publish no partial snapshot and recover on a later read.

The constructor receives defensive readers and captured values only. It creates
no frame and owns no BuildCatalog/DPS mutation, SavedVariables, GameAdapter,
Project Ebonhold, Sync/transport, scheduler, revision, or gameplay authority.
`Nexus.CommunityBuilds` remains the public facade and assembles the controller
and renderer behind its unchanged entry points.

## core/CommunityController.lua — Community interaction authority

`Nexus.CommunityInternals.Controller.New(options)` constructs the single
frame-free owner of Community selection, persisted filter transitions, post and
edit drafts, saved-loadout import/repair, validated BuildCatalog/DPS/Sync
intentions, exact-loadout requests, and lock-in retry state. The public
`Nexus.CommunityBuilds` methods are delegates; rendering may read catalog and
projection values but does not admit, edit, tombstone, remove, broadcast, or
upload records.

Lock-in confirmation remains UI-owned. On acceptance the controller snapshots
the validated title/Echo payload once. A spacing result creates one pending
record; each pump makes at most one retry while its cumulative counter is below
12. Another spacing result never recreates or refreshes that record. After 12
unsuccessful retry uploads, the next pump reports the established friendly
spacing error and clears without a thirteenth retry upload. Success and
non-spacing failures clear immediately. A new explicit user confirmation may
supersede older pending work, matching the established interaction contract;
automatic retries cannot replace a payload or refresh its lifetime.

The controller creates no frame, row, popup, or gameplay action. Catalog, DPS,
Sync, and GameAdapter remain the mutation/transport service owners behind their
existing facades; ownership checks, tombstones, exact IDs, and broadcast order
remain unchanged.

## ui/CommunityRenderer.lua — Community presentation authority

`Nexus.CommunityInternals.Renderer.New(options)` receives exactly one
CommunityController instance and the CommunityProjection resolver, then
constructs the sole owner of
the established `NexusCommunityBuildsFrame`, its detail panel, main controls,
status labels, virtual list binding, and reusable card/header pools. It consumes
defensive readers and controller intentions injected by `CommunityBuilds`; it
does not bind `NexusDB`, admit or tombstone catalog records, enqueue or broadcast
Sync traffic, upload gameplay state, or call Project Ebonhold services.
Remote and persisted text remains raw in controller/storage ownership; every
rich-text label and editable field uses an inert display projection, and edit
submission decodes that projection back to the unchanged raw value.

The public `Nexus.CommunityBuilds` facade retains every signature and stable
frame name. Main/detail rendering binds only the visible window plus bounded
overscan, scrolling reuses the pool, failed row binding reclaims checked-out
cards, active Sync marks data dirty without rebuilding, and the quiet edge
publishes one deferred refresh. The renderer also owns the established
`NexusPostPopup` and `NexusEditPopup`, their menus, fields, preview rows, and
presentation callbacks; draft and mutation authority stays in the controller.

`Nexus.CommunityBuilds` is a thin assembly/delegation facade. Exactly one
CommunityProjection, CommunityController, and CommunityRenderer instance is
created lazily and reused across repeated initialization and public entry calls.
The facade creates no frame, binds no frame callback, and contains no duplicate
catalog walk/sort/DPS join, Sync, adapter, persistence, or presentation path.
Candidate enumeration, exact build/DPS reads, projection context, and edit-draft
preparation live in the controller; presentation formatting stays in Renderer.

## ui/VirtualList.lua — fixed-height visible windows

`Nexus.VirtualList.Window(count, rowHeight, viewportHeight, offset, overscan)`
is pure Lua 5.1 math. It clamps invalid/tiny/end offsets and returns the exact
visible-plus-overscan index range, content height, and maximum scroll offset.
It owns no frames or state.

CommunityRenderer retains one current defensive projection and binds only this
window into its reusable cards. Scrolling rebinds that window without
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

The scheduler is never an automation authority. Main routes its direct
0.2-second safety heartbeat through one `MainLifecycle` to one
`AutomationRuntime`, which calls
`GameAdapter.Poll()`. The expensive plan/owned/slots/panel
step runs only after consumed adapter dirtiness, a known action deadline, an
explicit refresh, or the five-second self-healing fallback. Combat/run latches,
in-flight action resolution, action deadlines, and all gameplay mutations remain
inside AutomationRuntime and outside scheduler callbacks. Adding one of those
paths to a scheduler callback is a contract violation even if the callback uses
a unique key.

## core/MainLifecycle.lua — boot and event coordination

`MainLifecycle` owns initialized state, Store-first world initialization,
optional owner initialization, lag observation, WoW event routing, and the
ordered `Sync -> DpsCapture -> AutomationRuntime` per-frame path. Main retains
the exact frame, seven event, two script, and three slash registrations and
delegates through one Lifecycle instance. Repeated world events reuse the same
owners; failed Store or missing dependency initialization remains retryable.

The database passed to diagnostic and overlay owners is read only after
`Store.Init()` completes, so a legacy-root adoption or other authoritative
binding cannot leave later owners on a stale table. Lifecycle owns no frame,
slash global, Sync queue, SavedVariables schema, or direct Project Ebonhold
access.

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

An 80-85-copy designed Wishlist with unavailable lock roles gains read authority
only from its associated active numbered loadout when that row is verified, its
aggregated exact spell/copy identity matches, and fully synced `LockedOwned()`
counts can be subtracted without underflow. Inline active lock booleans are not
authority. The adapter derives a
new 79-ordinary/six-locked projection without rewriting either server mirror or
SavedVariables; mismatch, partial/stale counts, excess/underflow, or non-active
same-name rows remain evidence-pending.

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
published candidates. `Nexus.Updates` retains up to 32 accepted peer versions as
ephemeral diagnostic observations. Peer observations never create or replace an
update notice. Only a newer stable version named by bundled release metadata may
create authoritative update state and emit at most one enabled chat notice per
session. Initialization conservatively quarantines an older unverified notice,
preserves its unknown fields, and is idempotent. Opt-out hides chat/UI without
erasing bundled authority. No module performs an update network request or
install.

## core/BuildCatalog.lua — `Nexus.BuildCatalog`

The catalog is the single admission authority for community build rows. Nothing
outside this module publishes catalog state, and every read is served from one
published root generation.

Legacy facade: `Init(db, bundled)`, `Get(id)`, `GetSummary(id)`, `All()`,
`Summaries()`, `DeltaSummaries()`, `IsAuthor(name)`, `ForEach(visitor)`,
`Count()`, `Put(build)`, `RemoveOverlay(id)`, `SetTombstone(id, tombstone,
options)`, `ClearTombstone(id)`, `OverlaySnapshot()`, `DeltaSnapshot()`, and
`TombstoneSnapshot()`. Returned records/tables are defensive copies; summary
surfaces deliberately omit Echo arrays.

Admission: `BeginRootAdmission(db, bundled)` captures one generation-bound
handle and `PumpRootAdmission()` advances it in bounded slices until it reports
a terminal state; `CancelRootAdmission()` discards an uncommitted candidate
without publishing. A candidate never becomes public before its final commit, a
failed candidate changes nothing, and restart resumes from cursor zero.
`RootState()`, `AuthorityState()`, and `Status()` report the published root, its
fixed refusal reason when unbound or invalidated, and bounded status accounting.
`Budget()` and `BudgetCounters()` expose the fixed
`CATALOG_AUTHORITY_BUDGET_V1` totals and the per-pump frontier slice actually
consumed. Replacing a bound SavedVariables owner is current-source drift and
publishes `ROOT_INVALIDATED`; a reload returns `ROOT_UNBOUND` until admission
reproduces the root.

Bounded reads: `BeginRecordCursor()`, `BeginSummaryCursor()`,
`BeginDeltaCursor()`, `BeginRelatedCursor(id)`, `BeginSavedMirrorCursor()`, and
`BeginDiagnosticCursor()` return generation-bound tokens advanced by their
matching `*Next` call. A token whose root generation has been replaced answers
`STALE_CURSOR` exactly once and `INVALID_CURSOR` afterwards. The one-call
collection reads (`All`, `Summaries`, `DeltaSummaries`, `TombstoneSnapshot`,
and the snapshot pair) refuse with `CURSOR_REQUIRED` above the fixed one-call
limits instead of returning a partial or unbounded copy.

Identity and evidence: typed IDs are collision-free (`n:<int>` for numbers,
`s:<len>:<bytes>` for strings) and protocol-7 refuses numeric, over-width, and
invalid-UTF-8 identities. Admission stores one canonical evidence record whose
duplicate role-bearing tuples merge by checked stack addition, so a public copy
carries the unique canonical tuple count. `Nexus.LoadoutEvidence.SemanticLimits`
owns the issue #22 envelope (79 ordinary, 6 locked, 85 total copies), which is a
semantic bound separate from the 256-entry parser ceiling; a record over the
envelope is refused with `SEMANTIC_ENVELOPE`. `FindExactFingerprint`,
`FindExactFingerprintId`, and `ResolveFingerprintIdentity` read bounded identity
and fingerprint indexes, never a scan. Unknown fields are preserved at their
original scope, including tuple-scoped subtrees; an unknown subtree that cannot
be attributed to one tuple is refused with `AMBIGUOUS_NESTED_UNKNOWN_SCOPE` or
`UNKNOWN_TUPLE_SCHEMA_MIGRATION_REQUIRED`. A newer `buildCatalog.schemaVersion`
binds the catalog read-only: metadata, overlay rows, and tombstones are
preserved without migration, and every mutation API refuses until a supported
database is rebound.

Mutation and tombstones: `BeginAllocationClaim`/`CancelAllocationClaim`,
`PutWithClaim`, `PutDeferred`/`PublishDeferred`, and `AllocationOccupancy`
bound ID allocation against every reserved surface. `SetTombstone` performs one
atomic row-to-tombstone replacement over an exact admitted row; exact replay is
a no-op, unequal replay preserves both raw objects, and a delete over a row that
was never admitted is refused. Reservations are deny-only substates
(`TOMBSTONE_CURRENT_DENY` in-session, `TOMBSTONE_RELOADED_BLOCK_ALL` after a
reload, `TOMBSTONE_OPAQUE_BLOCK_ALL` for an unproven remote order). Only a
current, module-private one-shot `TombstoneReadmissionClaimV1` from
`BeginTombstoneReadmissionClaim` can replace one; remote input, recovery,
migration, and replay cannot.

Maintenance: retention and compaction run inside one transaction bound to the
exact database. `BeginCatalogMaintenance(db)` returns a handle refused with
`DETACHED_DATABASE` when the binding does not match;
`MaintenanceOverlayNext`, `MaintenanceReplaceRow`, `MaintenanceEvictOverlay`,
`MaintenanceRetireTombstone`, and `MaintenanceExpireBarrier` collect bounded
work off-state, and only `CommitMaintenance` publishes one replacement root.
`CancelMaintenance` discards the candidate and leaves the prior root intact.
Overlay writes establish `evidenceKey`; after compaction is enabled, only an
exact deep round trip removes the inline duplicate. The canonical overlay
backing table is `NexusDB.authorityBundle.communityBuilds`, the catalog payload
field of the durable authority bundle. The PR #68 `NexusDB.communityBuilds`,
`NexusDB.syncTombstones`, `NexusDB.buildCatalog` and
`NexusDB.communityRetentionEvictions` locations have no Package B writer: they
are admission input only while the bundle is absent, are preserved
byte-identically once it is occupied, and are never used as a fallback after
occupancy. Read precedence is authorized tombstone, then a personal or
at-least-as-new overlay row, then the bundled row. `DeltaSnapshot()` contains
only overlay rows that win that selection; stale hidden rows and bundled-only
rows are excluded.

## core/SyncProtocol.lua — pure wire and compact-payload boundary

`Nexus.SyncInternals.Protocol.New(options)` constructs stateless validation and
payload helpers from injected Version, Codec safe-tree, and owner-key callbacks.
It owns field/identifier/hash/version/integer limits, escaped wire length, the
eight-field splitter, accepted compact/legacy build conversion, and safe payload
decoding. Calls send no packets and mutate no queue, peer, catalog,
SavedVariables, diagnostics, or gameplay state. `core/Sync.lua` remains the only
public `Nexus.Sync` facade and delegates these pure operations to one instance.

## core/SyncTransport.lua — durable outbound transport owner

`Nexus.SyncInternals.Transport.New(options)` constructs the sole stateful owner
of accepted bulk and control packets. It enforces the independent queue caps,
atomic batch admission, response headroom, control-before-bulk priority, FIFO
order, channel revalidation, pacing, throttle attribution, retained send-failure
retry, and process-idempotent message filters through injected clock/send/log
callbacks. Queue-capacity probes happen before responder serialization or
candidate work. Pending deletes and represented records stay with their existing
owners until their exact payload is admitted; accepted entries remain durable
until sent or the established session reset. The module performs no catalog,
hash, encoding, chunking, ownership, tombstone, SavedVariables, or gameplay work.
`core/Sync.lua` remains the only public `Nexus.Sync` facade and delegates to one
transport instance, so no old and new send path run together.

## core/SyncCompatibility.lua — read-only compatibility projection owner

`Nexus.SyncInternals.Compatibility.New(options)` constructs the sole owner of
Sync's catalog-token, current/delta/legacy/canonical build hashes, DPS hash
projection, build fingerprints, compact summaries, and revision-keyed candidate
views. Hash-cache and catalog dependencies are resolved through injected
read-only callbacks, so unchanged reads reuse represented revisions and current
peers retain byte-identical canonical hashes. Candidate discovery is resumable:
one overlay row or tombstone is examined per advance, a completed view is reused
while its delta hash and sender key remain current, and reset/invalidation never
touch represented records. The module may encode a prepared summary but cannot
admit or send it; it performs no queue, ownership, tombstone mutation,
SavedVariables, GameAdapter, or gameplay operation. `core/Sync.lua` keeps the
public facade and supplies read-only dependencies to one compatibility instance.

## core/SyncReconciler.lua — bounded response-planning owner

`Nexus.SyncInternals.Reconciler.New(options)` constructs the sole owner of
pending requester and exact-loadout work, fair response selection, pending-work
TTL/absolute age, and bounded response statistics. Each `Process(elapsed)` call
performs cheap expiry/timer maintenance and at most one ready preparation,
loadout, or bucket-response unit. Transport backpressure returns before hashes,
candidate snapshots, catalog lookup, serialization, encoding, or chunk work;
accepted work is retained and its absolute age is never refreshed by a
queue-full retry. Prepared loadouts and immutable candidate progress are reused
across retries. Peer-claim suppression and post-admission claim publication
recheck candidate currency and live tombstone ownership instead of caching that
mutable decision during preparation; claims are requested only after the
corresponding payload is admitted. Legacy or catalog-mismatch requests reconcile
only bounded mutable delta/summary state; known bundled loadouts remain
available by explicit ID.
The module parses no wire data, mutates no catalog/ownership/tombstone state,
owns no queue or SavedVariables, and performs no gameplay operation.

## core/SyncInbound.lua — synchronous validation and assembly owner

`Nexus.SyncInternals.Inbound.New(options)` constructs the sole owner of build
and DPS inflight transfer tables, shared global/per-sender caps, chunk
consistency/byte limits, idle/absolute expiry, recognized-code dispatch, and
sender-bound synchronous arrival order. It validates envelopes and assembles
complete payloads before invoking narrow request, claim, summary, deletion,
build, DPS, and peer callbacks. It has no inbound FIFO: `Sync.HandleIncoming`
delegates and returns in the same event callback, while `OnUpdate` performs only
established expiry cleanup. Rejected traffic cannot call authoritative commit
callbacks or mutate transport, represented data, peer authority, persistence,
or gameplay state beyond bounded rejection diagnostics. The module owns no
outbound queue, catalog, tombstone, SavedVariables, DpsCapture, or GameAdapter
state; `core/Sync.lua` retains all validated mutation and relay callbacks.

## core/SyncDiagnostics.lua — bounded passive Sync projections

`Nexus.SyncInternals.Diagnostics.New(options)` constructs the sole owner of the
bounded Sync event history and the established live `Sync.Stats()` scalar table.
It builds defensive work and leaderboard-status projections only from scalar
component snapshots supplied by the coordinator. Logging, clearing, overflow,
and projection reads cannot call transport, refresh represented revisions,
mutate SavedVariables, or submit gameplay actions. `Sync.EventLog()` and
`Sync.RawLog()` remain defensive row snapshots; `Sync.Stats()` retains its
established live table identity across `Sync.Init()` resets.

## core/SyncSession.lua — peer and convergence session owner

`Nexus.SyncInternals.Session.New(options)` constructs the sole owner of known
peers, receive-window/count state, bounded legacy exact-loadout recovery,
manual/login convergence, and channel-join retry. Remote developer-status
requests are default-inert: `HandleStatusRequest` and `FlushStatusReply` return
false and retain no pending state. `SendStatusTo` remains the explicit local
manual diagnostic action. The session preserves the established cooldown,
quiet-window, retry, status text, peer-row identity, and reset behavior. Recovery
and convergence can admit only through the injected durable transport facade;
the module parses no wire input and mutates no catalog, DPS record, tombstone,
ownership, SavedVariables, or gameplay state. `core/Sync.lua` invokes its narrow
update methods in the same order as the prior inline implementation.

## core/Sync.lua — release-aware build reconciliation

`core/Sync.lua` remains the only public `Nexus.Sync` facade. It assembles one
Protocol, Transport, Compatibility, Reconciler, Inbound, Diagnostics, and
Session instance; retains validated build/DPS/tombstone commit callbacks; and
coordinates the established ordered `OnUpdate`. No old and extracted session,
diagnostic, inbound, reconciliation, compatibility, or transport mutation path
runs simultaneously.

Current `WLRQ` build hashes contain eight overlay/tombstone bucket hashes followed
by a hex encoding of `BuildCatalog.CatalogVersion()`. Peers with the same catalog token send
only selected overlay rows and authorized tombstones. Legacy eight-bucket peers
and peers advertising another catalog token receive only bounded mutable
overlay/tombstone reconciliation plus summaries; exact bundled loadouts are
requested explicitly by known ID. Existing identities still
require an author-originated update: catalog tokens are compatibility hints, not
ownership authentication. A baseline-equivalent legacy payload is accepted
without copying it into the durable overlay payload. `Sync.Stats()` exposes
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
