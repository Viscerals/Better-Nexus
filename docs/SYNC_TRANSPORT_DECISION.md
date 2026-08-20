# Sync transport decision record

Status: accepted for Stage 24.7
Decision date: 2026-08-11
Decision scope: read-only comparison; no runtime, wire, dependency, or
SavedVariables change

## Decision

Keep repairing the current Nexus mesh. Do not replace it with LibP2PDB,
AceComm, or DeltaSync at this stage.

The present transport is the only candidate in this review with direct offline
evidence for Nexus's WoW 3.3.5a runtime, existing wire compatibility, bounded
resource behavior, author ownership, tombstones, and mixed-version recovery.
The reviewed libraries contain useful transport ideas, but none is a compatible
drop-in for those product rules.

This is an offline architecture verdict, not a claim that current two-client
delivery or addon-whisper reachability has passed an in-game test.

A channel-for-discovery plus whisper-for-directed-payload design remains the
best future experiment. It is deferred until the target server's addon-whisper
behavior is proved live and until coexistence with older Nexus clients is
designed. If a library is evaluated later, it must sit behind the existing
`SyncTransport`/`SyncInbound` boundaries; Nexus remains responsible for schema,
ownership, tombstones, admission, and resource limits.

## Method and claim labels

- **Source fact** means the claim is visible in the cited publisher page or in
  licensed source at the recorded revision.
- **Nexus fact** means the claim is visible in this repository at product head
  `3ed0ec845469fe07c2a79f59a1c0fbbd3b4f2c0b` or its offline tests.
- **Inference** means a design conclusion drawn from those facts. It is not a
  claim of live server behavior.

No third-party source was copied. Reference implementations were read only.

## Compatibility matrix

| Candidate | Runtime and reach | Framing and backpressure | Data policy and hostile-input boundary | Dependency, license, and migration verdict |
| --- | --- | --- | --- | --- |
| Current Nexus mesh | **Nexus fact:** uses the 3.3.5a-era global chat APIs, a named shared channel for discovery and payloads, and the established Nexus wire. Channel numbers are re-resolved before sends. **Inference:** widest current reach on the target runtime, but broadcast payloads create more aggregate receive work than directed delivery. | **Nexus fact:** explicit bounded control/bulk queues, atomic batch admission, conservative pacing, retry-on-send-failure, transfer count/byte/age limits, bounded responder work, and matching-hash silence. | **Nexus fact:** validates sender, envelope, schema, ownership, tombstones, and relay context before persistence. Offline suites cover queue pressure, mixed versions, ownership, tombstones, convergence, and deterministic hostile traffic. | No new dependency or license obligation. Existing wire and SavedVariables remain unchanged. **Selected:** repair in place and preserve current facades. |
| LibP2PDB v14 | **Source fact:** publisher lists Lua 5.1 and Retail/MoP/Classic/TBC, not WoW 3.3.5a. Source uses modern `C_ChatInfo`, `C_Timer`, `GetTimePreciseSec`, modern group helpers, and a modern player-GUID shape. It discovers through guild/group/yell broadcasts and chooses whisper neighbors. **Inference:** source adaptation, not configuration, would be required for this client. | **Source fact:** delegates multipart delivery to AceComm, paces row chunks, and yields database import work. Its receive path decodes, decompresses, and deserializes before row import; this review found no application-level compressed/decompressed byte cap in v14. | **Source fact:** provides schema callbacks, Lamport ordering, exclusive/immutable rows, tombstones, peer-ID/name verification, and migrations. Those semantics do not match Nexus's author-owned records and tombstone rules without a mapping and dual-read migration. | MIT, with copyright and permission notice required. Hard dependencies include AceComm and LibBucketedHashSet; serialization/compression implementations are also required in practice. **Rejected now:** incompatible APIs, a large semantic migration, and unresolved receive-size policy. |
| AceComm-3.0 plus ChatThrottleLib | **Source fact:** transports over a caller-selected WoW addon-message distribution; it does not discover peers or define reachability. Current AceComm retains an old registration fallback, but current ChatThrottleLib sends through modern `C_ChatInfo`. **Inference:** the reviewed current revision is not a 3.3.5a drop-in; a separately pinned legacy-compatible revision would need proof. | **Source fact:** AceComm splits and reassembles arbitrary-length strings; ChatThrottleLib supplies priority and shared traffic shaping. AceComm's multipart spool has no application payload cap or expiry and explicitly retains a timeout TODO. | No schema, identity authority, ownership, tombstone, reconciliation, or decompression policy. Those must stay in Nexus. A send callback reports chunks leaving the local queue, not peer persistence. | Ace3's source license and packaging conditions must be retained and reviewed; the publisher recommends referencing only the libraries used. ChatThrottleLib is separately distributed. **Deferred as a facade-only experiment:** useful framing/throttling, but not a policy engine and not current-client compatible as inspected. |
| DeltaSync v4.0.3 | **Source fact:** publisher lists current Retail and Classic-family versions, not WoW 3.3.5a. It uses guild-roster discovery, guild announcements, and directed whisper data; an opt-in guild-mode exists for servers where addon whispers fail. | **Source fact:** uses AceComm/AceSerializer plus AceCommQueue, checks message integrity, provides timeouts, delta/full fallback, send-failure reporting, and multi-host isolation. Current packaging declares three hard dependency families. | **Source fact:** the host supplies merge/application callbacks. Publisher guidance says content-aware consumers still implement merge semantics. No evidence reviewed shows Nexus-equivalent author/tombstone policy or the required external decompression/schema limits. | MIT, plus Ace3, AceCommQueue, and LibGuildRoster obligations. **Rejected now:** unproved old-client APIs, dependency weight, seven prefixes per host, and a full wire/state-policy migration. Useful future reference for directed catch-up and diagnostics only. |
| WeakAuras transmission reference | **Source fact:** current licensed source sends user-selected payloads by whisper, uses throttled multipart transports, and tracks expected senders while the receiving UI is active. | **Source fact:** it compresses/encodes before transport, decompresses/deserializes on receipt, and uses bulk data plus separate progress messages. | It is a user-initiated transfer workflow, not a distributed database. It offers no reusable Nexus ownership, tombstone, or convergence semantics. | GPL-2.0. **Pattern only:** direct payload delivery and explicit receive context are useful; no source may be copied into Nexus without a separate license decision. |
| Total RP 3 communication reference | **Source fact:** current Apache-2.0 source separates a broadcast protocol from peer-to-peer messages, caps broadcast messages, and sends directed peer messages by whisper through Chomp. Its current implementation uses modern client feature gates and APIs. | **Source fact:** Chomp owns multipart/priority transport; TRP3 compresses structured messages and uses a small broadcast surface for reach/discovery. | Application subsystems still own acceptance and data meaning. The transport does not provide Nexus's author/tombstone rules. | Apache-2.0. **Pattern only:** strongest established example for a future discovery-channel/directed-payload split; current source is not evidence of 3.3.5a compatibility. |

## Detailed verdicts

### WoW 3.3.5a and Lua 5.1

Lua 5.1 compatibility alone is insufficient. LibP2PDB v14 explicitly claims
Lua 5.1, but its source and manifest rely on APIs and client versions newer
than the target. DeltaSync's published support list likewise excludes 3.3.5a.
The current AceComm source contains some compatibility branches, but its bundled
ChatThrottleLib send path is modern. WeakAuras and Total RP 3 are architecture
references, not old-client candidates.

Therefore, no external candidate receives a compatibility PASS. A future
prototype must load, join/discover, send, receive, reconnect, and throttle on an
actual 3.3.5a client before it can affect the Nexus transport decision.

### Reachability and discovery

The current named channel supplies discovery and payload reach without a guild,
party, or raid dependency. LibP2PDB expands broadcasts across several social
distributions and then chooses neighbors. DeltaSync is primarily guild-roster
based. AceComm and ChatThrottleLib provide transport only. WeakAuras assumes a
known recipient. Total RP 3 demonstrates the useful separation between a
shared discovery/broadcast surface and directed peer messages.

The hybrid is promising because a small discovery summary can remain broadly
reachable while larger responses target one requester. It is not selected now:
addon-whisper delivery on the target server is unproved, and directed traffic
must coexist with clients that only understand the present channel wire.

### Sender, ownership, and tombstones

Transport sender identity is only one input to Nexus authority. Nexus also
binds author-owned records, prevents unauthorized replacement, preserves
tombstones, and keeps relay evidence distinct from direct-owner evidence.

LibP2PDB's Lamport/exclusive-row model and DeltaSync's host-defined merge model
are reasonable general policies, but neither is equivalent. AceComm,
ChatThrottleLib, Chomp, and the WeakAuras transmission layer deliberately do
not make application ownership decisions. Delegating persistence directly to
any candidate would therefore be a correctness regression.

### Fragmentation, backpressure, and frame time

AceComm/ChatThrottleLib and Chomp provide mature multipart traffic shaping.
DeltaSync builds more session and integrity behavior on top. LibP2PDB also
spreads import work across frames.

Those benefits do not replace receive limits. Generic unlimited multipart
reassembly or decompression before an application bound can enlarge memory and
frame-time risk. Any future facade must retain Nexus's bounded admitted queues,
inflight count/byte/age limits, validated decode tree, response headroom, and
incremental reconciliation. Library callbacks must be interpreted as local
transport outcomes, not peer storage confirmation.

### Delta behavior and old clients

All database candidates have some delta or hash comparison, but a matching
label does not imply a matching canonical hash, bucket layout, tombstone set,
owner rule, or conflict order. Replacing the algorithm would create a new
protocol even if the outer transport remained unchanged.

The existing wire remains authoritative. Older clients must continue to use it
without receiving new envelopes they cannot parse. Any later experiment must
be additive, version-negotiated, and able to fall back to the present path.

### License and packaging

This repository has no root license or third-party notice inventory at the
reviewed head. That does not prevent research, but it makes dependency adoption
a separate release decision.

- LibP2PDB and DeltaSync are MIT; distributed copies require their notices.
- Ace3 carries its own redistribution conditions; only needed sub-libraries
  should be referenced and all required notices retained.
- WeakAuras is GPL-2.0 and is used only as an architectural reference here.
- Total RP 3 is Apache-2.0 and is also used only as a reference.

No library source, notice, or runtime file is added by this decision.

## Future migration gate

The decision may be reopened only when all of these are available:

1. Byte-matched two-client evidence for addon whisper delivery, reconnect, and
   throttling on the target 3.3.5a server.
2. A pinned transport/dependency source revision that parses and runs on the
   target client, with a complete notice inventory.
3. A facade design that preserves current wire messages, canonical hashes,
   author ownership, tombstones, validation, diagnostics, and SavedVariables.
4. Coexistence tests where old clients continue on the current channel while
   capable clients try directed payloads without duplicate persistence.
5. Receive-side byte/count/time/decompression bounds and frame-time stress
   evidence equal to or stronger than the current gates.
6. A rollback that removes the experimental route without data conversion or
   SavedVariables rollback.

Until those gates pass, the operational choice is repair, not replacement.

## Source record

Primary publisher pages and directly inspected licensed sources:

- Nexus source at `3ed0ec845469fe07c2a79f59a1c0fbbd3b4f2c0b`:
  `core/Sync.lua`, `core/SyncTransport.lua`, `core/SyncProtocol.lua`,
  `core/SyncInbound.lua`, `core/SyncReconciler.lua`, `core/SyncSession.lua`,
  `core/MainLifecycle.lua`, and their offline suites.
- LibP2PDB v14 publisher page:
  <https://www.curseforge.com/wow/addons/libp2pdb>
- LibP2PDB v14 source and MIT license, inspected at
  `95a653a40048338fb8c842f16522c31522b1a97c`:
  <https://github.com/erunehtar/LibP2PDB/tree/95a653a40048338fb8c842f16522c31522b1a97c>
- Ace3 documentation:
  <https://www.wowace.com/projects/ace3/pages/api/ace-comm-3-0>
- AceComm-3.0, ChatThrottleLib, and Ace3 license, inspected at
  `7321b063f79a5487df212e904124ac2b4d71d866`:
  <https://github.com/WoWUIDev/Ace3/tree/7321b063f79a5487df212e904124ac2b4d71d866/AceComm-3.0>
- DeltaSync v4.0.3 publisher page and release:
  <https://www.curseforge.com/wow/addons/deltasync>
  and <https://www.curseforge.com/wow/addons/deltasync/files/8572153>
- WeakAuras transmission source and GPL-2.0 license, inspected at
  `9aab8786e79ac07acf6b246c1712d12d3b18e77d`:
  <https://github.com/WeakAuras/WeakAuras2/blob/9aab8786e79ac07acf6b246c1712d12d3b18e77d/WeakAuras/Transmission.lua>
- Total RP 3 communication source and Apache-2.0 license, inspected at
  `e810774d9f39fe930a67a18a375a983bfc9c3ec8`:
  <https://github.com/Total-RP/Total-RP-3/tree/e810774d9f39fe930a67a18a375a983bfc9c3ec8/totalRP3/Core>

This record intentionally excludes private logs, identities, packet captures,
and operational abuse details.
