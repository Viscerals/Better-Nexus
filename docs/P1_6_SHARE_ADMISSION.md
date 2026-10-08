# Share Build during incoming catalog work

Experimental P1.6 correction for NATIVE-05, based on the exact reviewed source
3551401852dc5d67dbe48d47e4b5fd63802e3f30 (test.9015-3551401).

Two normal Share clicks on that build returned ROOT_MUTATION_PENDING. Neither
attempt produced a stored record or a retained local-save ticket. A later
passive observation showed an incoming catalog write still in progress. The
original screenshots, exact IDs, baseline and offline failure remain in the
separate correction evidence.

Share now retains one approved content snapshot and one ID when an existing
same-owner catalog write is in progress. The existing lifecycle gives it the
next normal admission turn before another incoming Sync update can start.
The catalog still performs all validation and bounded preparation. The intent
submits once; a rejected or failed write is terminal and is not retried.

The form reports that Share is waiting to save and that nothing has been sent.
It closes after acceptance. Reopening the form cannot replace or duplicate
the outstanding approval. Closing a window does not cancel that approval.
Only the original local ticket's confirmed commit can queue its one broadcast.
Later source edits cannot rewrite the approved snapshot. Player, database or
catalog binding changes stop an unsubmitted intent. A changed owner cannot
broadcast a record from an already-submitted ticket. Reload does not restore
or resubmit the in-memory intent.

A Share with three ordinary copies is valid. A complete ordinary list means
that the supplied exact contents are available and consistent; it does not
mean 79 copies. The protocol has upper limits of 79 ordinary and six locked
copies. A full Mage build would not resolve occupied catalog admission.

Current contract (later correction; the limits above describe
test.9015-3551401 and are kept as history): evidence and the wire keep 79
ordinary copies and hold the locked role to resource ceilings of at most 256
rows of up to 120 copies each, with a 10000-copy total where a total is
checked; these are not server legality claims. The live occupied-record
capacity is absent from evidence and payloads. A Share plan keeps 79 / 6 / 85
as authored policy (`LoadoutEvidence.PlanLimits`). The wire format is
unchanged; older builds and peers keep their six-copy acceptance limit.
CONTRACTS.md (Occupied locked records) is authoritative.

The library first requires available, consistent ordinary evidence, then uses
scope, class and search filters. Both DPS records additionally requires a
positive Dummy record and a positive Lich King record. All Shared on that
toggle removes the DPS requirement. Highest DPS changes ordering. The disabled
scope button marks the selected scope: a disabled My Builds button means My
Builds is selected. All Shared scope includes ordinary shared records; My
Builds also includes the local owner's Saved Builds.

Three new synthetic LuaJIT regressions use the real Share form, controller,
catalog, lifecycle, incoming protocol, transport admission and library
controls. They cover contention, duplicate clicks, changed owner/database/
binding, failed ticket settlement, immutable content and three-copy listing.
They do not prove native timing, peer receipt, native UI rendering, or live
convergence. The retained 82 prototype scripts remain unchanged.

No gameplay resource use, Orb submission, installed-file patch, native test or
distribution is part of this writer correction. Existing Orb confirmation
limits remain: an ambiguous same-ID result stays pending with its spending
exposure; no retry or refund is inferred from missing confirmation.
