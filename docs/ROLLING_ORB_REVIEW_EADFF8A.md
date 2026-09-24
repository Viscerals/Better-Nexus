# Rolling and Orb corrections after the review of main `eadff8a`

Baseline: `eadff8abfe2ef4c732fc23afe18a3eb6c4f98302`, tree
`a54eb169ea01c310c86139788d3669d678f89c47`.

All tests named here are new synthetic offline tests written from the review
report's stated scenarios. The review's original probes were not available.
The tests use the real Nexus modules with mocked game services. They prove no
native client behaviour.

## R1 - Unknown Orb state and the ordinary-action gate

### Demonstrated cause

`GameAdapter.OrdinaryBoardAllowed()` read `OrbService.IsOfferPending()` only.
It did not read `OrbService.IsStateKnown()`. With a service that reported
"state not known" and "no offer pending", the gate returned true. The real
`GameAdapter.Take` then called `PerkService.SelectPerk`. Automatic rolling
submitted a Freeze in the same state.

### Current contract

`OrbAdapter.ServiceState()` is the one owner of the OrbService known/pending
classification for callers outside Orb mode. `OrdinaryBoardAllowed()` uses it.

| Capability case | Condition | Ordinary mutation |
|---|---|---|
| `NO_ORB_SERVICE` | There is no `ProjectEbonhold` table, or its `OrbService` is nil | Allowed. The only explicit legacy capability. |
| `MISSING_STATE` | An `OrbService` exists, `IsOfferPending` is a function, and no `IsStateKnown` member exists | Blocked: `orb state capability missing`. The service cannot say whether its pending answer is authoritative. |
| `STATE_AWARE` | `IsStateKnown` and `IsOfferPending` are functions | Allowed only when `IsStateKnown()` returns boolean true and `IsOfferPending()` returns boolean false. |
| `MALFORMED` | OrbService is not a table, `IsOfferPending` is not a function, `IsStateKnown` exists and is not a function, or reading the service or a member throws | Blocked: `orb state unavailable`. |

| State answer | Reason code | Visible text |
|---|---|---|
| `IsStateKnown()` returns false | `orb state not yet known` | Ordinary rolling paused: the server's Orb state is not confirmed yet |
| A callback throws or returns a non-boolean | `orb state unknown` | Ordinary rolling paused: the game's Orb state could not be read |
| Missing or malformed capability | `orb state unavailable` | Ordinary rolling paused: the game's Orb service does not expose its pending-offer state |
| `IsOfferPending()` returns true | `Orb offer active -- manual action required` | An Orb offer is active; use Orb mode or resolve it in the game |

Unknown state wins over the pending answer. A service that does not know its
state cannot vouch for its pending flag.

### Mutators and gate coverage

| Mutator | Game call | Guard |
|---|---|---|
| `GameAdapter.Take` | `PerkService.SelectPerk` | `OrdinaryBoardAllowed()` |
| `GameAdapter.Banish` | `PerkService.BanishPerk` | `OrdinaryBoardAllowed()` |
| `GameAdapter.Reroll` | `PerkService.RequestReroll` | `OrdinaryBoardAllowed()` |
| `GameAdapter.Freeze` | `PerkService.FreezePerk` | `OrdinaryBoardAllowed()` |
| Automatic rolling (`AutomationRuntime` `AutoAllowed`, and the policy state field `ordinaryBoardAllowed`) | the four calls above | `OrdinaryBoardAllowed()` |
| `GameAdapter.Activate`, `Save`, `UploadWishlist`, `LockPerk`, `UnlockPerk` | build-slot and permanent-slot calls | `OrbRuntime.BlocksOrdinary()` only. Not changed by R1. |
| `GameAdapter.ToggleLever` | `PerkService.ToggleTomeEcho` | No Orb guard. Not changed by R1. |

The second and third groups do not act on the three-card board. R1 did not
extend the Orb-state gate to them. The `BlocksOrdinary()` guard on the second
group still holds while an Orb operation is unresolved.

### Re-evaluation when the gate changes (review finding F1)

The game sends no event when the Orb state changes from unknown to known. The
automation loop is change-driven, so it did not evaluate again on an unchanged
board, and the status text stayed stale. `core/AutomationRuntime.lua` now
compares one scalar gate key (allowed, or blocked with its reason) at each
existing 0.2 s poll. A change requests one coalesced decision evaluation, the
same bounded trigger that an automation toggle uses. It invalidates no static
state and submits nothing itself. Test:
`tests/prototype/rolling_review_orb_state_recompute.lua`.

### Correction of 2026-09-21: no permit for a service without `IsStateKnown`

Until 2026-09-21 a service with `IsOfferPending` and no `IsStateKnown` member
permitted ordinary rolling as the named `PENDING_ONLY` case, because the older
test `tests/prototype/automation.lua` asserted it with a minimal mock. The user
ruled that this contradicts R1: an existing OrbService must give an
authoritative known-not-pending answer, and only a genuinely absent OrbService
is the legacy exception. The case is now `MISSING_STATE` and blocks. The two
mocks in `tests/prototype/automation.lua` were updated to what they stand for, a
client that reports a known state (`IsStateKnown` returns true); none of its
assertions changed. A throwing read of `ProjectEbonhold.OrbService` or of a
member is now classified `MALFORMED` (blocked) instead of raising an error at
the gate. (A table whose member lookup throws only on a later read can still
raise an error out of `Take`; no mutation is sent in that case.)

Tests: `tests/prototype/rolling_review_unknown_orb_state.lua` (the real
`Take`, `Banish`, `Reroll`, `Freeze` and automatic rolling; red on `90b8e58`),
`tests/prototype/rolling_review_automatic_paths_orb_state.lua` (automatic lever
and save paths).

## R2 - Passive recovery after reload

### Demonstrated cause

A restored receipt went directly to `finishResult`. It never collected offer or
selection observations. The read-only `SelectPerk` observer was installed only
by `OrbAdapter.Acquire`, and a reload does not restore that owner. The visible
instruction was "Resolve the native offer, then Recheck". On the baseline, a
checkpoint with the observed offer, then a manual choice, the exact result and
four Rechecks stayed unresolved. The instruction promised more than the code
could observe.

### What changed

| Part | Change |
|---|---|
| `OrbAdapter.Watch(snapshot)` / `Unwatch()` | Passive watcher. It installs the same read-only `SelectPerk` observer that the action owner uses. It sets no owner, so `Spend`, `Select` and `Rebind` stay unavailable. |
| `OrbRuntime` restore | The read-only recovery pump starts when the receipt is restored. It reads at 0.2 s while an offer is open and for 60 s after restore or Recheck, then every 5 s. |
| `OrbRuntime` `recoverObserve` | Records the offer and a manual choice for a restored receipt, through the existing `observeLifecycle`. |
| Settlement | Unchanged owner: `finishResult`. All B2 requirements stay: the offer, a choice sent or observed within that offer, one Orb, closed offer and host state, the exact ownership delta, a fresh ownership response, unchanged permanent Echoes, the original loadout. |
| Text | The recovery reason is derived from the current observation on each passive pump. `Status().recovery = {kind, observing}` reports the same classification. |

An open offer is tied to the saved action only when all of these hold: the Orb
balance is exactly one less than the receipt, rolled ownership equals the
receipt with or without the named source, permanent Echoes are unchanged, the
loadout is the original one, and, for an offer first seen after the reload, no
host action is in flight and no selection was recorded. A recorded offer must
also have the same offer identity. An offer first seen after the reload is
marked `offerSeenAfterReload` in the receipt. This is the same evidence the live
path uses for its first offer observation, checked more strictly.

The watcher is bound to the original loadout only. A choice observed on an
unmatched offer, or on another loadout, is discarded and is never evidence for
the saved action. A choice recorded on the matched offer is still consumed when
that offer closes between two recovery reads.

| Recovery kind | Meaning | Text tells the player |
|---|---|---|
| `OFFER_OPEN`, observing | The matching offer is open | Choose in the game's offer window. Nexus records the choice and will not choose or spend. |
| `OFFER_OPEN`, not observing | No `hooksecurefunc` observer | A manual choice cannot be observed; the action cannot be confirmed afterwards; the record is kept. |
| `OFFER_UNMATCHED` | An open offer does not match the receipt | Nexus cannot confirm the earlier action from this offer; the record is kept. |
| `WAIT_RESULT` | A choice is recorded | Waiting for the exact fresh ownership response; Recheck requests one. |
| `OFFER_OPEN` with `proposed` | A proposed key was refused before `SelectPerk` | Only a choice of that same Echo can be confirmed; a different choice cannot; the record is kept; no exit exists yet. |
| `WAIT_OFFER`, observing | No offer, state still equals the receipt | If a matching offer opens, a choice is recorded at the moment it is made, unless another game action is in flight at that moment: then it is not recorded (intended fail-closed result); Nexus cannot tell whether the spend was refused; the record is kept. |
| `WAIT_OFFER`, not observing | Same, without the observer | The action cannot be confirmed if its offer opens later; no exit exists yet. |
| `UNOBSERVABLE` | The action ended while unobserved | Nexus cannot confirm it; Recheck cannot settle it; record, exposure and blocks are kept; nothing is retried, refunded or deleted. |

Recovery never spends, never selects, never retries, never refunds allowance,
never erases the receipt, and never accepts an ownership delta alone.

### Corrections after the independent review of `eadff8a..578c77e`

| Finding | Correction |
|---|---|
| F3: exact result ownership can arrive while the game still flags the offer as pending. The read classified `OFFER_UNMATCHED` and discarded an observed choice. | A choice that the observer recorded on the offer this session already matched is consumed first, as the live path does. It needs the same offer identity, the one-Orb balance, and ownership that is the receipt or its exact single gain. Recorded choice evidence is never discarded by a later classification. Inexact ownership is still discarded. `finishResult` is unchanged. |
| F4: after 60 s the pump reads every 5 s. An offer that opened and was answered between two slow reads was never matched. | Chosen option: event-driven observation. The read-only `SelectPerk` observer notifies the passive watcher at the moment of a manual choice. One passive pump then records the offer and the choice with the same exact-evidence rules as a timed read, and reopens the 60 s fast window. An offer first seen at that moment is adopted only when the observed choice is the single host action in flight. The timed reads stay as they were. The `WAIT_OFFER` text now says that the choice is recorded at the moment it is made, and has a separate text when the client cannot observe choices. |
| F7: with a proposed key that was refused before `SelectPerk`, the text invited any manual choice. | The kind stays `OFFER_OPEN`; `Status().recovery.proposed` is true. The text names the proposed Echo and says that only that same Echo can be confirmed. After a different choice the pause text says that Nexus cannot confirm the action, that the record is kept, and that no exit exists yet. The rule itself is unchanged. |
| N2: blocked reasons said "owns the current action" and "Stop and settle". | `OrbRuntime.BlockReason(subject)` owns the reason. `GameAdapter.OrdinaryBoardAllowed` and the five build-slot and permanent-slot mutators use it. For a restored receipt it says either that Nexus only observes and the block ends when the action is confirmed, or that the action cannot be confirmed, that Nexus has no way to clear the block yet, and that the settlement path is only a proposal and is not built. The refusals of `Prepare`, `UseAssignedWishlist` and `SuggestSources` use the same text. No block changed. |

Not covered, because `core/Main.lua` is outside this branch's ownership: its
chat line "Stop and settle that operation first." for `/nexus auto` while Orb
mode blocks.

Tests: `orb_review_reload_early_ownership`,
`orb_review_reload_early_ownership_inexact`, `orb_review_reload_slow_cadence`,
`orb_review_reload_choice_event_guards`, `orb_review_reload_truthful_blocks`.

Second review of `578c77e..08a3caa` (G1, G4): the event-driven tests counted
accepted `take` actions only, and the mock refuses a second `SelectPerk` while
the player's select is pending, so a selection issued by the event path was
invisible. `orb_review_reload_slow_cadence`, `orb_review_reload_manual_choice`,
`orb_review_reload_early_ownership` and `orb_review_reload_choice_event_guards`
now wrap the mocked `SelectPerk` and `ConfirmSpend` entry points after the
reload and count every call, refused calls included: total `SelectPerk` calls
equal the scripted player calls, and `ConfirmSpend` calls are 0. Two more
tests pin rules that no test pinned: `orb_review_reload_refused_first_choice`
(an observation on an unadopted offer with another host action in flight is
discarded) and `orb_review_reload_balance_guard` (a choice at a wrong Orb
balance is never recorded, also on an offer that was matched before).

### Not changed

- The live-path rule that a manual choice different from a recorded proposed
  key pauses the operation. This also applies after a reload. Only its text
  changed (F7).
- `UNOBSERVABLE` receipts still block new Orb runs and ordinary rolling
  indefinitely. No exit exists. See the proposal below.

### Proposal only, not implemented: acknowledged settlement of unobservable history

Goal: let a player leave the permanent block of an `UNOBSERVABLE` receipt
without any fabricated confirmation.

1. Eligibility: recovery kind `UNOBSERVABLE` only, continuously for a minimum
   time, with a successful fresh read: known Orb state, no Orb offer, no board,
   no host action, nothing in flight, original character.
2. Action: an explicit panel control with a typed or two-step acknowledgement.
   The text states that Nexus did not confirm the action and that the Orb is
   counted as spent.
3. Effect: the receipt moves, unchanged, to a bounded per-character
   `orbRefinement.unresolvedHistory` list with outcome `ACKNOWLEDGED_UNCONFIRMED`
   and the snapshot keys seen at acknowledgement. It is never recorded as a
   confirmed replacement and never enters `recent`.
4. Accounting: the exposure counts as one spent Orb of the old run. The old run
   ends as `STOPPED`. No allowance returns. No Resume.
5. After it: a new Orb run needs the normal new review. Ordinary rolling resumes
   only through the normal gate (`OrdinaryBoardAllowed`), which verifies the
   current native Orb state first.
6. Never: a retry of the original spend, a selection, an automatic trigger, or
   use for receipts whose offer is open or whose choice evidence exists.

This needs a user decision because it changes what a permanent block means.
It also needs a panel control in `ui/OrbPanel.lua` and a Store field.

Tests: `orb_review_reload_unobservable`, `orb_review_reload_manual_choice`,
`orb_review_reload_offer_after_reload`, `orb_review_reload_offer_mismatch`,
`orb_review_reload_no_observer`, `orb_review_reload_rejected_selection`,
`orb_review_reload_other_loadout`, `orb_review_reload_choice_between_reads`.

## R3 - Reroll: outstanding need versus original Wishlist membership

Status: deliberate policy difference from the named reference strategy
(LoadoutPilot 1.3.6 / patch 103). It is a proposed strategy change, not a
correction of a proven bug. It is one separate commit. `git revert` of that commit is NOT a supported way to
switch it off: on the current branch it conflicts (this document, the test
runner, and for R3 also `logic/EchoWeaver.lua`), and the R5 code uses the
`local policy` that the R3 commit added. The supported way is the flag: set
`rerollIgnoresSatisfiedTargets = false` in `EchoWeaver.NEXUS_POLICY`. That flag alone
restores the reference decision and leaves the other change active
(`tests/prototype/rolling_review_policy_flags.lua`).

Reference rule: a permitted Reroll is skipped when any Echo of the original
Wishlist is on the board, also when its exact count is already met.

Nexus rule (option `rerollIgnoresSatisfiedTargets` in
`EchoWeaver.NEXUS_POLICY`, passed by `DecideNexus`): only an Echo that is
still needed stops the Reroll. `EchoWeaver.Decide` without the option keeps the
reference decision, so `tests/prototype/planner_reference.lua` still compares
10,000 random inputs with the reference, unchanged.

Kept: the Reroll preference (`allowReroll`), the Reroll charge count, trusted
resource state, the pending guards, the ordinary-board gate, the two-frozen
Reroll prohibition, exact copy counts, permanent ownership, and every
still-needed or frozen still-needed offer (taken, never rerolled away).

New reason code `REROLL_NO_OUTSTANDING_ON_BOARD`, text "Reroll: no Echo on this
board is still needed". The old text "no requested Echo on board" would be
false for such a board.

Demonstrated on fixtures only (no draw odds are modelled):

| Fixture | Reference rule | R3 rule |
|---|---|---|
| F1: need 102, board 101 (met) / 901 / 902, 1 pick, 5 Rerolls | Take surplus 101, 0 Rerolls, 102 missing | Reroll |
| Replay A: the third scripted board holds 102 | 101 taken, 0 Rerolls, incomplete | 102 taken after 2 Rerolls |
| Replay B: 102 never appears | 101 taken, 0 Rerolls | 101 taken after all 5 Rerolls |
| `policy_compare` battery, 864 decisions | - | 16 decisions differ (8 states, each verified/unverified): with Banish and Reroll both available, 12 change from Banish of the met target to Reroll, and 4 (30 picks left, low pressure) change from a low-pressure fallback take to Reroll |

Trade-off: R3 spends Rerolls in states where the reference spends none or
spends a Banish. When the needed Echo does not appear, those Rerolls are gone
and the final pick is the same. No universal or optimal gain is claimed.

Risk, stated plainly (review note N4): R3 only adds Rerolls; it removes none. No
Reroll ration is enforced (see R4). Boards that hold an already-met target
become more common as a Wishlist fills, so the extra spending grows late in a
run. At low pressure (30 picks left) R3 also rerolls where the reference takes
a filler. The limits that remain are the `autoReroll` permission, the server's
Reroll charges and the two-frozen rule.

`policy_compare.lua` pins no decision fingerprint, so it cannot show this
change. `tests/prototype/rolling_review_policy_flags.lua` pins it on the same
battery: R3 changes 16 of 864 decisions (12 Banish to Reroll, 4 take to
Reroll), R5 changes 0.

Test: `tests/prototype/rolling_review_reroll_outstanding.lua`.

## R5 - Freeze of a duplicate that the next selection makes surplus

Status: deliberate policy difference from the named reference strategy. It is a
proposed strategy change, not a correction of a proven bug. It is one separate commit. `git revert` of that commit is NOT a supported way to
switch it off: on the current branch it conflicts (this document, the test
runner, and for R3 also `logic/EchoWeaver.lua`), and the R5 code uses the
`local policy` that the R3 commit added. The supported way is the flag: set
`freezeMustStayNeeded = false` in `EchoWeaver.NEXUS_POLICY`. That flag alone
restores the reference decision and leaves the other change active
(`tests/prototype/rolling_review_policy_flags.lua`).

Reference rule: under high pressure, with a Freeze and a Banish available, the
best still-needed offer is frozen before the search.

Nexus rule (option `freezeMustStayNeeded` in `EchoWeaver.NEXUS_POLICY`): the
Freeze is skipped when the next selection is another selectable copy of the same
Echo and exactly one copy is needed. The planner takes the Echo at once.
`EchoWeaver.Decide` without the option keeps the reference decision;
`planner_reference` is unchanged and passes.

Kept: the Freeze preference, Freeze and Banish charges, trusted resource state,
pending guards, the ordinary-board gate, exact copy counts, permanent ownership,
observed frozen offers, and the reference Freeze wherever the held copy stays
needed (two different needed Echoes, two needed copies, or no selectable
duplicate).

Demonstrated on the F3 fixture only (need 101 x1 and 102 x1, board 101 / 101 /
filler, 2 picks, 1 Freeze, 1 Banish):

| | Reference rule | R5 rule |
|---|---|---|
| Step 1 | Freeze 101 (index 1) | Take 101 (index 1) |
| Step 2 | Take the other 101 | - |
| Freeze charges used | 1 | 0 |
| Next board | held surplus 101 plus two fresh offers | three fresh offers |

The `policy_compare` battery has no duplicate-offer board: 0 of 864 decisions
change. No general efficiency gain is claimed.

Test: `tests/prototype/rolling_review_freeze_surplus.lua`.

## R4 - Reroll ration and reserve fields: trace only, no behavioural change

| Item | Location | Fact |
|---|---|---|
| Counters `fillerFishState` (`guaranteedId`, `consecutive`, `bracket`, `bracketSpent`) | `core/AutomationRuntime.lua` | Session-local. Reset at each level-bracket change (`RerollBracket`: 1-34, 35-63, 64-69, 70-77, 78+), at a change of the guaranteed spell, and at each run boundary. Not saved. |
| `state.rerollBudget` (`consecutive`, `consecutiveLimit` 3, or 2 at level 10 or lower; `bracketSpent`, `bracketLimit` 4, or 2 at level 10 or lower; `reserve` 5, or 0 from level 78) | `core/AutomationRuntime.lua` StepRun | Built for every decision. |
| The only reader | `logic/Policy.lua`, historical branch "bracket fishing: reroll filler guarantee" | It rations Rerolls of an unwanted *guaranteed* Echo. Production never reaches it: `Policy.Decide` routes every ordinary board to `EchoWeaver.DecideNexus`. |
| The active planner | `logic/EchoWeaver.lua` | Does not read `rerollBudget`. Its Reroll limits are: permission `allowReroll`, trusted charges, Reroll charges above 0, not pending, fewer than two frozen offers, no still-needed Echo on the board. |
| Counter increment | `core/AutomationRuntime.lua`, after a confirmed `Adapter.Reroll()` | Keyed to the reason string `bracket fishing: reroll filler guarantee`. EchoWeaver never returns that reason, so `bracketSpent` stays 0 and `consecutive` is set to 0. |
| User setting | `data/DefaultProfile.lua` `autoReroll`, commands `/nexus reroll on|off` | Effective: it becomes `allowReroll` and `searchRefused.reroll`, and the action executor checks it again. There is no setting for a count, a bracket limit or a reserve. |
| Current user-facing text | `ui/Help.lua` "Rolling and settings", `README.md`, in-game changelog | No limit or reserve is promised. Help says: "Reroll asks for new choices when enabled." |
| Historical text | `CHANGELOG.md`, 1.19.2 Dev Test 13 | "maximum 3 consecutive rerolls against the same unwanted guaranteed Echo and 4 rerolls per level bracket", "Preserves 5 rerolls for later brackets until level 78". This describes the guarantee-based bracket fishing. |
| `core/UserText.lua` | mapping for the old reason string | Display only. |
| Test adapter | `tests/prototype/policy_adapter.lua` | Passes a fixed `rerollBudget`, as the runtime does. No test asserts that the ration limits an EchoWeaver Reroll. |

Conclusion: no current setting or text promises a Reroll ration. R4 changes no
behaviour. The fields stay as they are.

The exact question for the user:

- Fact 1. The historical ration applied to one thing only: Rerolls of an
  *unwanted guaranteed Echo* ("bracket fishing"). Guaranteed future Echoes no
  longer exist in the current contract, so that object no longer exists. There
  is no existing behaviour left to keep.
- Fact 2. "Retain" would therefore mean a NEW general Reroll budget for the
  current planner. It would not be the revival of a behaviour that exists. It
  would need new decisions: which Rerolls count, the limits and the reserve,
  one enforcement boundary, counters keyed to confirmed Rerolls (not to reason
  strings), and Help text that states the limits.
- Fact 3. "Retire" means: remove the unread fields and counters
  (`fillerFishState`, `state.rerollBudget`, the reason-string increment). The
  `autoReroll` permission and the server's Reroll charges stay the only limits.
- Fact 4 (risk). R3 spends more Rerolls than the reference, and no ration is
  enforced today. With "retire", that stays so. If the user wants a limit on
  Reroll spending, it must be the new budget of Fact 2, or R3 must be switched
  off with its flag.

Question: introduce a new general Reroll budget (and with which limits), or
retire the unread ration fields?

## Orb-offer redraw: investigation only

Question: does the repository hold evidence of a supported action that redraws
an open Orb offer, with its cost and its confirmation contract?

| Source examined | Finding |
|---|---|
| `core/OrbAdapter.lua` capability probes | Required `OrbService` members: `IsStateKnown`, `GetCharges`, `IsOfferPending`, `ConfirmSpend`, `RequestCharges`. Required `PerkService` members: `GetGrantedPerks`, `GetLockedPerks`, `GetCurrentChoice`, `SelectPerk`, `RequestGrantedPerks`. Optional: `GetDiscoveredEchoes`, `IsTomeEchoDisabled`. No redraw member is probed or called. |
| `core/OrbRuntime.lua` | One spend is `ConfirmSpend(sourceId, 1)`. A changed pending offer is treated as ambiguity ("The pending Orb offer changed unexpectedly") and pauses. |
| `docs/ORB_MEMORY_MODE.md`, `docs/P1_5_1_CORRECTIONS.md` | Describe spend, offer, select, confirmation. No redraw action. |
| `tests/prototype/orbs_support.lua` and the `orbs_*` tests | The mocked `OrbService` has the five members above only. |
| Supplied third-party reference used by `orbs_policy` (`Memory/MemoryMode.lua`) | Its one use of the word "redraw" means a result with the same spell ID as the source. It has no offer-redraw call. |
| `PerkService.RequestReroll` | This is the ordinary-board Reroll. The ordinary gate blocks it while an Orb offer is pending. It is not evidence of an Orb-offer redraw, and it must not be used as one. |

Result: unavailable from the repository's evidence. Exact missing capability:

1. The name and signature of the client call that redraws an open Orb offer
   (service, function, arguments).
2. Its cost contract: an authoritative one-Orb (or other) charge change that the
   client reports for that call, and its refusal and failure answers.
3. Its confirmation contract: evidence that a *new* offer generation replaced
   the old one for the *same* owed operation (the current API exposes no offer
   ID or generation; `boardKey` equality cannot tell a redraw from an unrelated
   offer), with unchanged rolled and permanent ownership and an unchanged
   owed-offer count.
4. Whether any quality boost carries over to the redrawn offer. Nothing in the
   repository supports an assumption either way.

Until a supported client supplies items 1-3, Nexus keeps the current behaviour:
an offer change during a pending operation is ambiguity, not a redraw. No test
for a redraw action was prepared, because no established interface exists to
test against. This investigation does not block R1 or R2.

## Decisions for the user

These items were found by the independent review of `eadff8a..578c77e`. No
behaviour was changed for them. Each needs a user decision.

### D1 (review F2) - When does `OrbService.IsStateKnown()` become true?

Facts:

- Nothing in the repository defines when `IsStateKnown()` becomes true.
  `THIRD_PARTY.md` lists the call only. The supplied reference
  `Memory/MemoryMode.lua` does not contain it.
- The ordinary rolling path never requests Orb state.
- With R1, ordinary `Take`, `Banish`, `Reroll`, `Freeze` and automatic rolling
  are blocked while an existing OrbService reports `false`. If a legitimate
  client reports `false` for a whole session (for example a character without
  the Orb feature, or a state that the server sends only on request), ordinary
  rolling is blocked for that whole session. Nexus has no remedy for it.
- The one state request call that the repository already uses is
  `OrbService.RequestCharges()`. Only `OrbAdapter.RequestRefresh()` calls it.
  `RequestRefresh()` has two callers, both inside Orb mode: the Orb window's
  Recheck, and the live pending path of a Nexus-owned Orb action, once per
  offer or result timeout (`core/OrbRuntime.lua`, `B.RequestRefresh()` in
  `Pump`). The ordinary rolling path never calls it. The repository holds no
  evidence that `RequestCharges()` makes `IsStateKnown()` true. No other state
  request call exists in the repository. None was invented.

Options:

- (a) Keep fail-closed as it is. Verify the `IsStateKnown()` lifecycle in the
  next authorized native session before release.
- (b) Add a bounded, read-only `OrbService.RequestCharges()` request on the
  ordinary path while the state is unknown (for example one request, then a
  slow retry with a fixed maximum). Its effect on `IsStateKnown()` is unproven
  until a native session shows it.

### D2 (review F6) - The `PENDING_ONLY` permit: resolved 2026-09-21

The user ruled that this was a requirement discrepancy, not a product choice.
The permit is removed; see "Correction of 2026-09-21" in the R1 section. The
earlier text of this item offered "keep" or "block"; it is kept here only as a
record that the question existed.

### D3 (review N1) - Non-board mutators while Orb state is unknown

Scope check (2026-09-21). R1 covers ordinary mutation by Nexus. Every
automatic caller of a GameAdapter mutator passes `AutoAllowed()`, which asks the
ordinary-board gate, so every automatic path is blocked while Orb state is
unknown, pending or not reportable:

| Mutator | Automatic caller (file:line in `core/AutomationRuntime.lua`) | Guard on the automatic path | Manual callers |
|---|---|---|---|
| `Take`, `Banish`, `Freeze`, `Reroll` | `StepRun`, 2433 / 2445 / 2463 / 2477 | `AutoAllowed()` and the mutator's own `OrdinaryBoardAllowed()` | none outside automation |
| `ToggleLever` | `StepArm`, 812 (disable) and 831 (re-enable) | `AutoAllowed()` (both inside the `automationAllowed` branch) | none found |
| `Save` | `StepSave`, 2562 and 2673 | `AutoAllowed()` at the entry of `StepSave` | Saved Build controls of the game UI (not Nexus) |
| `LockPerk`, `UnlockPerk` | automatic permanent-slot handling, 1891 / 1776 | `AutoAllowed()` checked again immediately before each send | Wishlist Editor lock switches reconcile through the same automatic handler |
| `UploadWishlist` | none | - | `core/WishlistController.lua` (Wishlist Editor save), `core/CommunityController.lua` (copy a shared build; the line moves when the Share work is merged) |
| `Activate` | none | - | none in Nexus code |

Test: `tests/prototype/rolling_review_automatic_paths_orb_state.lua` sends the
automatic lever and save steps zero times with an unknown state or a service
without `IsStateKnown`, and once with a known state (control). Each run starts
from fresh saved data, and each blocked case runs before its control. A mutant
whose `AutoAllowed()` ignores the gate is red at the lever step and at the save
step. (An earlier version ran the lever control first; saved state from that run
kept the blocked lever case at zero under every mutant, and this document then
wrongly named "another guard" as the cause. Found by the independent review of
`08a3caa..d91fdd7`.) The lock and unlock paths are covered by reading
(`AutoAllowed()` immediately before the send), not by a dedicated test.

Manual user controls (`UploadWishlist` from the editor or a shared build) are
not ordinary automation and were deliberately not gated.

Facts:

- `Activate`, `Save`, `UploadWishlist`, `LockPerk` and `UnlockPerk` use
  `OrbRuntime.BlocksOrdinary()` only. `ToggleLever` has no Orb guard. All six
  still send their call while an existing OrbService reports unknown state.
- They do not act on the three-card board. Every Nexus-owned or restored Orb
  action blocks the first five through `BlocksOrdinary()`. The automatic lever,
  lock and save paths are stopped while the state is unknown, because they use
  `AutoAllowed()`.
- The review found no concrete harmful scenario.
- One edge exists that does not depend on Orb state: `BlocksOrdinary()` returns
  false while `Store.State()` is nil, so a manual `Activate` in that window could
  cross the loadout boundary of a saved receipt.

Options:

- Keep as it is.
- Extend the known-Orb-state requirement to these mutators. This would also
  block manual build-slot and permanent-slot changes for a whole session in the
  D1 case.
