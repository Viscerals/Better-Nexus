# Echo choice and Orb diagnostic evidence

The support summary and prepared report separate three sources. An ordinary
Echo choice may exist while the Orb service is idle and the runner has never
started. None of these fields proves ownership, a successful roll or server
freshness.

## Observation contract

- `Echo choice` records the existing `GameAdapter.Board()` or Orb adapter
  `GetCurrentChoice` read. No additional native read is made. A plain dense
  response containing one to three valid spell-ID rows is `present`; a plain
  explicit empty table is `absent`. Nil, errors, missing APIs and malformed
  responses are `unknown`. In the authorized inert ProjectEbonhold metadata v37
  source (`THIRD_PARTY.md` records the SHA-256 and `GetCurrentChoice`/opcode16
  symbols), the cache can be nil after empty or unparseable replies. This does
  not verify the installed tester/client version; nil alone cannot establish absence.
- `observedAt` is whole client uptime seconds, not UTC. `age` is elapsed client
  time since that evaluation. `recent` means at most one client second old;
  it is a diagnostic sampling bound, never an action or server-response gate.
  A stale sample, unavailable/regressed clock, interrupted/blocked Orb Status
  read, world leave/entry or logout cannot assert current absence/presence.
  `lastPresence`, `lastCount` and `lastReason` preserve the sampled historical
  result, even when the current reason is `stale` or `transition`.
  `read_blocked` is conservative: an Orb Status read that refuses before reaching
  the choice getter also invalidates a previous ordinary Board sample. It does
  not establish that the ordinary choice getter itself failed.
- `sampleEpoch`, `currentEpoch` and `world` come from events received by the
  existing Main dispatcher since this addon load. They do not identify a
  server session or prove that a service mirror has hydrated after loading.
  Only a subsequent ordinary read records a sample in the new epoch.
- `Orb service` records the existing classifier, preserving its return values
  and arity. Only a recent `IDLE` result establishes `offer=absent`; `PENDING`
  establishes present. Unknown, invalid, missing or malformed capability is
  unknown. `status` and `lastOffer` remain the last normal read's facts.
- `Orb runner` reads initialized session memory without constructing a runtime,
  querying saved data, starting observers, sending or saving. Its receipt is
  unknown before initialization. State codes distinguish deliberate Stop,
  completion, resource exhaustion, no safe sources and recovery. They do not
  imply ordinary choice absence. The Orb-owner lifecycle epoch is unavailable
  until that owner's frame exists; it is distinct from Main's world context.
  The separate legacy recovery section may still restore a known saved
  receipt for early reporting, as before. An empty uninitialized runtime is
  not constructed merely to inspect Continue or empty history.
- Boundary comparisons are retained evidence. `changed_age` dates the stored
  comparison; `read_age` dates the latest successful ordinary comparison read
  even if values stayed stable. A failed read clears that read time to unknown
  while retaining the older comparison; unknown does not distinguish a failed
  read from a missing clock or no prior read. `scope=retained current=no` applies
  after completion too.

The views return detached scalar tables. No raw API error, card contents,
player identity or payload is retained in the new block. The report formats
fixed keys/codes. A prepared report is frozen when built: its printed ages do
not tick afterward. Rebuilding a report does not refresh native state.

## Scope and remaining gaps

The diagnostics work is tracked in [#127](https://github.com/Viscerals/Better-Nexus/issues/127).
The following boundaries describe the implementation, independently of any
particular review or validation run.

| Area | Disposition in this change |
| --- | --- |
| Ordinary choice and error/absence conflation | Existing-read sampling, tri-state presence, reason and age. Nil stays unknown. |
| Orb-service capability and offer state | Separate passive classifier sample and freshness. |
| Runner state omitted without a receipt | Pure runner view and uninitialized report guard. A hypothetical nil Store result is not asserted as a production defect. |
| Retained comparison age | Changed/read ages and an explicit retained/not-current label. |
| Lifecycle observer scope | Main observation context plus explicit Orb-owner observer availability. No gameplay epoch change. |
| Recovery slot/pick ages and Continue refusal breakdown | Deferred; new choice block must not be used to reinterpret an older receipt. |
| Other action-latch history | Deferred; no latch watchdog or dead-latch behavior change. |
| General log-export purity and charge wording | Deferred to a separate log-export audit. This change covers support-report evidence only. |
| Echo rejection export and roll-trace schema | Deferred; no trace schema/Sync changes. |
| Continue-view side effects | Empty uninitialized reports skip Continue/history constructors. Existing saved-receipt restoration and initialized Continue-view behavior are preserved and deferred. |
| Board fingerprint comment/behavior and export privacy alignment | Deferred, outside this diagnostic slice. |

## Verification and limits

Regression fixtures cover idle/stopped runners with an open choice; explicit
empty, nil, malformed, missing and raising APIs; clock loss/regression; old and
transition-invalidated samples; unknown Orb service states; report collection
without native reads/runtime initialization; and retained completed-operation
comparisons. Existing purity, ownership, transition and report guards remain
required, followed by the complete registered suite.

The additions use bounded scalar samples and at most four raw choice-key checks;
there is no new frame, timer, polling loop, network message or saved schema.
CPU/frame cost is not measured. Native API empty-response semantics, live loading
behavior and clipboard/export bytes have not been tested here. This diagnostics
PR does not diagnose or fix a particular live Orb failure, add retry policy,
automatically resume a run, merge code or publish a build.

The separate bounded live recovery path now consumes admitted exact empty-choice
response evidence, not this diagnostic sample. Its transport status additionally
exposes bounded scalar `choiceObserver`, `ownBare` and `ownFramed` facts; report
collection installs no hook and performs no gameplay read. Its outgoing observer
is installed only by the live owner. Nil stays unknown, retained sample ages
stay frozen, and none of these support views grants permission. See
`ORB_BOUNDED_RECOVERY.md` for query effects and native compatibility limits.
