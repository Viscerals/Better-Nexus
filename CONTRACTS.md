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
  `state.flags` select no planner and change no decision. The historical
  scoring engine described in the `logic/Policy.lua` section below was
  unreachable (the production TOC always loads EchoWeaver) and has been
  removed from the file; without the planner, `Policy.Decide` answers a wait.
  `Model.Support` and the draw-distribution helpers (`BuildDistribution`,
  `EmaxK`, `EmaxGivenK`, `WithoutKey`, `FreeDist`) fed only that engine and
  now live in the test-only `tests/prototype/historical_model_support.lua`, which the
  policy adapter uses; `Model.Delta` stays in `logic/Model.lua`.
- **`EchoWeaver.Decide(input)`** is the pure ordinary planner. Without
  `input.policy` it follows the base strategy. `DecideNexus` passes `EchoWeaver.NEXUS_POLICY`, whose options
  are deliberate, documented differences (`docs/ROLLING_ORB_REVIEW_EADFF8A.md`).
  Exact `plan.requestedCounts` per spell ID, rolled plus permanent ownership,
  actual charges and the per-action permissions are its inputs. Actions:
  `take`, `freeze`, `banish`, `reroll`, `wait`. Action `index` is 1-based.
- **Optional leveling pick (`settings.autoPickLeveling`).** Off unless exactly
  `true` (absent is not a default; read-only roots adopt only a saved `true`).
  Set only by `/nexus leveling on|off` or its Automation settings row; it never
  turns Auto ON. It decides only where the planner waits with an advisor plan,
  no Wishlist, and `AssignedWishlist().knownUnassigned == true` (no Saved Build
  in use and no first-run plan, or a populated Saved Build with no association;
  every loading, restoring, unavailable, empty-slot or unknown state refuses).
  `Policy.DecideLevelingRarity` takes the highest `observedQuality` (exact
  integer 0..4 from `GameAdapter.Board`; any card without one refuses the whole
  board) at live level 2..79, first card on a tie. The intent uses the existing
  prepare/preauthorize/submit/settle lifecycle; preauthorization re-runs the
  selector on the fresh board and re-reads mode, `autoPick == true`, live level
  and the unassigned key, and `GameAdapter.Take(spellId, expect)` checks index,
  rarity and authority after its own board read. Ownership readiness: the
  mode decides only with `owned.synced == true` and preauthorization re-reads
  it; at submission `Take` needs a readable granted mirror for the exact
  pre-send count (nil, non-table or a throwing read is unknown, never zero) and
  `ownedConfirmedGeneration == ownedGeneration`. User-facing name: Random Roll
  (it picks by highest rarity, never at random; the key, command and policy ID
  are unchanged). Final admission (R5), callouts first in a fixed bounded
  order: `raw1` (the strict whole raw choice, exactly three tables with numeric
  integer spellId and quality 0..4, is the selector's actual input), the
  runtime verifier, owner identity, granted `g1`, a strict typed choice key
  `raw2 == raw1`, granted `g2` with the same signature as `g1` (the exact
  baseline), R6: a third strict choice key `raw3 == raw1` after `g2`, the Orb
  gate, live level 2..79; then memory-only checks: current
  `Perks` table with `pendingSelectSpellId == nil`, unchanged
  `wishlistProjectionRevision`, current-run generation, and `expect.final`
  (same prepared intent, master Auto, mode, `autoPick`, pause epoch, world and
  user holds); then the pause boundary; then R17 (C02): the last memory-only
  observation, phase `mirror`, immediately before the native Select: the strict
  typed key of the current `Perks.currentChoice` field (`rawget`, no metamethod,
  no callout; the field the provider publishes wholesale and that
  `GetCurrentChoice` returns by reference) must equal the admitted `raw1` key. A
  republished table with changed values, an in-place mutation, a cleared or
  malformed mirror refuses with `leveling_offer_changed`; a distinct
  value-identical republication passes (a value key, never an identity
  refusal). The decision-time board carries `strictObservation`; a filtered
  subset is refused. Any failure sends nothing. R6 settlement: right after a
  successful leveling Select, one granted read compares the spell's exact count
  with the captured baseline; an unreadable mirror or a different count marks
  the adapter's own record `competing`, so `ConfirmAwaitingGrant` holds it
  `ambiguous` (never proven, never replayed, cancelled or refunded).
  `GameAdapter.LevelingAdmissionPhase` is a memory-only diagnostic naming the
  current admission step. Trust boundary (BLOCKED, not
  claimed safe): the source has no atomic or memory-mirrored native
  observation, so a change made inside the last callouts (`g2`, Orb gate,
  level) to native Orb or level facts is not detected, and a change to the
  choice between the `mirror` read and the native Select is not detected
  either (no callout separates them in this source; Lua event preemption is
  neither asserted nor excluded). Loaded provider identity, archive precedence
  and server cadence are not established by this source. The
  missing contract is a precondition-carrying native Select or event-maintained
  revisions of those facts. Level 1 is idle (no tome
  setup); at 80 and above nothing new is decided and nothing is saved or
  searched, while a sent intent settles by the existing rules. No reroll,
  banish, freeze, Orb, tome, lock, activation, save or load is added. Offline
  evidence only; native offer origin and rarity range are not established.
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
  behind `GameAdapter.Orbs`. An unresolved command is never replayed or refunded.
  Within an approved session run, bounded recovery may retain an unresolved
  receipt in the archive and continue with a new attempt from actual ownership:
  at most two recovery checks per run, with every uncertain spend still counted
  toward the same approved maximum. It requires two qualifying quiet balance
  replies, refreshed ownership, and an exact empty-choice response observed after
  requesting the current choice, beside unchanged assignment, owner, loadout and
  locks and no active action. Own request framing must be passively observable;
  a framed-empty outgoing send invalidates that check. Automatic history leaves
  two entries and 12,288 bytes for explicit recovery under the existing archive
  caps. Observed build completion never fabricates per-operation attribution.
  The session-only quiet permission must remain valid through the next spend's
  final owner guard; newer uncertain choice evidence invalidates its empty fact.
  A newer admitted empty reply can restore that fact only with the other current
  guards unchanged. No added query or allowance reset follows the archive.
  Nil choice data alone is unknown; timers authorize
  no recovery. No result or owned Echo is inferred. Stop and Pause cancel further
  actions; loading preserves only existing session authorization. See
  `docs/ORB_BOUNDED_RECOVERY.md`. Recovery after logout/reload remains passive.
  The restored receipt's explicit exit is the player's
  explicit Continue (`docs/ORB_RECOVERY_CONTINUE.md`), for a spend this client
  observed (the one-Orb decrement seen with the offer; no server reply carries a
  spend identity, so Nexus never states it as server-confirmed; the saved
  receipt keeps its compatibility field `spendConfirmed`, and the passive
  `RecoveryView` reports `spendObserved`) with
  no usable recorded outcome and the original offer gone: it keeps the spent
  count, the limit and the configured maximum, archives the saved receipt
  unchanged in the character row key `orbRecoveryArchive`, sends no spend and no
  choice (only the read-only refresh requests that Recheck also sends) and is
  never automatic. An incoming passive observer of the game's own addon-message
  prefix feeds its strict check; it registers no opcode handler and sends
  nothing. The separate live check requests the current choice and observes
  outgoing sends with a secure post-hook. That hook may change the global
  function identity; the original transport implementation is still invoked.
- **Orb client admission.** `OrbAdapter.ClientAdmission()` decides whether Orb
  mode may act on the loaded game client. It is memory only (`rawget` on
  `ProjectEbonhold`, its `PerkService` and its `Perks`; no getter or callout)
  and returns `true`, or `false`, a reason text and a fixed code:
  - `updated_client`: `PerkService` holds a `GetServerActiveDesign` or a
    `WantsMoreOfEcho` member of any type. These are the two updated-provider
    markers that the ordinary path also reads.
  - `spec_draw`: neither marker is present, but `Perks.currentSpecDraw` is,
    with any value. The client keeps that field after the draw is answered,
    until its next Echo choice.
  - `unreadable`: `ProjectEbonhold`, `PerkService` or `Perks` is not a table.

  On a refusal Orb mode starts nothing, spends nothing and chooses nothing; the
  game's own Orb and choice windows are not touched. There is no positive
  exception: a visible memory card (flag 3) is not taken either, and three
  ordinary-looking cards are not proof that no memory card was offered. A
  client with neither marker and no specialization field is the older provider
  and keeps the Orb contract above.

  Where it is read: `OrbRuntime` preflight (so `Prepare`, `Start`, `Confirm` and
  the window's `canStart` / `startReason` give the same reason); `Confirm` once
  more immediately before ordinary Auto is switched off; `OrbAdapter.Acquire`
  and `Rebind`; `Resume` of a kept receipt whose three-card offer is open,
  before ordinary Auto is switched off; the runtime before a spend receipt is
  created and before a choice is decided; `OrbAdapter.Spend` immediately before
  `ConfirmSpend`; `OrbAdapter.Select` after validation and again immediately
  before `SelectPerk`. `Spend` and `Select` return `REJECTED` with the boundary
  status `CLIENT_CONTRACT`. A start refused by the preflight, or by `Confirm`'s
  check immediately before the switch, leaves ordinary Auto, the Orb ownership,
  the balance and every choice unchanged; a client that is already refused when
  the player starts is always refused there. One narrow race remains: the
  switch to Auto OFF and `Acquire`'s own fresh read run other code, so if the
  provider markers or the specialization field appear only after `Confirm`'s
  check, `OrbAdapter.Acquire` refuses after ordinary Auto has already been
  switched off. Auto then stays off until the player turns it on again; no
  ownership is taken, no receipt is created, and no Orb or choice is sent. A
  refused choice pauses
  the run and keeps the receipt and its counted spend with no selection attempt
  recorded; the player's own choice settles it through the existing result
  path. Recovery authority, budgets and the read-only recovery requests are
  unchanged and are not gated by this rule.

  Basis and limits. The rule rests on a static reading of one captured client:
  `perks_service.lua` (SHA-256
  `3303632eedb997f121b6ac5fa155bd6041b3f17190d71fb7c8b71dd670bd7c51`) and
  `orb_of_lost_memories.lua` (SHA-256
  `c08c0d096d8893a7969a974f63006a223e98179471ece9532cd3a6aad8930fe8`). A later
  extraction, made after the launcher changed two game archives, holds the same
  bytes for both. In that source every Echo choice, an Orb draw included,
  passes through one parser that marks a memory card, drops a fourth card
  before it publishes the choice and records a specialization draw, and the Orb
  service's pending value is a count of owed draws that does not identify the
  shown cards. Not established: whether the server ever sends a memory card, a
  specialization token or a four-card list in an Orb draw; the order in which
  the game loads its archives; any server behaviour. The older provider is
  recognized only by the absence of both markers and of the field, so a client
  that renames them would be read as the older provider. Offline evidence only;
  no native result. The three refusal texts are English and uncatalogued.
- **Souvenir stage (updated provider).** On the updated provider (either
  marker above) the ordinary path admits exactly one automatic choice action:
  a `GameAdapter.Take` of the memory card (flag 3, `isGuaranteed`) that the
  published choice shows. Every other Take, and every Reroll, Banish and
  Freeze, is refused there (`ChoiceAdmission`, `MutationAdmission`); the gate
  stays closed when no memory card is visible. `GameAdapter.Board()` sets
  `memoryStage = true` when that provider shows a flagged card, `nil`
  otherwise. Its absence proves nothing: a dropped fourth card can hide a
  souvenir, so no visible flag never opens the ordinary actions. On a
  `memoryStage` board (1 to 4 cards) `EchoWeaver.DecideNexus` does not wait
  for three cards. After its usual gates (Orb hold, plan, ownership sync,
  pending action, horizon, lock sync) it returns a `take` of the souvenir only
  when exactly one card is flagged, that card is selectable and its exact
  spell ID is still outstanding (rolled plus counted locked copies
  subtracted). An unneeded souvenir is given up for the three hidden Echoes
  (souvenir reveal, below) when the board is `revealable` and a Wishlist
  target is still missing. Otherwise it waits with the reason `souvenir: take
  it or draw three random Echoes; the choice is left to the player`: nothing
  missing, a souvenir whose Echo family still has a missing target or is not
  known, a souvenir the game's own build asks for, two flagged cards, or a
  carried card beside the souvenir (giving it up or taking another card
  gives the souvenir up). The game's own choice window is not touched. The Take keeps every existing
  send guard (pending native Select, in-flight action, session pause, the
  final memory-only admission before `SelectPerk`). The older provider is
  unchanged (`memoryStage` is nil; a one-card board still waits).
- **Souvenir reveal (updated provider; user requirement of 2026-11-17).**
  Nexus sends `REQUEST_PERK_MEMORY_DRAW` only through
  `GameAdapter.RevealMemory(spellId, expect)`, for an action `reveal` the
  planner decides as above. It is a sacrifice, not a reroll: the souvenir is
  lost for the climb. `Board()` marks a lone souvenir (exactly one published
  card, flagged) `revealable` only when the request would not be refused at
  once (`RevealSnapshot`: no Select, Reroll, Orb redraw, Banish or Freeze
  pending, no specialization draw, `CS.REQUEST_PERK_MEMORY_DRAW == 349` and a
  `sendToServer` function) and the game's `WantsMoreOfEcho(souvenir)` returns
  no true value (a missing or thrown read refuses); `revealSent` when this draw was already given up.
  `RevealMemory` sends nothing unless all of these hold again: the updated
  provider, the ordinary gate (specialization, Orb), no session pause or
  passive mode, nothing in flight and no reveal waiting, the lone souvenir
  unchanged, `WantsMoreOfEcho` not true, the owned total readable, and this draw
  (souvenir, pending draw count, owned total) not already given up. Then the
  runtime's `verify` decides again on fresh reads (the Wishlist plan probed
  again, board, rolled and locked ownership, level, horizon) and must again
  return this reveal; a changed decision supersedes the intent and a fresh
  decision follows. After it, memory only: the runtime's `final` (master Auto,
  `autoPick == true`, this prepared intent, no pause, world hold or player
  action), the pause epoch, nothing in flight, the same `Perks` table and the
  same souvenir table, the same pending draw count. The request is
  `sendToServer(349, "")`, once per draw for the session: the draw is marked
  given up before the send, so a refused, failed or unanswered request is
  never repeated. The reveal is in flight (`InFlight`) until a new choice or
  `REVEAL_WINDOW` (10 s); the runtime intent stays on that board and is never
  resent; the board then waits with `souvenir given up; waiting for the three
  revealed Echoes`.
  The first new choice is bound to the reveal (`revealBound`) only when it
  arrives within the window, shows exactly three unflagged Echoes with valid
  IDs, no Select or specialization draw is pending, and the pending draw count
  and the owned total equal those of the request. Any other new choice ends
  the reveal unbound, and the ordinary updated-provider admission applies
  (nothing is chosen). On a bound board `ChoiceAdmission` admits a Take of one
  of its three Echoes (entry and send boundary); Reroll, Banish and Freeze
  stay refused, and the planner decides with no search (`canBanish`,
  `canFreeze`, `canReroll` false): a needed Echo, else a filler.
  The game's own auto-accept timer (`perks_service.lua`) is armed at a choice
  parse with the card it chose, fires on the first frame after 0.18 s through
  `Perks.SelectPerk` (refused only when a pick is pending or the card is not
  on the current choice) and re-checks neither its option nor the Wishlist,
  so switching the option off, as the existing Auto gate and solo-picker
  lease do, does not cancel an armed timer. Nexus therefore reveals, and takes
  from a revealed board, only after it has observed that exact choice table
  for `CHOICE_SETTLE` (1 s; first observation is never before the parse):
  `Board()` marks a younger one `revealSettling`, the planner waits with
  `waiting for the game's own pick window to pass` and the runtime decides
  again at the poll pace; `RevealMemory` (`reveal_not_settled`, superseded
  and decided again) and the revealed-board `ChoiceAdmission` refuse it at
  the send boundary. An armed timer has fired by then: its Select is pending
  (every send boundary refuses) or it was refused. The bound is frame-time
  based: a single frame spanning the whole settle time is not excluded, and
  then only the pending-Select checks at the send boundaries separate the two
  picks.
  Basis and limits: static reading of the captured `perks.lua` (above;
  `RequestMemoryDraw`, `PlayMemoryGiveUp`) and `projectebonhold.lua`
  (`REQUEST_PERK_MEMORY_DRAW = 349`); no reply opcode, request ID or refusal
  exists there, so the reply is inferred to be the next published choice
  (`SEND_PLAYER_PERK_CHOICE`). The game's window is not told: it keeps
  showing the souvenir until that reply, and a player click there in that
  window is not excluded. A reload forgets the session's given-up draws. Not
  established: the server's reply, refusal or timing, whether the reply can
  carry carried cards or a fourth card, and the native window's state after a
  reveal it did not start. Offline evidence only
  (`tests/prototype/automation_souvenir_reveal.lua`, including a model of the
  timer from the captured source); no native result. The new reasons are
  English and uncatalogued.

  Basis and limits. A static reading of one captured client: `perks.lua`
  (SHA-256 `43e28daef02a1f95d344eaca880bde2ce1794a0e821113837c5bfc5d5b98b8a2`,
  the "Memory stage" comment and `LayoutMemoryStage`) and `perks_service.lua`
  (the SHA-256 above: flag 3 parsing, the dropped fourth card). The wow.export
  version of this extraction is not recorded, and whether this `perks.lua`
  predates the launcher's archive change is not established. Not established:
  the server's wire order of the souvenir, whether it can be the dropped
  fourth card, and the native timing of the client's own automatic pick.
  Offline evidence only (`tests/prototype/automation_souvenir_stage.lua`); no
  native result. The wait reason is English and uncatalogued (language work
  deferred). Live user diagnostic on test.9097-a8c00d3a (summary supplied by
  the coordinator): two own Takes of needed souvenirs were proven granted, and
  an unneeded souvenir waited; this is native evidence for the Take and the
  hand-off of that build only.
- **Auto Save, unavailable client.** `GameAdapter.Save` returns
  `false, "save_unavailable"` when the `PerkService` table is present and has no
  `SaveServerBuildSlot` member. Nothing is called, sent or timed for it. The
  captured `perks_service.lua` named above exports no such member. The reason is
  distinct from `"refused"` (the member exists and declined or failed, or no
  service table is loaded) and from `"spacing"`. On `save_unavailable` the
  automation sets one status, prints one notice and makes no further save
  attempt for that level-80 visit: the memory-only flag
  `save.unavailableVisit` is cleared when the level leaves 80 and at a run
  boundary, never saved, and is not a success (`savedThisVisit`, the
  verification fields and `lastSaveStatus` are not touched). An ordinary
  refusal keeps its earlier handling. Whether the updated client offers a
  manual save is not established. Offline evidence only.
- **Attribution-only explicit exit.** A stopped receipt, restored or from the
  current session, may use that same checked Continue path when a fresh exact
  distinct chosen gain is actually owned and attribution alone prevents
  confirmation. The flag alone is insufficient. Original loadout, owner, locks,
  current binding and quiet native state are rechecked through the actual atomic
  save. It archives the unchanged receipt as `ACK_UNCONFIRMED`, confidence `NONE`,
  keeps observed spend and unknown exposure separately without refund or double
  charge, ends the old run and only then releases ordinary rolling. It sends no
  spend, selection or automatic Resume, and consumes no fresh live allowance.
  Completion from actual ownership and exhaustion of two live checks do not
  remove this finite explicit exit. Archive/save refusal keeps receipt and gate.
- **Recovery authority.** Retained completed states survive lifecycle holds and
  cannot reopen limit approval. Eligible held receipts have the explicit checked
  Continue exit; an ineligible entry preserves the automatic owner. Equivalent
  current owed-offer orders share the strict one-choice Resume guards. A revoked
  post-archive permit stays revoked; unknown reads retain unclassified evidence.
  Only classified fresh choice evidence updates that fact. Host-false consumes
  the one-use permit, whereas pre-host refusal does not. Budget/resource terminals
  precede permit waits. Optional capability absence is explicit, and a real
  outgoing-hook attempt is latched once per adapter lifetime, including failure.
- **Retained attribution.** The current character's bounded unconfirmed archive
  supplies source/pair uncertainty across approvals and passive reloads. Own and
  observed choices apply it before saving. A late snapshot explained by retained
  attempts may hold attribution, including a compound delta with the current
  result; it never confirms an operation. Unrelated deltas remain blocked.
- **Downgrades.** New receipts carrying attribution risk or unknown exposure use
  `attributionFormat=1` and retain their real GUID in `attributionOwner`, with
  legacy `guid` absent. The original loadout and other observations are unchanged.
  Read-only source inspection of public `a43cf27` Runtime+Adapter shows that it
  cannot interpret that owner identity: its existing owner guard retains the
  pending receipt and ordinary-action blocker, and refuses its no-choice Continue.
  That exact pair was not executed; archive-key retention tests establish a
  separate data-preservation boundary. The current owner validates and reads the
  versioned identity. Unknown/conflicting versions fail closed. This is a local
  receipt representation, with no global Store migration or fabricated facts.
  Archive byte retention alone is a separate, weaker compatibility claim.
- **Passive readiness diagnostics.** `GameAdapter.OwnershipTrustView()` and
  `OrbRuntime.ReadinessView()` return a new table of scalars and fixed codes.
  The first holds the current generation facts and, separately, what the last
  normal `Owned()` and `LockedOwned()` evaluations sampled (each with its own
  time). The second holds what the last Orb window read (`OrbRuntime.Status`)
  observed. Only those normal reads record them, in memory. The accessors read
  no game state and send, save or change nothing. `OrbAdapter.Read()` may
  return a third value, the stage code of its refusal, for that observation
  only. No decision, gate or count reads any of this. The support report shows
  it as bounded `key=value` blocks with ages. An age is the time of a read, not
  proof of a fresh server response. A locked rejection code labels the evidence
  and does not mean that an Echo was removed. One exception concerns wording
  only: at the trust gate with rolled ownership trusted (stage `trust_locked`),
  `OrbAdapter.Read()` compares the `diagnosticSerial` of the
  `GameAdapter.LockedOwned()` read it just made (a diagnostics-only scalar:
  that read's serial) with `OwnershipTrustView().lockedSerial`. Only when they
  are equal and that sample's `lockedRejection` is `over_cap` does the refusal
  text say that Nexus rejected the locked Echo data: it names the occupied
  records and the live capacity of that same read when it lists more records
  than the capacity, or says a locked record is above the limit Nexus
  supports. A missing serial and a stale, mismatched, failing or unreadable
  sample keep the shared wait text. The refusal, its stage and every gate are
  the same either way; nothing is read from the game, requested or saved for
  the text.
- **Choice and runner diagnostics.** `GameAdapter.ChoicePresenceView()`,
  `OrbAdapter.ServiceStateView()` and `OrbRuntime.RunnerView()` expose separate
  memory-only observations. Existing `Board()` and Orb adapter reads sample
  `GetCurrentChoice` without adding a native call. A checked nonempty dense
  choice is present; an explicit checked empty table is absent; nil, failure,
  unavailable or malformed data is unknown. Samples older than one client
  second, invalidated by a loading/logout transition, or without a usable
  clock cannot assert current presence or absence. Historical sample facts
  remain labelled separately. The existing Main event dispatcher updates only
  diagnostic world context, including before an Orb recovery frame exists.
  An Orb runner being IDLE or STOPPED does not settle an ordinary Echo choice.
  Uninitialized runner/receipt state is unknown; these passive facts never
  initialize it. The separate legacy recovery section retains early saved
  receipt restoration; empty uninitialized reports skip Continue/history
  constructors. None of this authorizes recovery or
  changes gameplay, ownership, saved data or retry policy. See
  `docs/CHOICE_DIAGNOSTICS.md` for sampling and coverage limits.
- **Occupied locked records.** The client mirrors each SS18 entry flagged
  locked as one record with its own locked stack; granted copies of the same
  spell can be held beside it. The native journal's client-side lock gate
  compares the record count (not copies) with `GetMaximumPermanentEchoes`,
  which keeps its last positive value. Not established: one record per spell,
  every held copy in that record, or server enforcement of the record bound.
  Nexus treats record partitions and a spell held in both roles as data.
  `GameAdapter.LockedOwned()` counts each table with a recognized ID as one
  occupied record and returns `occupied`, `records` (one `{spellId, stacks}`
  per record) and the `capacity` it was held to, beside the exact `bySpell`
  copies (never clamped). It trusts the records when they are structurally
  valid and no more than the live capacity, or, while the capacity is unknown,
  no more than the record ceiling (256; the capacity then stays unavailable to
  actions, `MaxPermanentEchoes()` is nil). A record above the 120-copy row
  ceiling is `over_cap`. A record's own `maxStack` bounds nothing: the native
  SS18 parser stores `stack` and `maxStack` independently, and whether the
  server holds one to the other (or retunes it) is unknown. A retained positive
  capacity is used as stated; its freshness is not observable and is not
  claimed. The Echo snapshot's locked field includes the record partition and
  the capacity, so equal per-spell copies in another partition are a change.
  `Model.LockedProjection` admits only a read that states its occupancy, and
  AutoLock counts records: one lock occupies one record, whatever its copies,
  and a spell that is already locked is never locked again for more copies
  (LockPerk sends the spellId only). Elsewhere three different bounds apply,
  and none is a guessed capacity:
  - Resource ceilings: durable evidence, the catalog, DPS records and a stated
    `lv = 1` locked set carry no capacity and normalize rows, so they hold the
    locked role to `LoadoutEvidence.SemanticLimits` (256 locked rows, 120
    copies in one row, 10000 copies in all, beside 79 ordinary copies).
  - The DPS wire, unchanged and narrower: each received DPS Echo list,
    ordinary or locked, holds at most 120 entries and 120 copies in all
    (`DpsCapture` `ValidWireEchoList`).
  - The authored plan envelope, 79 ordinary and six locked target copies (85
    in all): the Wishlist design (`WishlistModel`), a Share
    (`LoadoutEvidence.PlanLimits`) and an EBH1 code (`Codec`).
  The peer wire format is unchanged; released (test.9049) peers keep their 79 /
  6 / 85 envelope, refuse inline slot-4 locked copies above six and ignore a
  stated `lv = 1` set, and new responders send a stated set only to
  `lv1`-capable requesters. A trusted representation is not a claim that the
  server accepts a given loadout.
- **Wishlist editor locked targets.** The editor holds a new locked target to
  two separate rules (`WishlistModel` `LockBudgetRefusal`). Design: the plan's
  own target copies -- its designed rows (a tagged row one copy, a queued
  target its copies), the new target and, once each, the fulfilled targets the
  final design keeps -- stay within the authored six. Slots: the trusted
  projection's occupied records, plus one record for each designed spell that
  holds none, stay within the live capacity, or within six while the capacity
  is unknown. A replacement frees the replaced spell's records and drops its
  fulfilled target from the design, as `PlanLockCommit` and the draft export
  do; current locked Echoes the plan does not target are occupancy, never
  design. Each refusal names its rule. A plan without locked targets carries
  the current locked Echoes as the locked rows of its EBH1 code only while
  their copies fit six; otherwise the code holds the ordinary plan and the
  export says that the locks are left out. A code the codec would empty
  (outside 79 / 6 / 85, or no Echo at all) is refused with its reason and never
  shown. Neither rule claims what the server accepts. The design rule also
  bounds whole plans (`DesignCopies`): a Copy whose locked rows hold more than
  six copies is refused before it replaces the draft, and Save refuses a draft
  whose own final design holds more than six copies before any confirmation or
  upload and keeps no retry; occupied records, the live capacity and maxStack
  do not enter it.
- **Equal rolled contents, several retained designs.** A server mirror carries
  ordinary rows only, so a plan without its own design reads the content-key
  bucket (`lockDesignTargetsBySlot[key]`) only while the retained designs of
  those contents agree (`WishlistRoles.DesignAmbiguous`: the bucket, every
  stored assignment, the first-run plan and the removal history, compared by
  canonical target token; a legacy empty bucket `{}` from before W4 is a
  zero-target design and counts). When the bucket exists and two of them
  differ, none is chosen: `AssignedWishlist` reads `unavailable` with a note,
  AutoLock reads no targets, and the Wishlist Editor fills in no locked target
  and says so (a save then keeps only the targets set there). An explicit
  picker selection of a plain row carries a design only through
  `WishlistRoles.SelectedDesign`: the clicked row is still the row the picker
  showed, exactly one retained design is attributable to its name and
  contents, `ResolveSaved` puts that plan on exactly the clicked row, and the
  bucket's design (an empty legacy bucket included) is that design or the
  design of a valid plan of another name; a design that only the bucket holds
  is never carried. Moved-identity, missing-mirror and slot-number-only
  selections borrow nothing and stay unavailable. Upgrade: such a design-less
  assignment read `ready` with the bucket in earlier builds (also when the
  bucket was its own design) and reads `unavailable` now, until it is
  reassigned, restored or given targets; no profile, provenance or schema is
  migrated. Residual limit, present since this rule was added (f53f5ed): the
  removal history keeps five records, so once a differing design has left all
  retained data the plain plan reads the bucket again. Removing that needs
  durable per-plan design provenance, a saved-format change that is not made.
- **Locked shape capture.** `GameAdapter.LockedShapeView()` returns a new table
  for the last normal `LockedOwned()` read that refused a table, or
  `observed=false` since load. Protected hooks inside that read's own parse
  record it (`ReadLockedPerks(raw, sink)`; `LockedFingerprint` passes no
  collector): no second walk, no second getter call, memory only. A failing
  hook ends the capture as `status=failed` and never changes the parse. The
  header holds `serial` (the existing `projectionStatus.locked.calls` of that
  read), `at`, `age`, `sampledGeneration`, `currentGeneration`, `first`,
  `copies`, `ids` (that read's `bySpell` keys), `status` (`captured`,
  `truncated` past 64 tables, `failed`) and `rows`. `current` and `laterReads`
  compare `serial` with `OwnershipTrustView().lockedSerial`, which the Orb
  observation copies as `lockedSerial` (its report block prints
  `locked.serial`). Each row, at most 64 in pre-order, holds
  seven integers or fixed codes: parent row `p`, key class `k`, anonymous ID
  class `c`, copies added `n`, the ID and count alias bits the parser read
  (`im`, `cm`) and defect bits `e`. No key, ID, name, value or table reference
  is kept. The prepared file report shows it as the bounded `Locked shape`
  block; the copied summary does not. A repeated ID class, a count or a nesting
  is structure, not a native meaning; a later read or a newer generation is
  context, not proof of a change. No decision, gate or count reads any of this.
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

> The index-base item still describes the current adapter. The signature,
> latch-watchdog and run-boundary items below are amended for the adapter's own
> ordinary Select (its tracking until an exact grant). The
> `DISABLE_SUPPRESSES_GUARANTEE` self-check item is **HISTORICAL**: that flag
> belongs to the obsolete guarantee model and changes no current decision. The
> undemote command still exists and only clears those legacy flag demotions.

- **Index bases:** `Policy` `action.index` is **1-based** into `board.cards`;
  `GameAdapter.Banish(index0)` takes the client's **0-based** perk index. `Main`
  converts at the seam (`action.index - 1`).
- `board` additionally carries `idSignature` (spellIds only, comma-joined). When
  the client's flag for the adapter's own Select clears, the adapter records,
  like-for-like by `idSignature`, whether the board stayed the same, moved on or
  went away. That is a diagnostic fact only: no board outcome is that Select's
  result (no supported signal says refused or granted). The Select stays in
  flight, never owned, until its exact grant: that spell's granted count above
  the pre-send count, in the same run, with a readable `Perks` table showing no
  Select flag and no outside Select of that spell seen (any such Select makes
  every later rise ambiguous). Otherwise it waits until a run boundary voids it,
  or a `/reload` drops the tracking with the result unknown. The game gives no
  receipt for a selection, so this wait can last the run. Auto off and on does
  not end it.
- **`Ratchet.Dominates` filler axis is COUNT-based**, not set-subset: every board
  forces a take, so per-run filler sets always differ and subset never holds; the
  spec's own potential Φ = coverage − ρ·fillerCount is count-based. Coverage stays
  set-superset. Advisor mode (no wishlist) NEVER saves.
- `Store` per-char `tomeTogglePending[lever] = { t = sentAt, want = bool }` (legacy
  bare-number entries read as `want=true`); `priorAutoAccept` survives version bumps.
- `GameAdapter.DisabledLevers()` values are `"confirmed"` (server mirror) or
  `"pending"` (our unconfirmed request) — both truthy for pool math; only
  `"confirmed"` may drive the DISABLE_SUPPRESSES_GUARANTEE self-check demotion.
- Per-latch watchdog: a client `pending*` latch stuck >10s is declared dead
  (per-action, mirroring the client's own failure mode), excluded from the
  whole-loop gate, its charges zeroed, status surfaced; recovers if the latch clears.
  Exceptions: the adapter's own unresolved Select is not released (an expired
  watchdog is not its result; it keeps its provenance). A dead Select flag is still
  a set flag: `A.Take` admits a Select only when a readable `Perks` table shows
  `pendingSelectSpellId == nil`, checked before the client is called (as a dead
  Freeze flag keeps Freeze closed). Nothing writes a client field.
- Run boundary (`A.RunBoundaryReset`, called once this session has seen level 80
  and then a live lower level): recorded picks void; owned-sync trust suspended
  until the client-reported owned set CHANGES from its at-reset snapshot (dead-run
  ghost protection). The own unresolved Select is voided (its result unknown, never
  proven). If a Select flag is still set then, or `Perks` cannot be read, the
  in-flight marker is re-armed and holds every Echo action (Take, Banish, Freeze,
  Reroll, Orb actions) until a readable table shows no flag. That flag is a
  selection pending, not proof that the voided Select is the one pending.
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
