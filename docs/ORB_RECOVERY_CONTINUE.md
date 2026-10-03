# Orb recovery: pick evidence and the player-confirmed Continue (035)

Status: phase one, offline-tested with synthetic data only. Native game behavior is NOT TESTED.
Phase two (an automatic continuation with a notice) is NOT built and is not authorized.
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
* The hook's host function is untouched: return values, invocation count and errors. The roll
  trace setting changes nothing.

An in-memory SavedVariables write reaches the disk at the game's own reload or logout save. A
crash before that is not covered and is not claimed.

## Part 2a: the passive transport observer (core/OrbAdapter.lua)

The audited client (the owner's installed bytes; the reporter's build is not verified) delivers
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
  message is an arrival. At most eight assemblies are tracked; a message that cannot be tracked
  (more than 64 fragments) is an unqualified admitted packet and taints. A leading-zero opcode
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

The class: a restored receipt, a confirmed spend, no usable recorded outcome
(`hasChoiceEvidence` is false) and the original offer gone.

The check (a session-only state machine, driven by the passive recovery pass):

1. needs the observer; asks the game for a refresh; waits for the first qualifying charge reply
   observed after that request began; asks again; waits for the second. Requests are serialized
   (the second goes out only after the first reply was observed; none while an earlier Nexus
   request has no observed reply in this epoch);
2. each reply needs an explicit third field of 0 and the same balance, and that balance must equal
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
`ACK_UNCONFIRMED`, `receipt` (the original, unchanged), `spent`, `limit`, `intent` (what Nexus
intended), `observed` (counts of the raw pick evidence, which lives inside the receipt),
`resolution` (`UNCONFIRMED`, confidence `NONE`), `consent` (version, policy `TWO_OBSERVED`, serial),
`pre` and `post` (below), `late` and `lateN`.

Budget review (measured in `orb_recovery_store_compat`, deidentified 034 shape with three full
pick entries, the worst case): one entry is about 218 edges, 3 KB, depth 4. The deepest table is
row (1) > archive (2) > entry (3) > receipt (4) > picks (5) > one pick (6): exactly at the Store's
own depth bound of 6, not past it. There is no margin: the entry cap (depth 4 below the archive)
refuses anything deeper, so a later change that adds a level is refused, not written.
Caps: an entry at most 1200 edges, 6144 bytes, depth 4; the archive at most 8 entries and 28672
bytes. The real Store starts, stays writable and keeps the archive with eight entries at the caps.
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
sender, no player, no Echo id or board is logged.

### What stays uncertain (accepted by the owner for phase one)

* the server may still apply a late result for the old action; Nexus reads it as an ordinary change
  and does not link it;
* a late offer shows up as a new, unmatched offer; the normal gates hold Nexus's own actions while it
  is open;
* two replies observed after Nexus asked detect a change; they do not prove that no older reply is
  on its way;
* the Orb count may be a little off, because Orbs can be farmed; this is accepted;
* the real server's sender and channel for the charge reply, and everything native, are NOT TESTED.

### Not built, not authorized

* phase two: continuing automatically with a notice. Field logs and a coordinator decision must gate
  it;
* a manual accepted-risk fallback for a client whose replies cannot be observed. It would be a
  separate proposal with its own scope and risk decision; 035 does not relax any strict check;
* a slot-zero hold rule change; it needs a separate rule decision.
