# Bounded recovery within an approved Orb run

Status: offline regression coverage with synthetic services. Native behavior,
server reply conventions and actual resource spending are not tested.

Start approves the displayed maximum and allows up to **two recovery checks in
that session run**. Neither a successful replacement, Pause/Resume nor elapsed
time renews this allowance. Stop cancels further actions. Logout/reload restores
only the passive unresolved receipt; it cannot restore run authorization.
World entry without a preceding leave pauses the run; further action requires
explicit Resume and its current guards.
A lightweight observer retains only the three-second pacing deadline when a
leave/entry pair happens before the first full Orb owner exists. It initializes
no run and reads no game state. Start may accept approval during that hold but
submits nothing until it expires. The full owner's receipt epoch and
`lifecycleObserved` diagnostic still describe only events it actually observed;
the lightweight hold does not manufacture prior receipt history. Pause/Stop win
over expiry, and an expired hold supplies no new approval.

## New approval and finite exit space

Every new operation must retain room for its possible explicit unconfirmed exit:
one of the eight slots and a full 6,144-byte entry inside the 28,672-byte total,
including the remaining supported late-annotation growth of all old entries.
Prepare and fresh Confirm refuse before disabling Auto or acquiring the Orb owner.
Each new operation checks again before pending creation, in the actual mandatory
Store write, and at the final guarded host call. No record is evicted or repaired.
An approved run without pending stops and releases ownership when no exit space
remains. Ordinary rolling is not blocked by that unadmitted refusal. An already
full restored pending record remains preserved and blocked: this build cannot
retain another exit for it. Full is a finite terminal limit, not endless retries.

After an explicit checked Continue ends the old run, a NEW deliberate Start may
acknowledge valid earlier AUTO or explicit unconfirmed history as a current-state
planning baseline. The same Start area displays the history count, late-result
risk and maximum; its actual callback supplies the represented review fact.
Prepare exposes that risk and Confirm requires the exact acknowledgment fact.
Programmatic Start without the represented fact refuses nonempty history.
Empty-history callers keep their existing approval path.

The approval holds exact bounded receipt/envelope copies in session memory only.
All archive data validates before acknowledged entries are filtered from BOTH
source/pair ambiguity and compound-delta checks. New entries during the run are
never silently acknowledged. Changed receipt/envelope facts or unsupported late
identity annotations invalidate the baseline. Supported bounded late diagnostic
facts carry no source/choice identity and may grow inside their reserved envelope.
Old entries retain UNKNOWN/NONE semantics; no server operation is identified.
Only an exact fresh observed replacement can settle the new receipt under this
accepted baseline, and its log states the absence of server correlation. An
unexplained compound mismatch remains held. Stop revokes spending; the same
pending may still be observed with its baseline context. Logout/reload restores
neither acknowledgment nor authority and uses conservative full history again.

Loading holds the owner in `WAIT_WORLD`. Nothing is submitted outside the world.
After a classified entry, the pending timer restarts and a three-second
settling window precedes mutations. This is a deliberate new wait opportunity,
not exact subtraction of elapsed loading time. A readable current offer
can then be selected once if no earlier selection was submitted. This is pacing,
not proof of server hydration: these APIs expose local caches without a server
revision or a correlated post-entry readiness signal. A client selection latch, active action, changed
assignment/character/loadout/locked set, or unresolved current choice blocks a
new spend. Unreadable post-entry data gets at most twelve seconds before pause.
The native API does not let Nexus cancel a stuck selection latch.

## Missing result

After the existing offer/result timer, the owner first tries ordinary exact
result settlement. If the current state is quiet, it may begin a recovery check:

1. Keep the original receipt and all normal owner, source and assignment gates.
2. Ask for charges and ownership twice, serialized; ask for the current choice
   only with the first request. The game's automatic
   acceptance must be known off before a choice request and throughout the check.
3. Observe two qualifying, equal-balance charge replies, serialized after each
   refresh, with explicit pending count zero and reported change zero. Require
   an ownership push and a replaced ownership observation after the first request.
4. Require an exact admitted empty choice response after the first request,
   evaluated on a subsequent pump. The current getter must show no present
   choice; malformed choice tables are refused. A later nonempty, malformed,
   rejected or segmented choice response invalidates the check. So do a loading
   transition, selection result, active latch/intent, or changed state.
5. Atomically archive the final saved receipt unchanged as `AUTO_UNCONFIRMED`,
   with outcome `UNCONFIRMED` and confidence `NONE`. Verify the write before
   clearing the session pending marker. Archive limits and rollback still apply.
   Automatic recovery leaves two of the existing eight entry slots and two
   worst-case entry byte budgets (12,288 bytes) for explicit recovery: its cap
   is six entries / 16,384 bytes. Both begin and final atomic write check this.
   Existing records and unknown fields are retained without eviction or repair.
   Explicit restored Continue keeps the original eight-entry / 28,672-byte cap;
   that finite archive can still fill. The refusal identifies the protected reserve.
   Those original explicit-exit caps measure the retained raw entry/total, including
   opaque legacy fields. They do not retroactively add prospective late-annotation
   reservations to old entries. Optional late evidence is skipped if it would exceed
   the actual raw caps; no receipt is changed to make room. New operations and
   automatic exits still reserve their supported future growth before admission.
6. Recompute the actual build and safe sources before a new attempt. Never
   replay the old spend or selection. The third unresolved operation pauses.

A failed or unanswered check pauses with its original pending record and
exposure retained. A timer only starts a check or ends a wait; it proves no
result. Missing optional capability preserves the existing one charge/ownership
refresh, then pause route without consuming a recovery allowance. A partial
refresh keeps its already-sent charge-request mark; no later query is sent after
a failed call. A legitimate first choice query must be observable before the
check consumes allowance; an unobservable query retires that tentative check and
reuses its sent refresh rather than issuing a duplicate. Missing reply evidence
after an admitted check pauses that check, without renewing its allowance.
An explicit Recheck while that charge reply is outstanding requests ownership
alone, allowing an exact result to settle without overlapping charge requests.

Before admission, the row must be durable, choice and pick evidence usable,
observers available, and space for a worst-case 6,144-byte entry available inside
the automatic cap. The actual entry and current capacity are checked again at
the atomic write. No failure repairs, evicts or clears the original record.

## Exposure and completion

`spent` keeps the existing meaning: an observed one-Orb decrement, not a
server-confirmed operation. `reserved` holds the current unknown spend.
On an unconfirmed archive, any reserved amount moves to `uncertain` rather than
being refunded or called spent. All three count toward the original maximum.
`unconfirmedResults` counts archived outcomes separately. These counts remain
visible in the run page, history/copy report and mini view during that session.
After reload, retained `uncertain` and current reservation are still reported,
but prior session recovery/outcome totals are explicitly unavailable. No totals
are reconstructed as permission to resume. Each archive entry
records only that attempt's unknown exposure, not the cumulative run total. The archive retains the original intent;
it never supplies owned Echoes or confirmed operation history.

Manual source counts are finite approvals for source attempts. An unknown
attempt does not refund that source quota, so manual mode can still end at
`NO_SOURCES` while the getter shows the same source. The normal automatic Start
recomputes safe actual surplus before each new attempt within the approved
maximum and the two-check allowance. Neither mode assumes a missing result.

The owner rebuilds source/choice uncertainty from the current character's bounded
unconfirmed archive. Outside the exact session-only acknowledgment described
above, this includes earlier approved runs and all passive reloads. It
remembers pairs, or conservatively the source when no usable choice was recorded.
The archive's original receipts, identifiers and content digests must validate;
unknown, malformed or future history cannot authorize another spend or result
confirmation. Another character's receipts supply no attribution memory.
At receipt creation, possible choices for its source are retained before a target
is known; unacknowledged source-only uncertainty marks the receipt immediately. Own, observed,
manual and restored selections all apply the same rule before persistence. The
flag alone proves neither a gain nor a spend. Different pairs keep ordinary exact
settlement. Without a new acknowledged baseline, a matching later gain advances actual
build progress but does not confirm a subsequent matching operation. The remaining bounded check can retain that current result as
unconfirmed; no allowance or source quota is renewed. When fresh actual ownership
shows the distinct chosen gain but attribution alone prevents settlement, the
player may Stop and use **Continue → Check → Confirm**, also after reload,
completion or exhaustion of the two checks. The existing manual quiet proof,
8-entry / 28,672-byte cap and atomic save apply. The flag alone is insufficient:
the recorded choice, fresh distinct gain, original loadout, locks, owner and current
binding must agree. An ordinary recorded choice without this proof remains
ineligible. A successful explicit exit archives the exact receipt as
`ACK_UNCONFIRMED`, confidence `NONE`, ends the old run and releases ordinary
rolling. It sends no spend/selection or automatic Resume. Observed spend is not
charged twice; unobserved charge exposure moves from reservation to unknown
exposure without a refund. A refused save retains the receipt, exposure and gate.

Only observed actual ownership can complete the selected build. If it completes
while the last operation cannot be attributed, the run stops with its unresolved
receipt and exposure retained until that explicit checked exit; completion does
not create a confirmed action. Reaching the
exposure maximum is a budget stop, and an exhausted recovery allowance is an
unresolved pause. Neither is build completion. This path does not address a
normal `NO_SOURCES` stop: source availability remains based on the actual build.
If an actual matching result later settles the completed run's last receipt,
the receipt clears and operation ownership releases, while COMPLETE or
ROLLED_COMPLETE remains terminal. A later observation of missing or changed
targets cannot reopen Resume or spending under that ended approval. Deliberate
Stop remains STOPPED. ROLLED_COMPLETE retains its locked-target limitation.

## Native limits

The authorized inert perks-service reference is ProjectEbonhold metadata version
37; see `THIRD_PARTY.md` for that artifact's identity and cache/request symbols.
Its digest does not pin the separate dispatcher, prefix or charge/slot handlers;
those compatibility assumptions use earlier unpinned snapshot observations.
Its getter returns
its local choice cache. Tester/deployed version equality is not established. An empty choice
reply clears that cache to nil, but an unparseable choice reply can also clear
it to nil. Therefore nil remains unknown in passive diagnostics and supplies no
recovery permission by itself. The passive transport observer retains only a
boolean for an exact empty choice response, never the raw body or sender. It
does not replace a handler or change the protocol. A naked request echo is not
an empty reply.

At approved Confirm, a secure post-hook of `SendAddonMessage` is installed when
available. `hooksecurefunc` may change the global function identity; Nexus does
not substitute the transport implementation: the original is still invoked.
No native opcode handler is registered. The installed observation must remain
available and unchanged. The query must synchronously
produce an observed bare `16` send. Any own exact framed-empty `16\t` send during
the check refuses it, independently of echo counts; a framed send within the
15-second pre-check lookback also refuses admission. No raw payload is retained.
The hook is installed once and makes a protected prefix/scalar comparison per
outgoing addon message. Its cost is unmeasured. Clients that hide, defer or frame
the request this way cannot use automatic recovery; capabilities alone do not
pin native framing. Only scalar outgoing-send facts are retained.

Replies are observed after a refresh began; the protocol has no request or
operation identity. This cannot prove that an older server reply will not arrive
later. A late offer arriving while the current receipt awaits an offer may be
adopted only under its ordinary offer/balance/ownership guards. If the check's
choice query returns that owed offer, the check refuses; explicit Resume may
select it once only when no selection was attempted and every current guard
passes. Stop never enables this route. Other failed checks require actual result
settlement, manual resolution, or passive reload and eligible explicit Continue;
they have no check-again button. A late ownership change is current ownership.
Its entire delta may be checked against a nonempty subset of the at most eight
retained attempts, with or without the current source removal and chosen gain.
Known pairs require their exact deltas; source-only attempts require the known
removals and corresponding observed positive gains. An explained extra delta
holds attribution and preserves the receipt; it never confirms an archived or
current action. A compound snapshot can support the explicit checked exit only
when it also contains the current distinct chosen gain. Unexplained changes
remain a mismatch. Actual owned completion is evaluated on these pending paths
without erasing the pending receipt or restoring authority after Stop.
The client source establishes request/handler behavior, not actual server reply
delivery or the required sender/channel convention. If those signals are absent,
recovery pauses. Requesting a choice is a network query, but a returned offer may
activate the game's own automatic acceptance if the player changes that setting
while a response is in flight; Nexus checks it before requesting and on each pass.

The offline regression uses real Nexus owners and adapters with synthetic game
services. It covers transition reconciliation, explicit empty replies, nil with
no reply, invalid/old/segmented replies, Stop, active actions, persistence and
binding refusal, the fixed allowance, uncertain exposure, and actual completion.

The restored Continue UI does not own a live check. Viewing, opening or cancelling
it cannot consume a live allowance or cancel its check. Pause/Stop freeze that
check; passive/nested pumps cannot issue its next query or archive. During an
admitted check, ordinary same-ID/mismatch pauses give way to the check's bounded
quiet-state refusal; this supplies no weaker result-confirmation permission.
The support view labels its separate live stage without a manual token. A held-choice
reload hint is tied to the receipt that crossed loading and survives its timeout
pause; it does not follow later unrelated choices. Native visual fit remains
unverified; the approval disclosure has a conservative offline wrapping check.

After an automatic archive, its session-only quiet-choice permission remains
bound through the next spend's final owner guard inside `OrbAdapter.Spend`, after
source and assignment evaluation and the adapter's current native read. A newer
malformed, nonempty, rejected or segmented choice arrival invalidates the earlier
empty fact. A later exact admitted empty reply can restore that choice fact only
while the other current guards still agree. Loading, a newer own query, lost
observations or changed protected state refuses the old permission. A failed
observation remains unknown; no new query is added to clear it. Waiting ends in a
pause after the existing bounded wait. Stop/Pause still require explicit further
authorization, and no source quota, exposure count or recovery allowance is reset.
Actual ownership may advance and may complete the build before any next spend.
This does not promise invariance against an arbitrary game-mutating replacement
of the documented passive provenance sink; native event dispatch is synchronous.

## Backward-safe pending identity

New pending records admitted under nonempty acknowledged history, with attribution
risk, possible ambiguous choices or retained unknown exposure encode their real owner GUID as `attributionOwner`, with
`attributionFormat=1` and no legacy `guid`. No owner, native, loadout, choice or
spend fact is invented. Current readers accept only that known version with a
nonempty owner and no conflicting legacy GUID. Other versions stay blocked.
Passive untouched restoration preserves saved bytes. If genuinely NEW ambiguous
ownership is observed on a legacy restored receipt, the existing safety migration
moves its original GUID into attributionOwner once and retains all original
information and unknown fields. This qualified migration is not passive byte
identity, server attribution or restored action authority.

Read-only inspection of the exact public `a43cf27` Runtime+Adapter source shows
its existing unknown-owner gate on this record. That exact pair was not executed
by these focused fixtures; this is source-only downgrade evidence. It cannot settle the result or use its no-choice Continue, and
the ordinary-action blocker remains. Its historical message says the action
belongs to another character; here it means that reader cannot interpret the
versioned owner identity. The inspected owner guards preserve the pending record; archive-key retention
is separately executed with released 9049 and current Store boundaries. The
current owner can read the identity after upgrading again, without resuming.
This is separate from the released 9049 archive-key retention controls; it does
not establish semantics for every older dependency combination or native timing.
`AUTO_UNCONFIRMED` archive entries remain version 1. Original receipts and archive
caps are retained, with no global Store migration or synthetic loadout latch.

## Recovery authority and presentation

A completed run with an unresolved receipt remains COMPLETE or ROLLED_COMPLETE
across loading and passive checks. Its receipt, counters and ordinary-action
block remain; Pause cannot reopen a limit increase. An eligible held automatic
receipt can enter explicit Continue through the real Check, Cancel and Confirm
controls. An ineligible manual entry leaves the automatic check owner intact.

An unchosen owed offer can be resumed under the same strict receipt, original
loadout, owner, locks, ownership, one-Orb balance and current-action guards when
it arrives choice-first, charge-first, cache-first, during Pause, or after a
pre-admission outstanding-query timeout. Resume completes that already approved
choice once; it submits no new spend. Stop, restored/selected receipts, changed
contexts, unrelated ownership and native latches retain their refusals.

Post-archive revocation is permanent for that permit. Direct Resume reports the
current refusal; both status views withhold it. Unknown reads keep the last
classified transport ordinal, so an intervening rejected or nonquiet event is
still checked after reads recover. Only a classified exact empty reply can
restore an uncertain choice fact, with all other guards still valid; it cannot
undo revocation. A paused unresolved receipt still collects observations without
gaining action authority. A paused post-archive permit with no pending receipt
keeps no full-read pump loop: the full status view or explicit Resume classifies
its retained transport backlog. Resume performs a fresh action read.
The approved exposure limit and zero-resource terminal are evaluated before a
permit wait. An actual host-false result consumes the one-use recovery permit,
using the Adapter's fourth typed `HOST_FALSE` return after actual host crossing;
display wording is not safety authority. A pre-host refusal does not consume it.
The diagnostic host_call observer runs after the protected invocation, before
its typed return event, so no diagnostic callback intervenes after the final guard. An ambiguous submission retains its receipt.
Pre-host validation exceptions and final-guard exceptions are typed known-unsent
rejections, not ambiguous host calls. Spend rejection restores its unused source
quota and clears its unsent receipt/reservation. A failing read also invalidates
post-recovery choice permission without consuming a host-crossing permit or
inventing exposure/progress. A rejected selection instead retains the actual
preceding spend receipt, marks that selection refused and never automatically
reselects. Existing bounded Errors diagnostics retain exception causes, even
though a failure of the diagnostic recorder cannot turn a rejection into a call.

Missing query or outgoing-hook capability has a named bounded fallback: one
legacy refresh, no recovery admission, no choice query, retained exposure and
pause. A real outgoing-hook installation is attempted at most once per adapter
lifetime, including failure; missing capability is distinct from a failed
attempt. Incoming observation installation remains separate. Support copy
reports availability, outgoing framing counts, actual archive kind/confidence
and consent policy, with observed run spends separate from each attempt's
unknown exposure. Full usage and compact-strip text is available on hover.
The mini view also shows unknown spend, current reservation and unconfirmed
outcomes together on its existing visible line; missing historical totals stay
unknown. Archive/report projections distinguish malformed observed numbers and
codes from absent values, without emitting their raw contents or repairing data.
Repeated identical holds do not revise history; real transitions still do.
Content-equal validated history and bounded invalid-content verdicts may be
reused by passive views. Real changes invalidate them, and actual atomic row
checks bypass those view caches. Oversized/deep history is not retained by a
negative cache. No cached verdict grants action authority.

Native clipping, timing, protocol identity and global observer costs remain
unverified.
