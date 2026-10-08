# Locked-role wire capability (#73)

Owner decision BN-OWNER-DECISION-WIRE-001 (approved compatibility policy): an
explicit capability handshake; compatible peers receive locked targets; older
peers receive ordinary targets only and the transfer is partial; locked roles
from old senders stay UNKNOWN, not zero. No capability is inferred from a
version string. This document is the protocol design recorded before the
implementation. It claims no native acceptance.

## Why a change is needed

A shared build keeps ordinary targets in `echoes` and locked targets in
`lockedEchoes` (Share and import split them). The full-build transfer
(`WLRB`, built by `SyncProtocol.CompactEncode` from `echoes` only) never
carries `lockedEchoes`. A receiver stores the build without locked targets
and cannot tell "none" from "not sent".

## Capability

| Item | Choice |
| --- | --- |
| Message | `WLCP|<sender>|<caps>|<nonce>`. `caps` is a comma list; `lv1` means "understands locked-role payload version 1". `nonce` identifies the sender's current session (6 to 16 lowercase letters or digits). |
| Released peers | test.9049 drops any unknown code before parsing (`if not peerCodes[code] then return false end`), so `WLCP` is ignored and never rejected. |
| When sent | Only together with our own state request (`WLRQ`) or loadout request (`WLLQ`), through the same control queue, the same Sync-mode checks and the same route. Once per 300 s. Again after at least 30 s when a peer that has no current entry in our table was active (at most once per peer per 900 s, so an older peer that never advertises does not keep the shorter spacing), or when a peer advertised a new nonce (it restarted and lost our capability). Never on its own schedule; Sync Off sends nothing. The advertisement uses one control-queue slot just before the request. |
| Limit | A responder that restarts loses our entry. If our table still has a current entry for it and it sends no advertisement (it makes no request, for example in Manual mode), we do not advertise again early: its answers to us are ordinary-only until our next periodic advertisement (at most 300 s). A later full answer for the same revision completes the record. |
| Accepted from | The transport sender only, and only when the message's sender field is that same sender. Malformed messages, unknown tokens and other peers' messages establish nothing. |
| Peer state | Memory only, keyed by the transport sender: `{lv=1, nonce, at}`. Lifetime 900 s from the last advertisement; at most 128 peers (the oldest is dropped). A new nonce replaces the entry and makes us advertise again. A reload clears all entries. No version string is read. The nonce is not a security token: after a peer downgrades, answers may still state the locked set for up to 900 s; released decoders ignore it. |
| Meaning | Advertised support for the representation only. It is not trusted authorship and not valid data: owner, sender, provenance, size and semantic checks stay unchanged. |

## Payload (full build, `WLRB`)

Two optional top-level keys in the existing compact JSON object:

| Key | Meaning |
| --- | --- |
| absent `lv` | Locked roles unknown (legacy form, unchanged). |
| `lv = 1` | Locked roles known. `le` is the complete locked set. |
| `le` | Array of `[spellId, quality, copies]`, only with `lv = 1`. Absent means a known empty locked set. |

- The 79 ordinary / 6 locked / 85 total envelope applies to ordinary rows plus
  `le` together. One Echo ID may appear in both roles.
- `lv = 1` together with inline slot-4 locked rows is malformed and the whole
  payload is refused. A malformed `le` refuses the whole payload.
- Any other `lv` value is treated as unknown roles (the rest of the payload is
  still used).
- Released peers ignore both keys (unknown top-level keys are not on their
  refusal list), so they store the ordinary targets only, exactly as from an
  ordinary-only payload.

Current contract (later correction; the design above is kept as history): the
79 / 6 / 85 envelope no longer bounds evidence or the wire. They keep 79
ordinary copies and hold the locked role, a stated `le` set included, to
resource ceilings of at most 256 rows of up to 120 copies each, with a
10000-copy total where a total is checked; the live occupied-record capacity
is absent from evidence and payloads. Authored Share and design plans keep
79 / 6 / 85 (`LoadoutEvidence.PlanLimits`). The wire format is unchanged;
released (test.9049) peers keep their six-copy acceptance limit and ignore a
stated `lv = 1` set, storing ordinary targets only. CONTRACTS.md (Occupied
locked records) is authoritative; no server acceptance of a combined count is
claimed.

## Who receives what

| Direction | Outcome |
| --- | --- |
| New responder, requester advertised `lv1` within 900 s, record roles known | `lv = 1` plus `le` (possibly empty). |
| New responder, requester not advertised (legacy or unknown) | The unchanged ordinary-only payload; the responder counts it as an ordinary-only (partial) response for that build. |
| Record roles unknown (for example received from a released peer) | Ordinary-only payload, whoever asks: a capable relay never reconstructs roles. |
| Unsolicited broadcast (no requester) | Ordinary-only payload. |
| Released responder to a new requester | Ordinary-only payload; the new receiver stores roles as unknown. |

The route is the existing one (addon whisper to a confirmed requester,
otherwise the channel). A channel response can be overheard: released
listeners ignore the new keys; new listeners use them because the payload
itself states the roles.

## Receiver record states

| State | Stored as |
| --- | --- |
| Known, non-empty | `lockedEchoes` = the rows, `lockedAuthorityProven = true` |
| Known empty | `lockedAuthorityProven = true`, no locked rows (the catalog keeps no empty evidence array) |
| Unknown | neither field |

- A same-revision full payload (same id, same `lastModified`, same ordinary
  fingerprint) may enrich a stored record whose roles are unknown.
- A same-revision ordinary-only payload never erases known roles (it is a
  duplicate, as today).
- A newer revision replaces the record; it never inherits the previous
  revision's locked rows.
- Promotion to the owner's verified record: locked roles that only a relay
  stated are not carried into the owner-verified record when the owner's
  own answer does not state them (they become unknown); the owner's full
  answer then completes it. Provenance comes first.
- Held admission: when the owner's ordinary-only answer and then its full
  answer for the same revision (same content) both wait in the admission
  queue, the full answer replaces the held partial one. A held full answer
  is never replaced by a partial one. The content digest does not include
  the role state.
- Copy into Editor is unchanged and conservative: a known empty set without
  rows is not taken as "none" there (the resolver needs rows or its own
  evidence), so it stays unavailable rather than zero.
- Copy authority still comes from the existing resolver
  (`CandidateEvidence.ResolveLocked` / `CurrentCopyAuthority`): known roles of
  a verified owner are used; unknown roles are not turned into zero.

## Local sources

- Share and import already split roles. A record with locked rows states its
  roles (the rows are the complete stated set). A local source without locked
  rows is sent with roles UNKNOWN: under the existing role contract an absence
  of stated locked rows (including a server mirror whose rows are all
  `locked=false`) is not role evidence, so nothing claims "none".
- A known empty set is sent only when a record already holds one
  (`lockedAuthorityProven = true`, no rows); a new receiver keeps it intact.
- "Update from Wishlist" now splits roles with the same Share role reading.
  Before, it copied every Wishlist entry into `echoes` and kept the previous
  `lockedEchoes`, so a role change was lost and stale rows would travel.

## User-requested completion (Request full build)

A remote build of a verified owner can keep unknown roles at an unchanged
revision (for example after an unsolicited broadcast). Leaderboard Copy then
stays unavailable: historical DPS record rows never prove current locked
roles. The Leaderboard detail offers "Request full build" for exactly that
case (`Sync.RequestLockedRoles`):

- One click queues one exact-ID loadout request (`WLLQ`) through the existing
  recovery queue, Sync-mode checks and route. Our capability (`WLCP`) is
  always stated just before it, because the owner may have restarted since
  our last advertisement.
- Only the owner's own same-revision full answer completes the record in
  place (the existing "roles" acceptance); a relay's answer stays refused.
- Refused requests (Sync Off, Manual without Sync Now, not connected, own,
  unknown or unverified build, known roles) send nothing and say why.
- The state is pending until roles arrive, or timeout 60 s after the actual
  send (a busy queue may hold the request first). Reading the state never
  sends; nothing retries by itself; a new request needs a new click.

## Not changed

Bucket tokens, summaries (`WLBI`) and ordinary fingerprints. A record stored
with unknown roles at an unchanged revision is enriched only when a full
response for it arrives; no new periodic traffic is added for that.

## Evidence

The released peer in the tests runs verbatim test.9049 source files
(`tests/prototype/fixtures/released_9049/`, copied from commit 27aaeec; see its
MANIFEST).
