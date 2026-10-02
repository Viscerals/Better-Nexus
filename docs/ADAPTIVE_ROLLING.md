# Adaptive rolling strategy and local roll record (experimental)

Status: private experimental build. Offline evidence only. No native (in-game)
test, no calibrated draw model, no claim of a gain in the live game.

## What changed

| Part | Where | Default |
|---|---|---|
| Adaptive strategy `adaptive-0-settle-live1`, profile `group-protected-neutral-1` | `logic/EchoWeaver.lua` (`DecideNexus`), reached through `Policy.Decide` | ON (setting `rollingPolicy = "adaptive"`) |
| Released strategy `released-nexus-1` | the same module, unchanged rules | explicit rollback: `/nexus policy released` |
| Automatic local roll record | `core/RollRecorder.lua`, stored by `core/DiagnosticLogs.lua` (history `rollTrace`, key `rollTraceLog`) | ON (setting `rollTrace = true`) |
| Report | `/nexus report` (Prepare report file: a `rolltrace` section), `/nexus trace` (the Roll trace tab, paged copy) | on request |

Action execution is unchanged. Preparation, the one-beat intent, immediate
authorization, adapter submission, uncertainty holds and authoritative
confirmation in `core/AutomationRuntime.lua` stay the only path. Orb resource
safety is not touched.

## Source of the strategy

The private study `echo-banish-policy-sim` (commit
`85ec1d233d258f01b21ccea92094f8c438847b76`, tree
`9ebaff0b54203365cfc2776d382304f0dec13196`, `tools/echo-policy-sim/adaptive.lua`,
`candidates.lua`, `CATALOG_STUDY.md`) selected `adaptive-0-settle` on 11,520
training runs and measured it on 57,600 held-out runs (69,120 synthetic runs in
all; 14,400 held-out runs per policy). Complete Wishlists, averaged over the study's
12 model profiles: adaptive 19.28%, protected Banish-first 18.78%, released 16.83%.
Several of those profiles use role multipliers or spell-ID Banish exclusion, which
the live variant does not model; the figures are not specific to the live profile. Adaptive against released: +2.44 points, paired seed-cluster
interval [+1.33, +3.56]. Adaptive against protected Banish-first: +0.49 points,
interval [-0.26, +1.24], which the study calls inconclusive. The study states
that no unique or live optimum is established.

Those numbers hold only inside the study's declared model. Its equal draw weight
for every eligible exact Echo is an assumption, not a measured server rule. The
ASSUMED profile is: neutral weight (equal per exact Echo), Banish exclusion by
quality group, no role multiplier. Nothing here is calibrated to the live game.

## Rules

On an ordinary board the live variant runs these steps in order.

1. The pure planner decides. It runs with Banish before Reroll on an unwanted
   board and with Freeze off. It keeps every gate it always had: Take, Banish,
   Reroll and Freeze permissions, trusted charges, pending actions, the Orb gate,
   guaranteed, frozen, carried and just-frozen protection, and the rule that two
   held offers prohibit Reroll.
2. A Take with two useful unheld offers and no held offer becomes a Freeze of
   one of them. The surplus copy of a single needed Echo is not frozen (the same
   Echo twice counts only when two copies are needed). Needs a trusted Freeze
   charge, Freeze permission and two picks left.
3. A Take or Freeze aims at the useful offer with the most outstanding copies.
   With neutral weight the study's copies-per-unit-weight score is the copy count.
   A tie goes to the first offer shown.
4. A Banish aims at the first unheld, unguaranteed, selectable, not-needed offer
   whose quality group holds no needed Echo. With no such offer the planner
   decides again without Banish (normally Reroll).
5. A Banish while only held offers are needed becomes a Take of the held offer.

Every returned action is checked again against the normalized board, permissions
and resources before it leaves the module (`Valid`). An invalid action falls back.

## Inputs

The policy consumes the live adapter's normalized values, never the study's own.

| Study input | Live input |
|---|---|
| `owned.bySpell` need counts | `outstandingCounts`: requested minus ordinary copies minus locked copies. With explicit roles a lock covers only the plan's locked targets of that Echo. The locked-role subtraction in `Prepare` is unchanged. |
| `catalog.familyOf` | `state.catalog.familyOf` |
| eligible pool and weights | not available live and not invented |
| replacement actions built by the lab | none: the shared planner builds every action |

## Divergences from the study

| Study | Live variant | Effect |
|---|---|---|
| Banish victim among safe offers is the one in the group with the highest pool weight | the first safe offer | differs only when the study could rank victims by group pool weight. 22 of 250 divergence vectors differ, always only in the victim index, never in the action kind. |
| Take or Freeze target ignores `selectable`, `freezeEligible` | both are required | an invalid action is not proposed |
| An offer with an unknown quality group may be Banished | it is never Banished | conservative |
| Lab reason text | live reason codes `BANISH_BEFORE_REROLL`, `PAIR_FREEZE_SECOND_NEEDED`, `SETTLE_HELD_WANTED` | labels only |

The live variant has its own policy ID because of the first row.

## Fallback and refusal

| Condition | Result | Recorded as |
|---|---|---|
| Selector `released` | released policy | `req=released`, no fallback |
| Selector is another value | released policy | `fb=SELECTOR_UNKNOWN` |
| A needed Echo has no quality group in the catalog | released policy for this choice | `fb=FAMILY_UNKNOWN` |
| The adaptive action fails the final check | released policy | `fb=ACTION_INVALID` |
| An error inside the adaptive path | released policy | `fb=ADAPTIVE_ERROR` |
| Orb gate, pending action, unsynced ownership or locked state, missing plan, board not three offers, missing pick count | `wait`, as before | `pr=wait:...` |

`/nexus status` shows the strategy in force and the last fallback reason.

## Selector

`rollingPolicy` is read on every decision. A new value takes effect only while no
action intent exists. An intent in any state (prepared, submitted, uncertain,
expired) keeps the strategy that made it. The change is never applied by clearing,
replaying or re-deciding an intent. The switch is recorded as a `policy` boundary.
In a read-only saved root the value applies to the session only.

## Local roll record

Recorded automatically, on this computer. Observation only: no poll, retry,
roll, selection or spend is added, and no caller waits on the recorder. Every
entry point is protected and answers nil on failure.

| Item | Rule |
|---|---|
| Records | at most 256 (`DiagnosticLogs` ring); the oldest is replaced first |
| Size | at most 2048 string bytes per record; flat records, no nested tables; at most 32 targets per decision; lifecycle text at most 240 bytes |
| Worst case in saved data | about 0.5 MiB |
| Work | `O(targets)` per decision for the record itself; each lifecycle or after update goes through `DiagnosticLogs.UpdateLast`, which checks the ring (at most about 320 slots) and copies one record, about 4 updates per decision; no catalog scan, no per-frame work, no full-catalog copy; the sorted target list is reused while the plan table is unchanged; the catalog version is read once per catalog revision |
| Identifiers | opaque session tag (base 36 of the login time), run id `<tag>r<n>`, decision id `<tag>-<n>` |
| Never kept | account, character or realm name, Wishlist or build name, chat, credentials, any network data |
| Retention | until replaced by newer records, `/nexus trace clear`, or removal of the saved data. `/nexus logclear` and Clear Log leave it alone. |
| Disable | `/nexus trace off` (exact `false` setting only) |

Each decision record links: addon build label, policy, profile, requested
selector and fallback reason, catalog version, level, class token, horizon, active
slot, capability text (pending, Orb gate, unsynced, disabled and refused states),
charges with trust, the three ordered offers with quality and flags, the proposal,
the targets with requested count, locked target count, ordinary and locked copies,
stack cap, known eligibility digit and required spell, then, in the same record
while it is the newest one, the action lifecycle with timing, the first
observation after it (offers, charges, ordinary ownership change), the Freeze or
held-offer survival, and the confirmation basis. When another record was written
first, the late fact becomes its own record naming the decision (`ref`).

Completeness is explicit. `inc` lists parts known to be incomplete (`tg` targets
cut, `ow` ownership not synced, `el` eligibility unknown, `ch` charges untrusted,
`io` lifecycle text cut). Every prepared intent is named in the lifecycle text `io` (`=t2.200002`: kind letter, offer index,
spell id), and `sa` is the action actually SUBMITTED. The outcome fields (`fz`, `af`, `ao`) describe
the submitted action, never the board's first proposal `pr`; a proposal that was never submitted gets
no Freeze outcome. A board can see several intents (a superseded or refused one, then another); only
an accepted submission counts. Two accepted submissions on one board, or a submission with no
action identity, are marked `am` (ambiguous) and get no outcome annotation. `pd` counts records
dropped before this one. A gap in
the decision numbers shows replacement. A decision with no outcome before a
`session` boundary was interrupted by a reload. (Records carry their own session tag, so
the gap shows even when a loading boundary was written first.) `fate=interrupted:world_leave` or
`:run` marks a loading screen or run reset. Boundaries recorded: `session`,
`run`, `world_leave`, `world_enter`, `auto`, `policy`.

The prepared support report (`/nexus report`, Prepare report file) carries the whole record
in its own section. A full ring is about 120 KiB of text typically (up to about 0.6 MiB in the worst case), and the report file is also
stored in the companion addon's saved data, so that data holds a second copy. The report
limit is 1 MiB. Ownership fields cover the Wishlist targets only (`tg`, `ao`), not the character's full
ownership, so the record alone cannot calibrate the game's complete draw mechanics.

Limits: the record is not a draw model. A board and the next board are
observations. A proposed action is not a result. Eligibility digits use class,
level, lever opt-out and stack cap only; whether a prerequisite spell is learned
is not known to the addon. Hidden server rules are not recorded.

### Measured overhead (offline, LuaJIT, not a WoW client)

One decision cycle (record, outcome updates, after-observation) costs about
0.03 ms of CPU in isolation (`roll_recorder_unit`). Inside the full runtime loop
(poll, step, decision, panel, intent; fake game services) an A/B run with
recording on and off measured about 0.05 to 0.09 ms per board of added CPU, within
the noise of the 1 ms clock, and about 9 KiB of added allocation per board. The
policy decision itself costs about 0.03 ms. The measurement is
offline on one machine and is not a WoW client figure. `/nexus perf` lists
`rolltrace.decision`, `rolltrace.intent` and `rolltrace.after` for the live client.

## Tests

`adaptive_policy_rules` (rules, fallback, purity, safety sweep),
`adaptive_policy_parity` (750 study-made replay vectors),
`roll_recorder_unit` (privacy, bounds including the worst-case record, flags, failure,
linkage, overhead),
`roll_recorder_runtime` (real runtime, selector at a safe boundary, loading,
equivalence with the recorder on, off, failing and absent, commands, read-only
root). Existing tests that asserted the released decision are pinned to
`rollingPolicy = "released"` or use a board where both strategies act the same.
