# Prepared Share and Edit sends during catalog work

Experimental correction for NATIVE06, based on test.9016-aa49abb, source
aa49abbd6dcd6f99604bfa9b1cbf539292eecfee, tree
95aa9e8994da9efbc3f7fbfd81a787d7016ff07d.

The original native B record saved and entered the queue. Later catalog work
withheld the full Sync update. Passive housekeeping expired B after 120.015
seconds without attemptedAt or sentAt. The exact offline reproduction and
native checkpoint are preserved separately. A successful defect probe is not
a passing product test.

An admitted manual Share now gets one normal transport turn while the full
Sync update waits for catalog or hash preparation. An explicitly approved
Edit Build / Save Details uses this same operation owner after its exact local
ticket commits. It retains the existing ID, advances its revision and prepares
one immutable summary. Edit does not gain an automatic queue-admission retry.

The existing transport controls pacing, channel availability, combat,
ChatThrottleLib capacity, throttle attribution, bounded transport retries and
terminal settlement. The Share expiry stays 120 seconds. A blocked packet can
still expire. A failed operation retains its actual reason and local record;
it is not described as sent. API submission does not prove peer storage.

Only an owned, prepared Share operation may use the restricted turn. A
throttled non-Share packet can be ahead of it. The restricted selector examines
the bounded control queue, preserves Share order, and removes only the chosen
Share. Withheld requests remain queued. The normal transport retains its bulk
fairness turn when full readiness returns. Requests, recovery, full-loadout
responses, bulk broadcasts and handshakes do not gain an early update.

Passive housekeeping also inspects a bounded, rotating slice of the control
queue. Expired or invalidated owned Shares settle even when a live withheld
request remains at the head. This releases their queue capacity and publishes
one terminal result without sending, retrying, or changing their deadline.

The current catalog owner proof must remain valid. Each approved send also
retains its player, database, catalog and binding scope. A scope change before
an Edit commit prevents broadcasting. A scope change after admission settles
the operation as superseded with reason `player or catalog changed`. Ordinary
catalog generations may advance without rewriting the approved wire bytes.

Save Details now reports a pending local save while its ticket is unfinished.
It reports saved and queued only after commit and successful admission. Busy
admission with no ticket is a refusal; the edit form stays open. The Save Link
consumer uses the same truthful receipt. No new retry control was added.

## Existing IDs after restart

On the owning character, open Build Library, select My Builds, set the DPS
filter to All Shared, and select the existing record. Use Edit Build, change
the approved description or title, then use Save Details. This updates the
same ID and queues its new revision after commit. Do not use Use Active
Wishlist Echoes for a description-only update.

For the authorized native records, A belongs to Nexustest and has ID
`mine-1789875308-486236`; B belongs to Valentinew and has ID
`mine-1789876626-962480`. Confirm the exact selected ID and owner from the
existing coordinator evidence before editing. Keep the protected main
assignment and unrelated records unchanged.

The top-level Share Build form creates a new ID. The old Retry Share receipt
is in memory and does not survive restart. Thus there is no same-ID UI route
after restart that repeats the original first-Share form approval. Edit now
exercises the related corrected prepared-summary dispatch path. It does not
prove first-Share form admission coverage. A same-session failed Share may
offer its existing explicit Retry Share action while its receipt remains.

Edit requires the owned record and normal catalog admission. If another
mutation owns admission, the form reports refusal and retains its draft.
An accepted ticket completes through the normal lifecycle. Later unrelated
catalog/hash work no longer blocks its prepared summary, but full-loadout
responses and peer reconciliation retain their own readiness requirements.
Observe the actual operation and peer's exact ID/revision/content. A saved
record, queue admission, chat message or API return alone is not peer receipt.

## Offline coverage and remaining limits

The retained 85 prototype scripts remain unchanged. Six new LuaJIT scripts
exercise real Share and Edit controls, source snapshots, catalog tickets,
ordinary lifecycle callbacks, operation receipts and paced wire submission.
They cover real Put and retention candidates, delayed notifications, unchanged
IDs and Echoes, queue ordering, invalidated approval scopes, combat, bandwidth,
missing CTL, suspended wire, adapter readiness, exact expiry and no automatic
duplicate. The Edit long-contention fixture uses ordinary delayed frame
notifications; it does not force readiness or drain a candidate directly.

A separate fresh-process reload probe preserves an actual synthetic database
between two LuaJIT processes. The original Edit failure and its 1,000-second
observation remain evidence, not a passing result. Corrected probe results and
independent review belong to the delivery receipt.

All tests are synthetic and offline. Native send timing, peer convergence and
game capabilities remain unverified for this replacement. The writer does
not install, launch or interact with the client. No Orb spending is authorized.
The prior same-ID Orb ambiguity rule still retains pending ownership and
unresolved exposure. No resource refund, automatic retry or native capability
claim follows from this Sync correction.
