# Orb recovery: pick evidence and the player-confirmed Continue (035)

Status: the restored-receipt Continue path is offline-tested with synthetic data only. Native game behavior is NOT TESTED.
An approved live session now has a separate bounded recovery path with an explicit
empty-choice response requirement; see `ORB_BOUNDED_RECOVERY.md`. It does not
automatically continue a restored receipt or recover authorization after reload.
The owner accepted the residual risk that is described under "What stays uncertain".

## Why

An Orb action saves a receipt before it spends. After a reload the receipt is restored and
blocks new Orb runs and ordinary rolling until the action is confirmed from its matching
result. Two situations leave a receipt that cannot be confirmed:

* the player's pick on the recorded offer was never recorded (the choice callback needed a
  successful read at that instant, or a reload came before the next timed pass);
* the offer was already gone when the receipt was restored, so there is nothing to observe.

Before 035 the block had no exit. The owner decided on a practical exit that keeps every
fact that is known and claims nothing that is not.

### Continue is conditional, not an exit for every unresolved record

A restored record with **no retained client-observed spend** is outside the
original no-recorded-choice Continue class.
Continue requires a retained observation of one Orb fewer *with that action's offer*.
`spendConfirmed` is the compatibility field for that client observation; it is not a
server acknowledgment. Missing retained history does not prove that a client never
observed the event (a save may have failed), or that the server spent nothing. `UNOBSERVABLE`
means the available facts cannot link the action to a result, not that Nexus knows the
server completed or refused it.

There is one additional attribution-only class. A stopped action with a retained
ambiguous choice can use this same explicit checked exit when fresh ownership
shows its distinct chosen gain in the original loadout. An exact result or a
whole compound delta explained by the bounded owner archive can establish this
gain; unrelated ownership changes cannot. The ambiguity flag
is assigned before submission and is never enough by itself. The gain establishes
current build progress, not the operation that caused it. This class works after
actual completion, exhausted live checks and passive reload, and also directly
after Stop in the same session. Current owner, binding, locks, loadout and quiet
state are revalidated at consent and inside the actual atomic write. An ordinary
recorded choice without that proof stays ineligible.

For this class the original receipt is archived unchanged as `ACK_UNCONFIRMED`,
confidence `NONE`. Observed spend stays counted once; a current unobserved charge
stays unknown exposure, without a refund or invented charge. The old run ends,
with no spend, selection or automatic Resume. Failed save retains receipt and
ordinary gating. The original 8-entry / 28,672-byte manual archive caps still apply.

For a restored, idle, ineligible record the run page exposes **Why blocked...**. Opening
it reads the same refusal explanation without invoking `ContinueBegin`, requesting a
refresh or granting a consent token. Check and Continue remain disabled. Eligible
records retain the existing **Continue...** -> **Check the game's state** -> explicit
confirmation sequence. Existing checking, refused and completed states retain their
progress/review labels.

Start, Resume and reload cannot reconstruct missing history. Recheck can collect
current facts; it cannot promise to settle an unobservable action. Preserve its record
and exposure. Do not force a spend flag, erase the record, infer a refund or resend a
spend or choice. Pausing before a planned dungeon transition prevents subsequent
automatic submissions; it cannot cancel an already submitted action.

### Boundary evidence in the private diagnostic build

`OrbRuntime.BoundaryDiagnostics()` returns a detached, bounded support view without
constructing runtime state, reading the game, writing saved data or authorizing anything.
It records the existing Pump read's before/current charge relation (`equal`, `one_below`,
`lower`, `higher`, `unknown`) and ownership relation (`before`, `source_removed`,
`neither`, `unknown`), plus offer, pick and host flags and local lifecycle epoch/phase.
Missing older history stays unknown. A local epoch is provenance, never server correlation.

New small receipts may carry `boundaryJournal`: at most eight flat entries of nine
whitelisted scalar fields. The first two keep receipt/pre-call provenance; only the recent
six are evicted. Host-call disposition, observed reads, pick callbacks and leave/enter/logout
events are facts, never an action gate. At an existing new live receipt-write boundary,
the mandatory original receipt is written and verified first, omitting only this visit's
new diagnostic field. A failed mandatory write is never retried to admit an action. On
mandatory success, at most one optional journal write is attempted. Diagnostic rejection,
error or invalid data falls back to session-only evidence and cannot reject that original
receipt write. This adds one bounded Store attempt on the normal successful live write
path; its cost is measured separately. Stable reads add no writes. `unsaved`
and `durableRetained` distinguish memory observations from a verified Store write. Disk
durability still depends on the game's normal save; a process crash is not covered.

Failure-isolation tradeoff: each mandatory new live receipt save omits this visit's
diagnostic field, even if its prior version was written successfully. If the optional
write then fails, those earlier diagnostic entries are no longer claimed durable.
`priorWrittenOmitted` records the bounded number omitted, `durableRetained` is zero,
`persisted` is false and `unsaved` is true; valid evidence stays in the session journal.
This deliberate diagnostic loss cannot erase raw picks or any original receipt fact.
It never applies to a restored or foreign journal. There is no retry loop to restore it.

Existing receipts and foreign same-name diagnostic fields (including false) use
**session-only** evidence. Optional diagnostic-budget refusal is distinct from
unverifiable archive history: malformed/future history refuses new action admission
before Auto/owner acquisition and is never treated as empty. Valid full history is
readable, but cannot reserve another exit. New operations require one complete
6,144-byte exit slot plus every existing entry's remaining late-growth budget.
The prospective receipt bound includes 4,096 bytes/400 edges for supported future
receipt evidence and its archive envelope plus 512 bytes/32 edges for late facts,
inside the unchanged 6,144-byte/1,200-edge limits. The full archive remains bounded
by 28,672 bytes and eight entries. Restored valid journals are kept unchanged: new diagnostics do not alter the
receipt digest or invalidate a Continue token. The archive still stores its original
receipt exactly, including any retained journal. Diagnostics add no new settlement,
spending, selection or archive permission.

Stable repeated reads compare the existing facts and do not allocate another journal
row or snapshot. `orb.read`, `orb.status` and `orb.panel` use the optional default-off
timing dispatcher. Timing and global net Lua-heap changes are diagnostic evidence, not
exclusive CPU, allocation ownership or a native FPS improvement.

## Part 1: raw pick evidence (core/OrbAdapter.lua, core/OrbRuntime.lua)

The `SelectPerk` hook first reads the plain facts of the callback from the game's own tables
(the board, the game's pick latch, the active slot, the offer flag) with no `O.Read()`. Then
the unchanged contextual observer runs, now protected so that nothing in Nexus can reach the
game's caller. The facts go to the Orb owner, which saves them with the receipt at once.

* `receipt.picks`: at most three entries, the earliest are never evicted, identical callbacks
  merge, counters stop at 999. Each entry holds numbers, booleans and short texts: the Echo id
  the callback named, the raw board text, how the board relates to the recorded offer
  (`offer`, `ids`, `other`, `none`, `norec`), whether the game's latch held the Echo, the slot,
  what the contextual observer concluded (`ok`, `noctx`, `fail`, `diff`, `state`, `err`),
  whether the receipt's own selection names it (`u`), a lifecycle phase and epoch, the clock.
* It is EVIDENCE. `hasChoiceEvidence`, `finishResult` and `observeLifecycle` never read it.
  No selected field is fabricated and no settlement gate changes. A held, unmatched,
  context-poor or unreadable observation stays only this.
* A pick that passes every contextual check is recorded in the receipt at once, also for a live
  receipt (the same fields, the same gates, no longer waiting for the next timed pass).
* A refused save stays in memory, is retried at the next pass and flushed at every lifecycle
  event. It changes no run state.
* The underlying host implementation is not substituted: a secure post-hook may
  change global function identity but preserves host return values, invocation count and errors. The roll
  trace setting changes nothing.

An in-memory SavedVariables write reaches the disk at the game's own reload or logout save. A
crash before that is not covered and is not claimed.

## Part 2a: the passive transport observer (core/OrbAdapter.lua)

The authorized inert client source reference (not a verified tester/deployed installation) delivers
server messages through one `CHAT_MSG_ADDON` frame, keeps one handler per opcode and checks the
prefix and the framing, not the sender or the channel. The observer listens to the same event in
a frame of its own. It registers no opcode handler, replaces nothing, patches no client file and
sends nothing. It reads the game's own prefix, which no other Nexus code does; it keeps only
parsed numbers and enumerated codes, never a sender, a name or a payload.

* Capture first: the event handler only classifies and records (class, ordinal, local epoch,
  parsed numbers) and reads no game state. An evaluation reads the game's cache on a later pass,
  after the game's handler had its turn. Nothing depends on frame order.
* Class Q (qualifying, opcode 1220 only): exact prefix, the whisper channel, a sender equal to
  the player's own exact name (a known identity; no cross-realm or short-name alias), a tab and a
  non-empty body, no segmentation, exactly three fields, canonical integers of at most six
  digits. This follows the strict convention of EbonAPI 2.1.1's bridge. It is a source-backed
  expectation, not proof of the real server's sender.
* Class A: admitted (sender and channel pass) but not qualifying, or an opcode that is followed
  by arrival only (16 offers, 18 ownership, 540 and 542 slot data, 1000 pick results). For those
  opcodes a segmented message is tracked by fragment: the game calls its handler only when every
  fragment has arrived, so a fragment alone replaces nothing and makes no record; only a COMPLETE
  message is an arrival. The assembly follows the first fragment's total, as the game's does, and
  expires 15 s after it. The observer expires eagerly (before the lookup; the game cleans up after it), so it
  can only under-count a completion, never over-count one. Up to the format limit of 4095 fragments are tracked; at most eight
  assemblies at a time; a fragment outside its assembly is an unqualified admitted packet and taints. A leading-zero opcode
  ("01220") reaches the game's handler as 1220, so it is recorded and never qualifies.
* Class R: a relevant packet that the game's dispatcher would still accept and the observer
  rejects (also a message that was completed with a rejected fragment: `mixed`). R, and any
  admitted record that carries a reason (an unqualified 1220, an untrackable message), may have
  changed the game's cache, so the opcode is tainted until a later Q (1220) or a complete A (the
  others) replaces it. A failing read of the player's name is an unknown identity, recorded as
  such, never a silent miss. The check refuses on a taint it
  cannot refresh and never reads a possibly poisoned cache as a trusted baseline.
* A reply is "observed after the refresh began". The protocol has no correlation. A local epoch
  rejects local timers, closures and already-observed replies. It cannot identify an older server
  reply that arrives later, and two arrivals do not prove that no older reply remains.

If the convention does not match the real server, every reply is rejected and the counters say
so (`rejects.sender`, `rejects.channel`, `rejects.identity` in the support report). There is no
fallback to the game's local pending flag.

## Part 2c: Continue (core/OrbRuntime.lua, ui/OrbPanel.lua)

The original class: a restored receipt, a spend this client observed (one Orb fewer with
its offer; the receipt keeps it in its compatibility field `spendConfirmed`, and
no server reply confirms it), no usable recorded outcome (`hasChoiceEvidence` is
false) and the original offer gone.
The narrow observed-gain attribution class above shares this check and archive;
it does not weaken ordinary recorded-choice refusal or restore live authority.

The check (a session-only state machine, driven by the passive recovery pass):

1. needs the observer; asks the game for a refresh; waits for the first qualifying charge reply
   observed after that request began; asks again; waits for the second. Requests are serialized
   (the second goes out only after the first reply was observed; none while an earlier Nexus
   request has no observed reply in this epoch, unless that request went unanswered for the whole
   wait and was given up: a `no_reply` refusal ends the wait, and a late answer to it is then
   indistinguishable from an answer to the next request);
2. each reply needs an explicit third field of 0, a reported change (the second field) of 0 and the same balance, and that balance must equal
   the game's own cache; an ownership push must have been observed after the first request and the
   game's ownership view must have been replaced;
3. throughout: an empty board, no pending Orb offer, no pick, no host action, no in-flight action,
   no Nexus intent; the balance, the rolled and locked Echoes and the slot unchanged; no rejected
   relevant packet, no choice or pick-result packet, no loading transition;
4. a wait that ends can only refuse. A fixed time is never proof.

The pending count is three-valued: a known positive count (refused, the player resolves the offer
in the game; nothing is spent), an explicit zero, and unknown. A missing, empty, malformed,
default or optimistic third field is unknown.

The confirmation token is bound to those values and to the loading epoch. Confirm checks them
again. A loading event is only a reason to start over: it is never readiness.

### What Continue does

* keeps the spent count, the run limit and the configured maximum exactly;
  unknown current charge exposure is retained separately rather than refunded;
* moves the saved receipt, unchanged, into the character row key `orbRecoveryArchive` and clears
  the pending receipt in ONE store mutation, then verifies the row; a refused, unverified or
  throwing write is rolled back and the same token can be confirmed again;
* stops the old run. It is never re-enabled and nothing is repeated; every later action keeps its
  normal authorization, ownership, lock, resource, action and limit gates; a new Orb run needs its
  own approval;
* sends nothing but the read-only refresh that Recheck already sends. It is never automatic.

### The archive

An array of at most eight entries under the row key `orbRecoveryArchive`. It is its own key because
an older build rebuilds `orbRefinement` from known keys and drops the rest, while an unknown row key
survives (test `orb_recovery_store_compat`, released 9049 and current builds). Builds between were
not run.

Entry (`v=1`): `id` (a digest of what identifies the spend: constant from the receipt's creation, so
repeating a Continue adds nothing), `cd` (a digest of the whole saved receipt), `kind`
`ACK_UNCONFIRMED` or `AUTO_UNCONFIRMED`, `receipt` (the original, unchanged at archive commit), `spent`, `limit`, `intent` (what Nexus
intended), `observed` (counts of the raw pick evidence, which lives inside the receipt),
`resolution` (`UNCONFIRMED`, confidence `NONE`), `consent` (version, policy `TWO_OBSERVED` for explicit or `SESSION_BOUNDED_TWO` for automatic, serial),
`pre` and `post` (below), `late` and `lateN`.

`receipt.uncertain` is the cumulative earlier unknown exposure retained by that
run at its last receipt save; it is not this archive attempt's own amount. Outer
`entry.uncertain`, when present on automatic or attribution-only exits, is only
this attempt's unknown reserved exposure. `spent` is a client-observed decrement,
not a server acknowledgment. `unconfirmedResults` and `recoveries` are session
counters and stay unavailable after reload; they are not reconstructed as zero.
`pre.emptyChoice` on an automatic entry is the positive transport ordinal of the
qualifying empty-choice observation, not a boolean. Passive transport records use
`emptyChoice` as a boolean. `observed.gain=true` on an attribution exit records
actual distinct owned gain, never which operation caused it. `lateN` counts up to
99, while `late` retains at most four known flat annotations, including
`events_lost`; they never rewrite the immutable receipt or identify a server action.

Budget review (measured in `orb_recovery_store_compat`, deidentified 034 shape with three full
pick entries): the current fixture measures 220 edges, 3,091 bytes, depth 4.
This one shape is not a universal bound on retained unknown fields; admission
uses the fixed limits and reserves supported future late growth. The deepest table is
row (1) > archive (2) > entry (3) > receipt (4) > picks (5) > one pick (6): exactly at the Store's
own depth bound of 6, not past it. There is no margin: the entry cap (depth 4 below the archive)
refuses anything deeper, so a later change that adds a level is refused, not written.
Caps: an entry at most 1200 edges, 6144 bytes, depth 4; the archive at most 8 entries and 28672
bytes. The Store data-retention fixture starts, stays writable and keeps eight padded
entries within its shape budget. That preservation probe is not proof that altered
fixture digests pass Runtime history validation; actual capacity branch fixtures
use distinct entries produced by the real checked Continue path.
Refuse, never evict, never repair, never delete: a full archive, a malformed one, one written by a
newer format (`v` above 1), an oversized receipt, an unverified write.

### Logging for phase two

Session (the support report, `Nexus.SupportReport.OrbLines`): the strict-path counters (qualifying,
admitted, rejected; not accepted by identity, sender, channel, segmentation, absent third field,
extra fields, malformed, range), the last attempts (outcome, reason, replies seen, ordinal, field
count, pending and balance of each reply, balance against the record, the slot now and the original
slot, the loadout check, ownership and lock fingerprints, consent version and policy, the receipt
identifier) and the archive. The archive entry keeps the same for the confirmed attempt, plus the
request and reply ordinals, the quiet facts (offer, board, host, flight, intent), the phase and
epochs, the spent count and limit, the post-state and the late events after the archive (kinds
`pending_positive`, `choice_push`, `pick_result`, `rejected`, `reply_unqualified`; at most four kept,
counted to 99; never linked to the old receipt and never acted on). No raw SavedVariables, no
sender or player identity is added to these bounded transport annotations.
The original receipt intentionally retains its original source/choice keys, owned
map and bounded raw-pick board evidence; those are not transport correlation IDs.

### What stays uncertain (accepted by the owner for phase one)

* the server may still apply a late result for the old action; Nexus reads it as an ordinary change
  and does not link it;
* a late offer shows up as a new, unmatched offer; the normal gates hold Nexus's own actions while it
  is open;
* two replies observed after Nexus asked detect a change; they do not prove that no older reply is
  on its way;
* the Orb count may be a little off, because Orbs can be farmed; this is accepted;
* the real server's sender and channel for the charge reply, and everything native, are NOT TESTED.

### Outside the live bounded recovery path

* automatically continuing a restored receipt. A reload never restores the approved run;
* a manual accepted-risk fallback for a client whose replies cannot be observed. It would be a
  separate proposal with its own scope and risk decision; 035 does not relax any strict check;
* a slot-zero hold rule change; it needs a separate rule decision.

The shared finite archive reserves two slots and 12,288 bytes from automatic
live recovery. Explicit Continue retains its original eight-entry / 28,672-byte
caps and may use this reserve, but can still fill them. Nothing evicts or repairs
old records. The restored Continue view/cancel/confirm path never owns a live
recovery check or resets its allowance.

New pending receipts with acknowledged-history risk, attribution risk or unknown exposure use a versioned
owner identity (`attributionFormat=1`, actual GUID in `attributionOwner`, legacy
`guid` absent). Read-only inspection of exact public `a43cf27` Runtime+Adapter
shows its owner blocker refusing settlement and no-choice Continue. That exact
pair is source-only evidence here, not an executed downgrade fixture.
The current owner reads this known identity without restarting spending; unknown
or conflicting versions remain blocked. No loadout or spend fact is fabricated.
See `ORB_BOUNDED_RECOVERY.md` for the replay scope and the historical older
message. Archive-key retention alone covers a separate data-preservation claim.

An eligible held automatic attribution receipt can use Check directly. Cancel
returns only that explicit check to idle; it keeps the receipt. Ineligible
Continue requests preserve the automatic owner. Completion remains visible
across loading while its unresolved receipt continues to block ordinary actions.
Full usage and main-panel summary text is available through their hover regions;
this is an offline accessibility path, not native font-fit evidence.

## Current baseline and restored-data qualification

A successful Continue preserves the saved receipt exactly at the atomic archive
commit and ends the old run. A later deliberate Start must disclose and acknowledge
nonempty unconfirmed history as a current-state baseline, together with its maximum.
It creates no server attribution and never changes old UNKNOWN/NONE entries.
The exact acknowledged set is session-only; new entries remain relevant and reload
returns to conservative full history. Every new operation reserves a full exit
before admission; already-full restored pending records stay preserved/refused.
See `ORB_BOUNDED_RECOVERY.md` for the complete approval and capacity contract.

Passive restoration/read preserves untouched legacy saved bytes. Genuinely NEW
ambiguous ownership may instead perform the existing one-time failclosed identity
migration: original GUID information moves into attributionOwner and unknown
fields survive. This distinction is exercised by `orb_recovery_store_compat`;
it does not claim every restored record remains byte-identical after new evidence.
The restored attribution check requires this load's baseline and a later fresh
ownership observation; old lifetime selection stamps do not substitute for it.

Exact source-pin executions and failures are retained outside product source.
Test assertion names describe controls, not proof that every historical category
was executed RED on one pin. Native timing, fonts, sender/channel conventions,
installed tester version and global observer costs remain unverified.
