# Stop Sharing result handling

The Stop Sharing confirmation now reports the local catalog result separately
from withdrawal queue admission. A busy refusal has readable text and keeps
the shared record. An accepted local ticket reports that removal is pending.
Only its committed result can report that the record stopped sharing locally.
The terminal callback reports a failed ticket without retrying it.

Sync retains ownership of its original catalog completion callback. Its first
three BroadcastDelete return values keep their existing meaning. A fourth
local-removal receipt and optional completion notification let the controller
observe that same ticket. The controller does not submit a fallback removal
when Sync already owns an accepted local ticket. Other supported callers can
still use the existing controller-owned local fallback.

Queue admission and a pending queue retry do not prove local removal. Local
removal does not prove peer removal. The shipped adapter still refuses remote
withdrawal with REMOTE_TOMBSTONE_ORDER_UNPROVEN and sends no withdrawal bytes.
Raw catalog and protocol reason codes remain in operation receipts. The normal
panel presents a readable reason for catalog preparation and unsupported remote
withdrawal. No admission rule, catalog slice, owner guard, retry policy, or
resource path is changed.

Three regression scripts use real Stop Sharing controls and exact-ID
confirmation, the controller, catalog tickets and normal lifecycle. They cover
busy refusal, Sync-owned pending removal, committed local removal, cancellation,
changed owner, and compatibility queue outcomes. Compatibility queue cases
replace only the Sync return at the boundary; they do not claim the shipped
protocol supports remote withdrawal. The existing prototype scripts stay
unchanged. All validation is synthetic and offline. Native result text and
terminal cleanup must be observed separately after a user-approved installation.
