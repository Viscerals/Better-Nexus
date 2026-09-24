# Nexus — internal module contracts

## Status of this document

This file has two parts.

1. **Current rolling and Orb contract** (next section). It is authoritative. It
   describes the production path of the current source. Where any later section
   conflicts with it, the current contract wins.
2. **Historical v1.19.4 module contracts** (all sections after it). They were
   written as the binding interface spec for v1.19.4. They are kept as history.
   Sections marked **HISTORICAL** describe the obsolete predicted-guarantee
   model. No production path uses that model. Do not implement from those
   sections, and do not restore guarantees to satisfy them.

## Current rolling and Orb contract (authoritative)

- **No inferred guarantee.** There are no guaranteed future Echo rolls. A saved
  or verified build is evidence of identity, contents and ownership only. It
  predicts no future offer. `isGuaranteed` on a board card is an observed flag of
  the current offer: that card cannot be banished or frozen. It implies nothing
  about a later board.
- **`Ratchet.PredictQueue()`** always returns `{ entries = {}, inferred = false }`.
  The old model exists only as `Ratchet.HistoricalGuaranteeQueue` for historical
  fixtures. The production state (`core/AutomationRuntime.lua`) supplies an empty
  queue.
- **`Policy.Decide(state)`** returns a wait when `state.ordinaryBoardAllowed ==
  false`. Otherwise every ordinary board goes to
  `EchoWeaver.DecideNexus(state)`. `state.snapshotVerified`, `state.queue` and
  `state.flags` select no planner and change no decision. The scoring rules in
  the historical `logic/Policy.lua` section below are reachable only when
  EchoWeaver is not loaded, which the production TOC never allows, and then
  only with an empty queue.
- **`EchoWeaver.Decide(input)`** is the pure ordinary planner. Without
  `input.policy` it follows the base strategy. `DecideNexus` passes `EchoWeaver.NEXUS_POLICY`, whose options
  are deliberate, documented differences (`docs/ROLLING_ORB_REVIEW_EADFF8A.md`).
  Exact `plan.requestedCounts` per spell ID, rolled plus permanent ownership,
  actual charges and the per-action permissions are its inputs. Actions:
  `take`, `freeze`, `banish`, `reroll`, `wait`. Action `index` is 1-based.
- **Ordinary-board gate.** `GameAdapter.OrdinaryBoardAllowed()` guards `Take`,
  `Banish`, `Reroll`, `Freeze` and automatic rolling. It blocks while Orb mode
  owns or has an unresolved action. When an `OrbService` exists it also requires
  the known, not-pending state from `OrbAdapter.ServiceState()`. One explicit
  legacy capability case keeps ordinary rolling: `NO_ORB_SERVICE` (the client
  has no `OrbService` at all). Every case of an existing service other than
  known and not pending blocks: unknown state, a pending offer, a service
  without an `IsStateKnown` member (`MISSING_STATE`), a malformed service or
  member, a non-boolean return, a thrown callback or a throwing read. (Until
  2026-09-21 a service without `IsStateKnown` was permitted as `PENDING_ONLY`;
  the user's R1 requirement names only an absent `OrbService` as the exception,
  so that permit was removed.) The automation loop evaluates again when this gate
  changes.
- **Orb mode** is specified in `docs/ORB_MEMORY_MODE.md`. All Orb mutation sits
  behind `GameAdapter.Orbs`. An unresolved Orb action is never retried, refunded
  or erased. Recovery after reload is passive.
- **Version.** The release identity lives in `data/Release.lua` and `Nexus.toc`,
  not in this file.
- **Tests.** The maintained offline suite is `tools/run_prototype_tests.py` with
  `tests/prototype/`. No-guarantee behaviour: `rolling_no_guarantee`,
  `rolling_no_guarantee_runtime`, `policy_compare`, through the maintained
  adapter `tests/prototype/policy_adapter.lua`.

# Historical v1.19.4 module contracts

Everything below is the v1.19.4 text. It is unchanged except for the
**HISTORICAL** markers. Data shapes that the current code still produces (catalog,
wishlist, owned, board, charges, slots) remain a useful description. Version
strings, the `flags` and `queue` shapes, `Ratchet.PredictQueue`, the
`Policy.Decide` rules and the `tests (mine)` section are historical.

Binding interface spec for all modules (as of v1.19.4). Authored from `WISHLIST_REALIZER_BUILD_PROMPT.md`
+ `WISHLIST_REALIZER_SPEC_ADDENDUM.md` + `WISHLIST_REALIZER_DESIGN.md` (the addendum wins
conflicts). Every `logic/*` and `data/*` file: plain Lua 5.1, NO WoW API, NO
SavedVariables, NO `ProjectEbonhold.*` — loadable under bare LuaJIT. All cross-module
data is plain tables produced by `core/GameAdapter.lua` (the only IO module).

Global namespace: `Nexus` (each file: `Nexus = Nexus or {};
local M = {}; Nexus.<Name> = M`). Version: `Nexus.VERSION = "1.19.4"`
set in Main; .toc `## Version: 1.19.4` kept in lockstep.

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

owned = {                    -- the granted mirror only: rolled stacks. Locked
                             -- Echoes are separate (LockedOwned). A submitted
                             -- Select is intent, never owned, until the mirror
                             -- shows it (#62); it holds InFlight() meanwhile
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

-- HISTORICAL: these flags belong to the obsolete guarantee model. The current
-- planner reads neither of them.
flags = { DISABLE_SUPPRESSES_GUARANTEE = true|false,  -- true (user-confirmed) unless runtime-demoted
          REROLL_HOLDS_GUARANTEED = true|false|nil }  -- nil = conservative

plan = Strategy.Compile output (below).
queue = Ratchet.PredictQueue output (below).  -- HISTORICAL: now always empty, inferred=false
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

> **HISTORICAL (PredictQueue, RunsEstimate queue input).** The predicted queue
> below is the obsolete guarantee model. The current `Ratchet.PredictQueue()`
> takes no meaningful input and returns an empty queue. See the current contract.

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

> **HISTORICAL.** Rules 1-7 below describe the guarantee-based scoring of
> v1.19.4 (guaranteed card, `wantedInQueue`, "guarantee already exhausted").
> Production routes every ordinary board to `EchoWeaver.DecideNexus`. See the
> current contract. Do not reintroduce these rules.

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

> **HISTORICAL in part.** `defaultFlags` and the reroll scoring params belong to
> the obsolete guarantee model. The current planner reads the per-action
> permissions (`autoBanish`, `autoReroll`, `autoFreeze`) and no guarantee flag.

Pure table: `params` (coverage=100, qualityBonus=2, anchorUnlock=150, diversity=5,
duplicate=-5, filler=-15, rerollCost=8, rerollHoldThreshold=25), `defaultSettings`
(autoPick=true, autoActivate=true, autoDisable=true, autoSave=true, autoBanish=true,
anchorSpellId=nil, leverOptOut={}), `defaultFlags` (DISABLE_SUPPRESSES_GUARANTEE=true
-- user-confirmed 2026-07-23, runtime-demotable; REROLL_HOLDS_GUARANTEED=nil).

## core/Store.lua — `Nexus.Store` (SavedVariables: `NexusDB`)

`Store.Init()` (wholesale-replace on version change, sibling pattern), `Store.Settings()`,
`Store.State()` (per-char keyed subtable: tomeTogglePending per lever w/ timestamps,
priorAutoAccept, flagDemotions, and a legacy recordedPicks field that is kept for
round-tripping but no longer written or read, #62). Char key from
`UnitName("player")` guarded — if unavailable, defer (never latch "Unknown").

## core/GameAdapter.lua — `Nexus.GameAdapter` (sole IO; my file)

Exposes to Main: `Init(callbacks)`, `Catalog()`, `Board()`, `Charges()`, `Owned()`,
`Wishlist()`, `Slots()`, `DisabledLevers()`, `DiscoverySynced()`, `Level()`, `Horizon()`,
`InFlight()`, `Take(spellId)`, `Banish(index)`, `Reroll()`,
`ToggleLever(leverId, wantDisabled)`, `Activate(slot)`, `Save(slot, name)`,
`SetSoloPicker()`, `RestoreAutoAccept()`, `RivalDetected()`, `RequestSlots()`,
`RequestGranted()`. All per design doc §4 (deep copies, ledger, gate v2 latch-polling,
run-boundary, self-check demotion hook).

## ui/*

- `ui/Readout.lua` — `Nexus.Readout`: pure-ish formatting: `Readout.Status(model)`,
  `Readout.CardLine(card, annotation, delta)`, `Readout.QueueLines(queue, n)`. No IO.
- `ui/Panel.lua` — `Nexus.Panel`: movable frame `NexusPanel`:
  status line, up to 3 card lines + recommendation, AUTO ON/OFF button (calls
  `callbacks.ToggleAuto()`), version string. `Panel.Init(callbacks)`, `Panel.Render(model)`.
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

## Post-review amendments (from the v1.19.4 pre-deploy adversarial pass)

> The index-base, signature, latch-watchdog and run-boundary items still describe
> the current adapter. The `DISABLE_SUPPRESSES_GUARANTEE` self-check item is
> **HISTORICAL**: that flag belongs to the obsolete guarantee model and changes
> no current decision. The undemote command still exists and only clears those
> legacy flag demotions.

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
- `Store` per-char `tomeTogglePending[lever] = { t = sentAt, want = bool }` (legacy
  bare-number entries read as `want=true`); `priorAutoAccept` survives version bumps.
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

> **HISTORICAL.** `tests/harness.lua` and `tests/run_integration.lua` are not the
> maintained suite. See "Tests" in the current contract.

`tests/harness.lua` (stub extensions per design §10) + `tests/run_integration.lua`
(scenario asserts). Run: `luajit tests/run_integration.lua` from the addon root; exits
non-zero on failure. A red suite blocks deploy.
