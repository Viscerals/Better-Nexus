# Better Nexus modular-refactor characterization

Branch baseline: `5cbe8ac53b3a06398e4241d6ee1d048aa693c246`.
Through Checkpoint 10.5 this work adds characterization only; runtime remains byte-identical to
the reviewed 10.2 head `8bcdc0cf6a18c2d3da2a41c207a5d187f227da45`.

This is the canonical map for the staged refactor. The machine-readable symbol
and callback inventory lives in `tests/module_contract_manifest.lua`; the
fixture `tests/run_module_contract_characterization.lua` fails when source and
the inventory diverge.

## Reading the matrices

State/authority codes:

- `TX`: channel and accepted outbound queues; `RX`: receive windows, inflight,
  reconciliation, pending responses; `SV`: `NexusDB`; `GA`: Project Ebonhold or
  WoW reads/actions; `AUT`: Main automation/FSM state; `UI`: frames and
  controller session state; `DG`: bounded diagnostics/counters; `CAT`: build,
  DPS, evidence, and revision facades; `-`: no owned mutation.
- Failure abbreviations: `reject` returns false/nil without committing; `noop`
  safely does nothing before readiness; `isolate` records/contains callback
  failure; `last-good` retains the previously published value.
- Coverage codes: `S-Q` Sync backpressure/transport safety; `S-W` wire and
  compatibility; `S-M` mesh/convergence/ownership; `S-D` Sync diagnostics;
  `S-C` Sync facade characterization; `ST` Store migrations; `ST-C` Store
  persistence characterization; `M-C` Main coordinator characterization;
  `A-X` GameAdapter boundary characterization; `F-A` freeze attribution;
  `C-C` Community facade characterization; `W-C` Wishlist facade
  characterization; `A-I` 70-check automation integration; `A-C` catalog;
  `A-W` wishlist/association; `C-UI` Community suites; `W-UI` Wishlist suites;
  `BOOT` full boot. Every row has executable coverage; deferred live checks
  are listed separately and are not represented as missing offline parity.

Inventory total: eleven modules, 191 unique callable surfaces, 14 unique assigned
namespace members, and 156 callback sites grouped into 17 behavioral owners,
zero unmapped.

Assigned members are inventoried separately because a namespace assignment can
publish a callable alias, expose a constant, or own mutable state without using
a `function Namespace.Name(...)` declaration.

| Assigned member | Assignment class | Owner/invariant |
| --- | --- | --- |
| `Sync.LogEvent` | `callable-alias` | Sync publishes the one bounded diagnostic append path. |
| `Sync.BroadcastBuildSummary` | `callable-alias` | Sync publishes the established bounded compatibility-summary sender. |
| `Sync._pendingDeleteScheduled` | `mutable-state` | Sync alone owns delete retry scheduling. |
| `Nexus.VERSION` | `constant` | Main exposes Release metadata without owning release publication. |
| `Nexus.lastError` | `mutable-state` | Main owns only the fallback last-error projection. |
| `Nexus.RequestRecompute` | `callable-alias` | Main exposes the one force-recompute latch. |
| `Nexus.RetryAutoLock` | `callable-alias` | Main exposes one explicit user-authorized retry for a retained rejected or expired AutoLock identity. |
| `Nexus.AppendAudit` | `callable-alias` | Main exposes the bounded diagnostic audit append path. |
| `Nexus.lastLagElapsed` | `mutable-state` | Main owns the latest direct-loop lag scalar. |
| `A.DIAGNOSTIC_PASSIVE` | `constant` | GameAdapter publishes the passive-diagnostics contract. |
| `A._wishlistNote` | `mutable-state` | GameAdapter owns the represented association note. |
| `A._pendingWishlistSlot` | `mutable-state` | GameAdapter owns the pending saved-loadout association slot. |
| `A._pendingWishlistAt` | `mutable-state` | GameAdapter owns the pending association deadline origin. |
| `A._lastUserAction` | `mutable-state` | GameAdapter owns the consumed external-user-action latch. |
| `M._fulfilledDraftTargets` | `mutable-state` | WishlistEditor preserves the established diagnostic alias to controller-owned fulfilled draft targets; no SavedVariables authority. |

## Load order and ownership

The relevant `Nexus.toc` order is:

1. `core/CandidateEvidence.lua`
2. `core/Store.lua`
3. `core/WishlistModel.lua`
4. `core/WishlistController.lua`
5. `core/SyncProtocol.lua`
6. `core/SyncTransport.lua`
7. `core/SyncCompatibility.lua`
8. `core/SyncReconciler.lua`
9. `core/SyncInbound.lua`
10. `core/SyncDiagnostics.lua`
11. `core/SyncSession.lua`
12. `core/Sync.lua`
13. `core/CommunityProjection.lua`
14. `core/CommunityController.lua`
15. `core/GameAdapter.lua`
16. `ui/WishlistRenderer.lua`
17. `ui/WishlistEditor.lua`
18. `ui/CommunityRenderer.lua`
19. `ui/CommunityBuilds.lua`
20. `core/AutomationRuntime.lua`
21. `core/MainLifecycle.lua`
22. `core/MainCommands.lua`
23. `core/MainViewModel.lua`
24. `core/MainDiagnostics.lua`
25. `core/Main.lua`

CandidateEvidence registers one pure typed builder/validator before any
candidate producer or consumer. It receives copied arrays, scalar identity and
revision evidence, and an optional read-only revision callback; it owns no
frames, persistence, GameAdapter access, automation, or action state.
Store therefore cannot require Sync, GameAdapter, or UI at load time.
WishlistModel registers one stateless constructor before WishlistEditor and
receives captured catalog, locked, committed-target, draft, class, and name
values only; it calls no Store, Adapter, Codec, frame, print, transport, or
gameplay owner.
WishlistController registers one frame-free constructor after WishlistModel.
The editor injects the live Store, Adapter, account-root reader, notifications,
and Community navigation intention; the controller owns mutable draft/session,
filter/scroll, exact association, Store commit, upload, and bounded retry state.
WishlistRenderer registers before WishlistEditor and consumes only controller
projections plus facade presentation callbacks; it creates the main editor,
switch menus, tooltips, and fixed available/pending row pools.
SyncProtocol registers a pure internal constructor and owns no runtime state;
SyncTransport registers the sole durable outbound queue constructor and owns no
planning, persistence, or gameplay state. SyncCompatibility registers the
read-only compatibility/hash/summary/candidate constructor and owns only derived
candidate-cache state. SyncReconciler registers the sole pending-response,
fairness, expiry, and response-stat owner; it processes at most one expensive
response unit per update and owns no transport, persistence, or represented
data. SyncInbound registers the sole build/DPS inflight owner and preserves
synchronous arrival order while invoking only validated commit callbacks; it
owns no transport, persistence, catalog, ownership, or gameplay mutation.
SyncDiagnostics owns bounded event history, the established live counter table,
and defensive scalar-only work/status projections; it calls no runtime owner.
SyncSession owns recognized peers, receive windows, bounded legacy recovery,
login/manual convergence, join retry, and developer status-reply state. Its
update methods are invoked in the established order and create no second
transport or inbound path.
Sync injects callbacks into one instance of each internal module. Sync may see
DpsCapture, ViewProjections, or GameAdapter as unavailable until Main has
finished initialization. Both UI modules may create closures before Main binds
their Adapter/Model dependencies. MainCommands registers the pure normalized
slash router, invokes one injected callback per initialized command, and owns
no slash globals or product authority. MainViewModel registers the pure progress,
defensive copy, immutable HUD projection, and value-keyed HUD-cache owner.
MainDiagnostics registers one passive constructor and owns no frame, gameplay
mutation, transport queue, or database root. AutomationRuntime owns the
arm/run/save state, known deadlines, retry latches, policy coordination, and
direct 0.2-second safety poll. MainLifecycle owns initialized state, ordered
boot/event/per-frame routing, lag observation, and optional scheduler/view
initialization. Main loads last, creates exactly one of each stateful owner,
keeps frame/event/slash registrations and public delegates, and retries through
Lifecycle when a required facade is missing.

`Nexus.toc` continues declaring exactly
`## SavedVariables: NexusDB WishlistRealizerDB`. Store owns binding and ordered
initialization of `NexusDB`; no UI or transport module owns the database. Sync
may commit accepted builds, DPS, and tombstones only through their established
validated facades. GameAdapter alone reads or mutates Project Ebonhold gameplay
services. MainLifecycle routes the direct update beat to AutomationRuntime
behind Main's unchanged coordinator facade.

Cross-module edges that later extraction must retain:

| From | To | Edge and ownership |
| --- | --- | --- |
| Main | MainLifecycle | Main retains exact frame/event/slash registrations and delegates event/update/initialized-state work to one Lifecycle instance. |
| MainLifecycle | Store | `Store.Init()` must succeed before Lifecycle initializes later persistent/runtime owners; the post-Store database identity is passed onward. |
| Main | AutomationRuntime | Main injects the established Model/Policy/Ratchet/Strategy/Store/GameAdapter dependencies once; Runtime solely owns automation state, deadlines, policy coordination, and action submission. |
| MainLifecycle | AutomationRuntime | Lifecycle routes the direct update beat and explicit refresh through the single Runtime instance. |
| AutomationRuntime | GameAdapter | Direct `Poll()`, live safety/authorization reads, and all arm/run/save gameplay mutations remain behind GameAdapter. |
| MainLifecycle | GameAdapter | `Adapter.Init(callbacks, Store)`, readiness, world/level events, and direct per-frame routing remain ordered by Lifecycle. |
| Main | GameAdapter | Explicit established slash-command reads/actions remain coordinated by Main. |
| Main | MainCommands | Main retains the three slash globals and injects existing command actions; Commands owns normalization, aliases, prefix arguments, and exactly-one callback dispatch with no product authority. |
| Main | MainDiagnostics | Main delegates retained audit formatting, page text, selective clear routing, and incremental export construction through unchanged public facades; Diagnostics receives only the required GameAdapter reads and owns no gameplay or transport path. |
| Main | MainViewModel | Main captures live adapter/status/update/DPS values, then delegates exact progress math, defensive copying, value-keyed HUD reuse, and immutable display projection; ViewModel receives no service or gameplay callback. |
| WishlistEditor | WishlistController | Editor assembles one model/controller/renderer chain, retains confirmation/import/export popup intentions, and delegates every draft/session/filter/scroll/association/apply/retry transition while preserving public facade identities. |
| WishlistEditor | WishlistRenderer | Facade injects controller projections, overlay access, and presentation intentions; Renderer alone owns the main editor frame, display popup, switch menus, tooltips, scrolling, and fixed visible-row binding. |
| WishlistController | WishlistModel/Store/GameAdapter | Controller delegates pure calculations to one model, persists lock designs only through Store-owned state, and performs uploads/associations only through the injected GameAdapter facade at mutation time. |
| Community/Leaderboard/WishlistController | CandidateEvidence | Both producers build the same immutable ordinary/locked contract; the controller validates that contract again before draft or action authority. |
| MainLifecycle | Sync | Lifecycle routes channel/whisper events and calls `Sync.OnUpdate`; the public Sync facade delegates outbound state to one SyncTransport instance. |
| Sync | SyncProtocol | Sync delegates stateless wire validation/splitting and compact payload transforms; Protocol owns no mutation path. |
| Sync | SyncTransport | Sync delegates all accepted bulk/control admission, pacing, throttle, and channel sends; Transport owns no planning, represented data, persistence, or gameplay state. |
| Sync | SyncCompatibility | Sync delegates compatibility hashes, fingerprints, compact summaries, and revision-keyed candidate views; Compatibility owns no admission, ownership, represented mutation, persistence, or gameplay state. |
| Sync | SyncReconciler | Sync delegates pending requester/loadout ownership, fair bounded progression, expiry, and post-admission claim timing; candidate currency and live tombstone ownership are rechecked before claim suppression/publication, and Reconciler owns no wire parsing, accepted queue, represented mutation, persistence, or gameplay state. |
| Sync | SyncInbound | Sync delegates synchronous recognized-code dispatch, sender validation, build/DPS chunk assembly, caps, and expiry; Inbound invokes narrow validated callbacks and owns no queue, represented mutation, peer authority, persistence, or gameplay state. |
| Sync | SyncDiagnostics | Sync delegates bounded history, live session counters, and defensive scalar aggregation; Diagnostics reads supplied snapshots only and owns no queue, represented data, persistence, or gameplay path. |
| Sync | SyncSession | Sync delegates peer presence, receive windows, bounded legacy recovery, login/manual convergence, join retry, and status replies; Session admits only through the injected transport facade and owns no wire parsing or represented mutation. |
| Main | Community/Wishlist | Main initializes and routes slash/UI entry points; UI owns frames/session state. |
| Sync | Codec/BuildCatalog/DpsCapture | Parse/validate first, then commit through established data owners. |
| Sync | GameAdapter | Read-only local identity/loadout evidence; never direct Project Ebonhold globals. |
| Community | CommunityProjection/BuildCatalog | Compose the existing list cache with one exact selected-detail snapshot and hydrate only bounded visible records. |
| CommunityBuilds | CommunityRenderer | The facade injects defensive readers and controller intentions; Renderer alone owns main/detail/post/edit frames, callbacks, and pooled visible-row binding. |
| Community | Sync/WishlistEditor | Request Sync or open editor; does not own queues or wishlist persistence. |
| Wishlist | GameAdapter/Model/Community | Controller requests validated adapter operations and navigation; render owns no transport. |

## `Nexus.CandidateEvidence` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Evidence.Build` | Normalize and bind immutable typed ordinary/locked candidate evidence | Community/Leaderboard/tests | copied arrays + scalar identity/selected-evidence token -> candidate-local snapshot | bounded fail closed above 79 ordinary copies, six locked copies, or invalid/dense evidence | W-C/W-UI |
| `Evidence.Validate` | Revalidate supported current/legacy candidate contracts immediately before use | Community/Leaderboard/WishlistController/tests | candidate-local snapshot + selected-evidence or legacy revision callback -> defensive snapshot | unsupported, mutated, stale, malformed, or unavailable evidence rejected | W-C/W-UI |
| `Evidence.ResolveLocked` | Resolve one exact category-aware locked-Echo authority without global reads | Community/Leaderboard/Wishlist/Peer Debug/tests | selected ordinary/build identity + bounded category or inline records -> defensive locked result + scalar diagnostics | incomplete ordinary data, malformed claims, identity mismatch, or category disagreement fail closed | W-C/W-UI |
| `Evidence.CurrentKind` | Publish the current typed candidate contract identifier | tests/diagnostics | constant -> string | none | W-C |
| `Evidence.NormalizeLockedEchoes` | Normalize one typed locked-role pool and enforce the six-copy envelope | Wishlist/tests | dense locked rows -> defensive exact rows with counts, future fields, and provenance | malformed rows or more than six total copies fail closed | W-C/W-UI |

## `Nexus.WishlistModel` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Factory.New` | Construct one stateless Wishlist calculation owner | WishlistEditor/tests | captured plain values -> immutable draft/export/commit plans | defensive empty/no-op | W-C/W-UI |

## `Nexus.WishlistInternals.Controller` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Controller.New` | Construct the sole Wishlist draft/session/action owner | WishlistEditor/tests | injected Model/Store/Adapter/preferences/intentions -> frame-free controller state | late facade binding; defensive invalid transitions | W-C/W-UI |

## `Nexus.WishlistInternals.Renderer` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Renderer.New` | Construct the sole Wishlist main-editor presentation owner | WishlistEditor/tests | controller projections + UI intentions -> bounded frames/rows | cosmetic failures isolated; lazy frame | W-C/W-UI |

## `Nexus.Sync` and internal responder inventory

`Responder.*` is a source-local internal namespace, not part of the public
`Nexus.Sync` facade and not a separate transport owner. Its behavior is frozen
through public queue, admission, claim, retry, and convergence outcomes until
Sync extraction parity is complete.

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Sync.GetPeerInfo` | Peer status projection | Nameplate/UI/tests | RX -> - | nil unknown | S-M |
| `Sync.IsKnownPeer` | Peer predicate | Nameplate/UI | RX -> - | false unknown | S-M |
| `Sync.WorkState` | Queue/work snapshot | diagnostics/UI/tests | TX/RX -> - | defensive defaults | S-Q |
| `Sync.ResponseStats` | Responder counters | diagnostics/tests | RX/DG -> - | defensive scalars | S-Q |
| `Sync.GetCompatibilityHashes` | Current delta/DPS hashes | send/tests | CAT -> DG cache | last-good/reject | S-W |
| `Sync.GetCanonicalBuildHashes` | Canonical build buckets | compatibility/tests | CAT -> DG cache | last-good/reject | S-W |
| `Sync.GetLegacyBuildHash` | Accepted legacy hash | compatibility/tests | CAT -> DG cache | last-good/reject | S-W |
| `Sync.HashCacheStats` | Hash-cache counters | diagnostics/tests | DG -> - | defensive scalars | S-W |
| `Sync.EnsureChannel` | Discover/join channel | Main/Init/update | GA/TX -> TX | retry/noop | S-M |
| `Sync.ChannelName` | Wire channel name | Main/UI/tests | constant -> - | none | S-W |
| `Sync.ChannelIndex` | Joined channel index | Main/tests | TX -> - | nil disconnected | S-C |
| `Sync.IsConnected` | Connection predicate | UI/Main/tests | TX -> - | false disconnected | S-M |
| `Sync.Stats` | Session transport counters | UI/diagnostics/tests | DG -> - | established live scalar table | S-D/S-C |
| `Sync.IsReceiving` | Receive-window predicate | UI/Main | RX/clock -> - | false outside window | S-M |
| `Sync.ReceiveTimeLeft` | Remaining window | UI | RX/clock -> - | clamps zero | S-C |
| `Sync.LastSyncNewCount` | Last request result | UI | RX -> - | zero initially | S-C |
| `Sync.EventLog` | Defensive Sync history | Main/log view/tests | DG -> - | empty snapshot | S-D |
| `Sync.ClearLog` | Clear Sync history only | Main/log view/tests | DG -> DG | isolate | S-D |
| `Sync.LogRaw` | Append sanitized raw event | internal/tests | value -> DG | bounded/isolate | S-D |
| `Sync.RawLog` | Defensive raw history | diagnostics/tests | DG -> - | empty snapshot | S-D |
| `Sync.LogStats` | History retention stats | diagnostics/tests | DG -> - | defensive scalars | S-D |
| `Sync.LogEvent` | Bounded diagnostic append alias | Sync internals/tests | input -> DG | sanitize/trim/isolate | S-D |
| `Sync.NoteTransportNotice` | Record throttle/transport notice | Main/transport | text -> TX/DG | bounded/isolate | S-Q |
| `Sync.RequestDataViewRefresh` | Notify represented view change | accepted commit paths | CAT -> scheduler/UI | isolate | F-A/S-C |
| `Sync.RequestLoadout` | Explicit exact-ID request | UI/recovery/tests | RX/TX -> TX/RX | reject queue/full/invalid | S-Q/S-W |
| `Sync.RequestFullLoadoutSync` | Request queued known IDs | UI/recovery | CAT/RX/TX -> TX/RX | bounded/reject | S-W/S-C |
| `Sync.BroadcastBuild` | Validate/serialize/admit one build | Community/Sync/tests | CAT/TX -> TX/DG | reject before admission | S-Q/S-W |
| `Sync.BroadcastMine` | Broadcast bounded local delta | Community/Sync/tests | CAT/TX -> TX/RX | backpressure yield | S-Q/S-M |
| `Sync.BroadcastBuildSummary` | Admit one bounded compatibility summary | response pipeline/tests | candidate/TX -> TX/DG | reject before admission | S-Q/S-W |
| `Sync.GetShareStatus` | Defensive latest local Share outcome | Community/UI/tests | TX/session -> - | nil unknown ID; peer confirmation unavailable | S-Q/S-D |
| `Sync.GetDeleteStatus` | Defensive bounded local delete outcome | Community/tests | TX/session -> - | nil unknown ID; peer confirmation unavailable | S-Q/S-D |
| `Sync.BroadcastDpsRecord` | Validate/serialize/admit DPS | DpsCapture/Sync/tests | CAT/TX -> TX/DG | reject before admission | S-Q/S-W |
| `Sync.BroadcastDps` | Construct local DPS send | DpsCapture/tests | CAT/TX -> TX | reject invalid/queue | S-W |
| `Sync.BroadcastDelete` | Admit author deletion | Community/tests | CAT/TX -> TX | reject non-owner/queue | S-M |
| `Sync.HandleIncoming` | Parse, validate, route wire input | Main channel event/tests | wire/RX/CAT -> RX/CAT/TX/DG | fail closed/isolate | S-W/S-M/F-A |
| `Sync.RequestSync` | Start manual/login reconciliation | Main/UI/tests | CAT/TX/RX -> TX/RX | cooldown/queue reject | S-M/S-Q |
| `Sync.GetLeaderboardSyncStatus` | UI status projection | Leaderboard/Main | TX/RX/DG -> - | idle defaults | S-D |
| `Sync.TombstoneCount` | Deletion count projection | diagnostics/tests | CAT -> - | zero invalid store | S-C |
| `Sync.OnUpdate` | One bounded transport/response unit | Main direct update | TX/RX/clock -> TX/RX/DG | isolate at Main | S-Q/S-M |
| `Sync.OnWorldEntry` | Revalidate channel and re-arm join retry without resetting admitted work | Main lifecycle/tests | channel/session -> channel/session | false while disconnected; preserves request/queue/inflight state | S-Q/S-M |
| `Sync.HandleStatusRequest` | Replace one pending developer status reply | Main dev-token whisper route | RX -> RX | noop empty sender | S-C |
| `Sync.FlushStatusReply` | Build/send pending status reply directly | update/tests | RX/GA -> RX/TX | consume then best-effort whisper | S-C |
| `Sync.SendStatusTo` | Build/send explicit status reply directly | slash/tests | GA -> TX | false invalid/codec; protected send | S-C |
| `Sync.Init` | Bind codec/adapter and reset session owner | Main/tests | facades -> TX/RX/DG | idempotent/retry | S-M/S-C |
| `Responder.SupportsRequestContext` | Recognize the reserved request-correlation capability marker | response pipeline/tests | request ID -> - | false for legacy/unmarked IDs | S-W/S-M |
| `Responder.RequestContext` | Validate one bounded scalar response context | response pipeline/tests | requester/request ID/bucket -> request-local | reject invalid or unmarked context | S-W/S-M |
| `Responder.ContextSuffix` | Encode optional contextual envelope fields only for marked requests | response pipeline/tests | request-local -> wire suffix | empty for legacy/unmarked traffic | S-W |
| `Responder.ContextRequestId` | Project matching, foreign, or ambient context into bounded session attribution | receive pipeline/tests | request-local/session identity -> - | nil ambient; foreign sentinel | S-M/S-D |
| `Responder.NoteContextOutcome` | Attribute one sanitized response outcome to the exact active request | receive pipeline/tests | request-local/session -> DG | false ambient/inactive | S-M/S-D |
| `Responder.BulkFree` | Cheap queue headroom | responder/tests | TX -> - | clamps bound | S-Q |
| `Responder.Backpressured` | Headroom predicate | responder/tests | TX -> - | true on saturation | S-Q |
| `Responder.CanAdmit` | Pre-work admission predicate | responder/tests | TX/count -> - | false invalid/full | S-Q |
| `Responder.PrepareSummary` | Pure bounded summary prep | response pipeline/tests | candidate -> request-local | reject malformed | S-Q |
| `Responder.ChunkBuildMessages` | Build exact wire chunks | prepared candidate/tests | bytes -> request-local | reject wire limit | S-W/S-Q |
| `Responder.ResolveBuild` | Hydrate candidate evidence | response pipeline/tests | CAT -> request-local | reject unavailable | S-W |
| `Responder.PrepareBuild` | Serialize one request-local build | response pipeline/tests | candidate/codec -> request-local | reject malformed | S-Q |
| `Responder.AdmitBuild` | Atomically enqueue prepared build | response pipeline/tests | request-local/TX -> TX | false without partial admit | S-Q |
| `Responder.BuildCandidateSnapshot` | Create immutable bounded candidate state | response pipeline/tests | CAT -> request-local | defer while backpressured | S-Q |
| `Responder.SnapshotCurrent` | Revision-current predicate | response pipeline/tests | CAT/revisions -> - | false stale | S-Q |
| `Responder.AdvanceCandidateSnapshot` | Advance one candidate | response pipeline/tests | request-local/CAT -> request-local | one-unit yield | S-Q |
| `Responder.PrepareCandidate` | Prepare one fair bucket item | response pipeline/tests | request-local/CAT -> request-local | bounded yield/reject | S-Q |
| `Responder.AdmitCandidate` | Admit one prepared item | response pipeline/tests | request-local/TX -> TX/RX | no duplicate/partial admit | S-Q |
| `Responder.SendNextBuild` | Fair one-build response step | response pipeline/tests | RX/TX -> RX/TX | yield full/expired | S-Q |
| `Responder.ValidatePreparedDps` | Validate immutable DPS payload | response pipeline/tests | request-local -> - | reject malformed/stale | S-W |
| `Responder.PrepareResponseEntry` | Initialize resumable requester state | response pipeline/tests | RX/CAT -> RX request-local | cheap backpressure yield | S-Q |
| `Responder.ResetResponseEntry` | Clear retry-local preparation | response pipeline/tests | RX -> RX | preserves admitted TX | S-Q |
| `Responder.NextReadyBucket` | Fair bucket selection | response pipeline/tests | RX -> RX cursor | nil none ready | S-Q |
| `Responder.SelectFairUnit` | Deterministic requester selection | response pipeline/tests | RX -> RX cursor | nil none ready | S-Q |
| `Responder.ProcessLoadoutResponse` | One explicit loadout unit | response pipeline/tests | RX/CAT/TX -> RX/TX | bounded retry/expiry | S-Q/S-W |

## `Nexus.Main` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Nexus.RequestRecompute` | Set force-recompute latch | adapter/scheduler/tests | request -> AUT | deterministic true | A-I/M-C |
| `Nexus.RetryAutoLock` | Mark retained rejected/expired AutoLock identity for one explicit retry | Wishlist editor/tests | AUT/SV -> AUT/SV | false without terminal identity | A-I/M-C |
| `Nexus.AppendAudit` | Append bounded diagnostic audit | Main/tests | fields/DG -> DG | false without diagnostic owner | S-D/M-C |
| `Nexus.RecomputeStats` | Recompute/FSM counters | diagnostics/tests | AUT/DG -> - | defensive scalars | A-I/M-C |
| `Nexus.RefreshHudView` | Noncritical display snapshot | scheduler/UI/tests | AUT/CAT/GA -> UI/DG | isolate/last model | BOOT/F-A/M-C |
| `Nexus.HudSnapshotStats` | HUD cache counters | diagnostics/tests | DG -> - | defensive scalars | BOOT |
| `Nexus.NewAIExportCoroutine` | Incremental diagnostic export | slash/log UI/tests | SV/CAT/DG -> coroutine-local | bounded/isolate | S-D/M-C |
| `Nexus.GetDiagnosticPageText` | Diagnostic tab projection | LogViewer/tests | SV/CAT/DG -> - | stable fallback text | S-D/M-C |
| `Nexus.RefreshPanel` | Explicit stateful full recompute/repaint | DpsCapture/UI/tests | AUT/GA/CAT -> AUT/UI | false before ready | BOOT/A-I/F-A/M-C |

## `Nexus.Store` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Store.Init` | Bind, decide/complete legacy retirement, and run ordered additive migrations | Main/tests | globals/defaults -> SV | throw/retry without false success or legacy release | ST/ST-C/ST-L |
| `Store.CurrentOwnerKey` | Canonical current character identity | Store/data owners | live name+realm -> owner key | nil until both are authoritative | ST/A-I |
| `Store.RegisterCurrentCharacter` | Upsert the account character ledger | Store/State | live identity/class/time -> SV | no write for unknown identity | ST/A-I |
| `Store.IsAccountOwnerKey` | Test canonical account membership | retention/UI | owner key + SV -> boolean | rejects unknown/noncanonical keys | ST/A-I |
| `Store.IsAccountBuild` | Protect account-owned build rows | retention/UI | build + ledger -> boolean | explicit local/imported markers remain protected | ST/A-I |
| `Store.AccountCharacters` | Live account character ledger | account views/tests | SV -> SV table | empty view before availability | ST/ST-C |
| `Store.SettingsVersion` | Supported settings schema | Store/tests | constant -> - | none | ST |
| `Store.Settings` | Account settings owner | all runtime consumers | SV -> SV missing defaults | preserves unknown/future | ST/ST-C |
| `Store.State` | Character-scoped safety state | Main/GameAdapter/tests | SV/player identity -> SV | nil until real character | ST/A-I/ST-C |

## `Nexus.GameAdapter` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `A.Catalog` | Published Echo catalog | Model/Main/UI | GA/cache -> CAT cache | last-good/not-ready | A-C |
| `A.CheckCatalogSource` | Explicit slow source check | scheduler/tests | GA -> CAT/revision | last-good/isolate | A-C |
| `A.CatalogStatus` | Catalog counters/status | diagnostics/tests | DG -> - | defensive scalars | A-C |
| `A.Ready` | Adapter readiness | Main/UI | GA/cache -> - | false pre-login | BOOT |
| `A.Board` | Current offered Echo board | Main/Model/UI | GA -> defensive data | empty/not-ready | A-I |
| `A.Charges` | Reroll/tome charges | Main/Model | GA -> defensive data | zero/not-ready | A-I |
| `A.DumpLockedPerksRaw` | Diagnostic locked data | diagnostics | GA -> serialized diagnostic text | empty/isolate | A-X |
| `A.LockedOwned` | Locked owned projection | Model/Main | GA/SV -> defensive data | empty/not-ready | A-I |
| `A.MaxPermanentEchoes` | Authoritative permanent slot capacity | AutomationRuntime/tests | GA -> number,source | nil/unavailable; never infer from editor cells | A-X/M-C |
| `A.Owned` | Owned Echo projection | Main/Model/UI | GA/SV -> defensive data | empty/not-ready | A-I |
| `A.RunBoundaryReset` | Reset per-run adapter latches | Main | GA/SV -> GA/SV | idempotent | A-I |
| `A.RequestGranted` | Request ownership/grant refresh | Main | GA -> GA request state | false/unavailable | A-I |
| `A.WishlistKey` | Pure exact-loadout identity | UI/tests | echoes -> - | nil malformed | A-W |
| `A.WishlistEvidenceState` | Pure bounded lock-evidence and association-state classification without boolean coercion | UI/tests | candidate/identity -> - | fixed fail-closed state | A-W/A-X |
| `A.GetWishlistCandidates` | Saved wishlist candidates | UI | GA -> defensive list | empty/ambiguous | A-W |
| `A.GetFirstRunWishlist` | First-run association read | Main/UI | SV/GA -> defensive row | nil absent | A-W/A-X |
| `A.SetFirstRunWishlist` | First-run slot association | Main/UI | GA/SV -> SV | reject invalid slot | A-W/A-X |
| `A.SetFirstRunWishlistIdentity` | First-run exact association | Main/UI | identity/SV -> SV | reject invalid | A-W |
| `A.ClearFirstRunWishlist` | Clear first-run association | Main/UI | SV -> SV | idempotent | A-X |
| `A.GetLoadoutWishlist` | Loadout association read | UI/Main | SV/GA -> defensive row | nil absent/ambiguous | A-W |
| `A.GetLoadoutWishlistState` | Read-only exact association evidence diagnosis and bounded transition observation | WishlistController/tests | SV/GA -> defensive row/fixed state | identity unavailable, pending, mismatch, or invalid without mutation | A-W/A-X |
| `A.GetLoadoutWishlistSlot` | Association slot read | UI/Main | SV -> - | nil absent | A-W/A-X |
| `A.SetLoadoutWishlistIdentity` | Exact per-loadout association | UI/Main | identity/SV -> SV | reject invalid | A-W |
| `A.SetFirstLoadoutWishlistIdentity` | First active loadout association | UI/Main | GA/identity/SV -> SV | reject no loadout | A-W/A-X |
| `A.SetLoadoutWishlist` | Slot-to-slot association | UI/Main | GA/SV -> SV | reject invalid/ambiguous | A-W |
| `A.UpdateWishlistAssociationAfterSave` | Reconcile saved association | UI/Main | GA/identity/SV -> SV | preserves prior on failure | A-W/A-X |
| `A.ClearLoadoutWishlist` | Remove one association | UI/Main | SV -> SV | idempotent | A-W |
| `A.Wishlist` | Active exact wishlist | Main/Model/UI | GA/SV -> defensive row | nil ambiguous | A-W |
| `A.WishlistNote` | Ambiguity/status note | UI/Main | adapter session -> - | nil none | A-X |
| `A.GetLoadoutCandidates` | Active-loadout candidate list | UI | GA/SV -> defensive list | empty none | A-X |
| `A.Slots` | Saved loadouts | Main/UI | GA -> defensive list | empty/not-ready | A-I/A-W |
| `A.RequestSlots` | Refresh saved loadouts | Main/UI | GA -> GA request | false/unavailable | A-I |
| `A.DiscoverySynced` | Discovery convergence predicate | Main | GA -> - | false unknown | A-X |
| `A.LeverHasKnownMember` | Lever membership predicate | Model/Policy | CAT -> - | false unknown | A-I |
| `A.UnknownTomesForEchoes` | Unknown tome projection | UI/Model | CAT/GA -> defensive list | empty unknown | A-I |
| `A.DisabledLevers` | Disabled lever projection | Main/Model | GA/SV -> defensive set | empty/not-ready | A-I |
| `A.ToggleLever` | Submit lever mutation | Main/Ratchet | GA/AUT -> GA | reject safety/spacing | A-I/A-X |
| `A.InFlight` | Current action snapshot | Main | GA/AUT -> defensive row | nil none | A-I |
| `A.Take` | Submit Echo pick | Main/Ratchet | GA/AUT -> GA | reject safety/spacing | A-I |
| `A.Banish` | Submit banish | Main/Ratchet | GA/AUT -> GA | reject safety/spacing | A-I |
| `A.Reroll` | Submit reroll | Main/Ratchet | GA/AUT -> GA | reject safety/spacing | A-I |
| `A.Freeze` | Submit freeze | Main/Ratchet | GA/AUT -> GA | reject safety/spacing | A-I/A-X |
| `A.Activate` | Activate saved loadout | UI/Main | GA/AUT -> GA | reject invalid/busy | A-W |
| `A.Save` | Save active loadout | UI/Main | GA/AUT/SV -> GA/SV | reject invalid/busy | A-W |
| `A.UploadWishlist` | Upload wishlist through service | Wishlist/UI | GA/AUT -> GA | reject invalid/spacing | W-UI/A-W |
| `A.LockPerk` | Lock Echo | Main/Ratchet | GA/AUT -> GA | reject safety | A-I/A-X |
| `A.UnlockPerk` | Unlock Echo | Main/Ratchet | GA/AUT -> GA | reject safety | A-I/A-X |
| `A.SetSoloPicker` | Disable external auto picker | Main | GA/AUT -> GA | noop unavailable | A-I |
| `A.AutoAcceptOn` | Read external auto-accept | Main | GA -> - | false unknown | A-X |
| `A.RestoreAutoAccept` | Restore prior external state | Main | SV/GA -> GA/SV | noop unavailable | A-I |
| `A.RivalDetected` | Rival-player predicate | Main/Policy | GA -> - | false unknown | A-I |
| `A.Level` | Player level | Main/Model/UI | WoW -> - | zero unavailable | A-I |
| `A.Horizon` | Strategy horizon | Main/Model | GA/CAT -> number | conservative default | A-I |
| `A.ExternalActionSeen` | External mutation latch | Main | GA session -> - | false none | A-X |
| `A.OwnedSyncInfo` | Owned-state revision info | Main | GA/SV -> defensive row | empty unavailable | A-X |
| `A.UnlockedSlots` | Available permanent slots | Main/Model | GA -> number | zero unknown | A-X |
| `A.TomeMutationPaused` | Tome safety pause | Main | GA/session -> - | false none | A-I/A-X |
| `A.TomeMutationResumeAt` | Exact end of an active Tome safety pause | Main direct loop | GA/session -> - | nil none | A-I/A-X |
| `A.EchoReconcileStats` | Defensive fixed-field Echo reconciliation totals, generations, and one bounded last reason | Main diagnostics/tests | GA/DG -> - | defensive zero/last-good | A-C/A-I/A-X |
| `A.AutomationSignature` | Generation-backed Echo/tome-safety snapshot for five-second missed-signal repair | Main direct loop | GA/Store semantic generations -> ephemeral row | nil failed read | A-C/A-I/A-X |
| `A.ConsumeDirty` | Consume represented dirty set | Main direct loop | GA session -> GA session | empty set | A-C/A-I/A-X |
| `A.RecordLevelBurstPump` | Acknowledge fixed scalar recompute/render/action work for one consumed level burst | AutomationRuntime direct loop | AUT scalar deltas -> GA session counters | false without events | A-I/A-X |
| `A.LevelBurstStats` | Defensive fixed-field level-event/coalescing/pump/work totals and authoritative last level | Main diagnostics/tests | GA session scalars -> defensive row | zero before observation | A-I/A-X |
| `A.PresentationRevisions` | Allocation-free Wishlist/Owned/Catalog scalar generations for revision-keyed overlay acquisition | WishlistOverlay/tests | GA semantic generations -> - | zero generations before observation | A-C/A-X |
| `A.ConsumeUserAction` | Consume user-action latch | Main direct loop | GA session -> GA session | false none | A-X |
| `A.Init` | Bind callbacks/Store and install hooks | Main/tests | facades/GA -> adapter session | idempotent hooks | BOOT/A-C/A-X |
| `A.OnEvent` | Adapter event router | Main event loop | event/GA -> adapter session | noop irrelevant | A-I/A-X |
| `A.Poll` | Direct safety/FSM polling | Main 0.2-second loop | GA/AUT -> adapter session | isolate/no action authority | A-I/A-C |

## `Nexus.CommunityInternals.Renderer` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `Renderer.New` | Construct one main/detail/popup presentation owner from one controller and the projection resolver | CommunityBuilds | projections/controller/UI -> UI session | fail fast on missing dependency; lazy frame retry | C-UI |

## `Nexus.CommunityBuilds` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `M.IsOwnBuild` | Ownership predicate | UI/tests | CAT/player -> - | false unknown | C-UI |
| `M.EnsureDpsBuildForEchoes` | Exact DPS build identity | DpsCapture/UI | CAT/DPS -> CAT | reject invalid | C-UI/C-C |
| `M.PostCurrentWishlist` | Create/post owned build | popup/tests | GA/CAT/SV/TX -> CAT/TX | reject no wishlist/invalid | C-UI |
| `M.ShareStatus` | Defensive local save/queue/send outcome | popup/tests | controller/TX -> - | nil unknown ID; no peer receipt claim | C-UI/S-D |
| `M.CanRetryShare` | Prove exact owned terminal Share retry eligibility | detail/tests | CAT/TX -> - | false active/success/non-owner/stale version | C-UI/S-D |
| `M.RetryShare` | Explicitly retry one unchanged failed Share | detail/tests | CAT/TX -> TX | reject unless exact failed owner; bounded Sync admission | C-UI/S-Q |
| `M.PublishImportedBuild` | Publish saved-loadout mirror | UI/tests | CAT/TX -> CAT/TX | reject invalid/non-owner | C-C |
| `M.EditBuild` | Edit owned build metadata | popup/tests | CAT/TX -> CAT/TX | reject non-owner/invalid | C-UI |
| `M.UpdateFromWishlist` | Replace owned exact loadout | popup/tests | GA/CAT/TX -> CAT/TX | reject non-owner/ambiguous | C-UI |
| `M.DeleteBuild` | Delete owned build | detail/tests | CAT/TX -> CAT/TX | reject non-owner | C-UI |
| `M._PumpPendingLockIn` | Retry pending lock-in | frame update/tests | controller/GA/clock -> controller/GA | 12 retries then friendly expiry | C-UI/C-C |
| `M.IsLockInPending` | Pending predicate | UI/tests | UI -> - | false none | C-UI |
| `M.LockInSelected` | Confirm/apply selected build | detail/tests | UI/CAT/GA -> UI/GA | reject unavailable/busy | C-UI |
| `M.GetSelectedBuildForPanel` | Defensive selected projection | Main/Panel | UI/CAT -> - | nil none | C-UI |
| `M.GetSelectedBuildForPanelKey` | Allocation-free visible selection identity plus selected-record revision | Main/Panel | UI/CAT revision scalars -> - | nil/zero while hidden | C-UI/A-C |
| `M.VirtualStats` | Read-only pool counters | tests/diagnostics | UI/DG -> - | defensive scalars | C-UI |
| `M.DiagnosticSnapshot` | Fixed-shape sanitized persisted-view publication state | visible State diagnostics/explicit export/tests | CAT count/filter/revision/UI scalars -> - | bounded unavailable/hidden reason | C-UI/DG |
| `M.MarkDataDirty` | Coalesce represented refresh | ViewRefresh/tests | UI -> UI | idempotent | C-UI |
| `M.ScrollTo` | Virtual offset controller | UI/tests | UI -> UI | false no frame | C-UI |
| `M.Refresh` | Rebuild/rebind represented view | revisions/UI/tests | CAT/DPS/UI -> UI | preserve dirty on error | C-UI |
| `M.ShowPostBuild` | Open post controller/frame | UI/tests | UI/GA -> UI | noop unavailable | C-C |
| `M.TogglePostPopup` | Post popup entry alias | UI | UI -> UI | noop unavailable | C-C |
| `M.ToggleEditPopup` | Edit popup controller | UI/tests | CAT/UI -> UI | reject invalid ID | C-C |
| `M.Init` | Bind Adapter/Model | Main/tests | facades -> UI session | idempotent/lazy frame | C-UI/BOOT |
| `M.Select` | Stable-ID selection | cards/tests | CAT/UI -> UI | nil invalid | C-UI |
| `M.SetViewMode` | Compatibility view routing | UI/tests | request -> UI | bounded accepted modes | C-UI |
| `M.GetViewMode` | Current compatibility mode | UI/tests | UI -> - | stable `builds` | C-C |
| `M.Show` | Show/refresh main frame | slash/navigation/tests | UI/CAT -> UI | lazy/retry | C-UI |
| `M.ShowBuild` | Show and select exact ID | Leaderboard/UI/tests | CAT/UI -> UI | no selection if missing | C-C |
| `M.Hide` | Hide main frame | UI | UI -> UI | noop absent | C-UI |
| `M.IsShown` | Visibility predicate | UI/tests | UI -> - | false absent | C-UI |
| `M.Toggle` | Toggle main frame | slash/navigation/tests | UI/CAT -> UI | lazy/retry | C-UI/BOOT |

## `Nexus.WishlistEditor` inventory

| Surface | Responsibility | Called by | Reads -> writes | Failure | Coverage/gap |
| --- | --- | --- | --- | --- | --- |
| `M._PumpApplyRetry` | Retry pending wishlist upload | frame update/tests | UI/GA/clock -> UI/GA | bounded deadline | W-UI/W-C |
| `M.IsApplyPending` | Pending predicate | UI/tests | UI -> - | false none | W-UI/W-C |
| `M.ImportEBH1String` | Parse/import external wishlist text | popup/tests | text/GA -> UI/GA | reject malformed/ambiguous | W-C |
| `M.Refresh` | Reconcile through controller and render current state | UI/adapter callbacks/tests | controller/GA/CAT/UI -> UI | reclaim/retry on error | W-UI |
| `M.ToggleDisplayPopup` | Overlay-display settings popup | UI/tests | UI/SV -> UI/SV via owner APIs | noop unavailable | W-UI |
| `M.Init` | Bind Adapter/Model | Main/tests | facades -> UI session | idempotent/lazy frame | W-UI/BOOT |
| `M.DebugPendingCount` | Selected draft-entry count | tests/diagnostics | controller -> - | zero none | W-UI |
| `M.DebugDraftState` | Defensive draft snapshot | tests/diagnostics | UI -> - | defensive empty | W-UI |
| `M.OpenForCandidate` | Candidate-to-editor controller | Community/Leaderboard/tests | candidate/GA/UI -> UI | reject malformed | W-UI |
| `M.OpenForWishlist` | Exact wishlist/loadout controller | Main/UI/tests | wishlist/GA/UI -> UI | reject ambiguous | W-C |
| `M.NewWishlist` | Clean editor state | UI/tests | UI/GA -> UI | lazy/retry | W-C |
| `M.Show` | Show current editor | slash/UI/tests | UI/GA -> UI | lazy/retry | W-UI |
| `M.Toggle` | Toggle editor | Main/slash/UI/tests | UI/GA -> UI | lazy/retry | W-UI/BOOT |

## Callback registration groups

Counts are source sites, not runtime multiplicity. For example, GameAdapter's
service-hook loop has one source site but may register against several named
service methods. Nil `SetScript` calls are included because clearing a pooled
row handler is observable lifecycle behavior.

| Module/group | Sites | Registration owner | Reads -> writes | Failure/fallback | Coverage/gap |
| --- | ---: | --- | --- | --- | --- |
| `Main/lifecycle-events` | 7 | Main event frame -> MainLifecycle | WoW events -> AUT/GA/TX/UI | ignore until initialized | BOOT/M-C |
| `Main/event-router` | 1 | Main event frame `OnEvent` | event -> Store/GA/Sync/AUT | per-path isolate/retry | BOOT/F-A/M-C |
| `Main/direct-update-loop` | 1 | Main event frame `OnUpdate` | clock -> GA Poll/Sync/AUT/UI | direct safety cadence | A-I/F-A/M-C |
| `GameAdapter/perk-ui-dirty-hooks` | 2 | Adapter hook installer | Project Ebonhold UI -> adapter dirty | idempotent hook install | A-C/A-X |
| `GameAdapter/journal-dirty-hook` | 1 | Adapter hook installer | EchoJournal -> adapter dirty | idempotent | A-C |
| `GameAdapter/service-mutation-hooks` | 1 | Adapter hook loop | service calls -> user-action/dirty | hook failures isolated | A-I/A-X |
| `CommunityRenderer/detail-link-lock-actions` | 16 | detail renderer | pointer/text -> UI/controller intention | tooltip/frame fallback | C-UI/C-C |
| `CommunityRenderer/pooled-card-bindings` | 6 | card factory | pointer/click -> stable selection/UI | release failed bind | C-UI |
| `CommunityRenderer/main-frame-lifecycle` | 3 | main frame | drag/update -> UI/Sync status | bounded tick/noop hidden | C-UI |
| `CommunityRenderer/main-controls-virtual-list` | 35 | main renderer | filters/nav/paging/scroll -> UI/controller intention | bounded rows/dropdown close | C-UI/C-C |
| `CommunityRenderer/post-edit-popups` | 15 | popup renderer | text/click/drag -> UI/controller intention | reject invalid/retain draft | C-UI/C-C |
| `WishlistRenderer/dynamic-row-reset-bindings` | 8 | pooled row binder | click/mousedown/nil reset -> UI | stale handlers cleared | W-UI |
| `WishlistRenderer/main-frame-lifecycle` | 5 | main frame | drag/update/show/hide -> UI/controller projections | bounded retry/restore server UI | W-UI/W-C |
| `WishlistRenderer/navigation-wishlist-controls` | 30 | navigation renderer | nav/search/click -> UI/controller intentions | preserve draft/selection | W-UI/W-C |
| `WishlistRenderer/list-edit-controls` | 16 | virtual lists/editor | wheel/click -> UI | bounded rows/clamped values | W-UI |
| `WishlistRenderer/candidate-association-controls` | 2 | ambiguity renderer | candidate click -> UI/controller association intention | no bare ambiguous choice | W-UI/W-C |
| `WishlistRenderer/display-popup-controls` | 10 | display popup | drag/scale/lock -> UI/SV owner APIs | clamp/noop unavailable | W-UI |

## SavedVariables ownership

| Data | Decision/mutation owner | Readers | Frozen invariant |
| --- | --- | --- | --- |
| `NexusDB` root and unknown fields | Store | all facades through owned APIs | Root identity and unknown/future fields survive initialization. |
| Settings/settings version | Store | Main, GameAdapter, UI | Never downgrade versions or replace explicit user choices. |
| Character automation state | Store; Main/GameAdapter mutate owned fields | Main/GameAdapter | Direct safety/FSM semantics and per-character identity stay unchanged. |
| Builds/tombstones | BuildCatalog after Sync/Community validation | Sync/UI/Main | Ownership, revisions, tombstones, unknown fields, and exact IDs stay unchanged. |
| DPS records | DpsCapture after validation | Sync/UI/Main | Origin authority, exact-loadout identity, categories, and winning rows stay unchanged. |
| Evidence/compaction | LoadoutEvidence/DataCompaction | catalog/DPS/Sync/UI | Exact canonical arrays and future schemas remain safe. |
| Diagnostic histories | Errors/DiagnosticLogs/Sync/DpsCapture owners | Main/LogViewer | Retention is observational and cannot mutate queues or automation. |
| UI preferences/associations | Store/Adapter/catalog owner APIs | Community/Wishlist/Main | Filters, positions, selections, associations, and drafts are never wholesale replaced. |

## Proposed extraction seams and invariants

These boundaries were frozen in Stage 10 and are being extracted one bounded
checkpoint at a time behind the same public facades.

1. Sync: pure inbound parsing/shape validation; pure reconciliation planning;
   immutable compatibility/candidate snapshots; one stateful durable transport
   owner; one diagnostic projection. Pure modules send nothing and commit
   nothing. Claims remain after complete payload admission.
2. Main: pure slash parsing, diagnostic export construction, and HUD view-model
   construction around one stateful lifecycle/automation coordinator. Passive
   providers and scheduler callbacks never call GameAdapter mutations.
3. Store: pure migration decision helpers around one root-binding/persistence
   owner. Unknown/future data is input to preservation decisions, never cleanup.
4. GameAdapter: pure normalization/catalog helpers may accept captured values,
   but all Project Ebonhold globals and gameplay actions remain in GameAdapter.
5. Community/Wishlist: pure controllers/projections accept plain data and emit
   intentions; renderers own frames/pools only. Renderers never own SavedVariables
   or transport, and controllers never create frames.

No old and new transport, persistence, or gameplay mutation path may run at the
same time. An old implementation remains until its replacement has parity
coverage and any required live verification.

## Residual freeze attribution boundaries (10.2)

`5cbe8ac` remains the primary fix: active-Sync Community invalidations use its
owned dirty bit, publish once after the receive window, skip unchanged periodic
work, and reuse one revision-scoped DPS identity index. Checkpoint 10.2 does not
reimplement that path and does not add an incoming packet queue.

| Aggregate path | Complete measured boundary | Owner and mutation invariant |
| --- | --- | --- |
| `sync.incoming` | Entire `Sync.HandleIncoming(text, sender)` call reached through `CHAT_MSG_CHANNEL` | Performance wraps the established synchronous handler; parsing, validation, sender binding, ownership, transport queues, wire output, and return timing are unchanged. |
| `views.refresh` | Entire keyed `ViewRefresh` scheduler callback, including receive-state decision and each view call | ViewRefresh owns three booleans only; active Sync marks Community dirty and defers Leaderboard/Panel data, while direct status paths remain live. |
| `hud.prepare` | `BuildHudDisplayModel(...)` before `Panel.Render` in both full render and HUD-only refresh | Main retains service-read/model ownership; `panel.render` still measures row/frame binding separately. |

The 1,000-build/500-DPS baseline probe confirmed one genuinely new issue: an
active receive callback still invoked open Leaderboard projection and Panel/HUD
model preparation for every coalesced revision group. `ViewRefresh` now keeps
those noncritical views dirty in bounded booleans and invokes each once after
Sync becomes quiet. Community keeps its established self-owned post-window
publication, avoiding a second scheduler-driven rebuild.

At checkpoint 10.2, the incoming handler and final individual view publications
remained synchronous. Stage 17 later made Community and Leaderboard source
acquisition, joining, and ranking resumable while retaining atomic visible-row
publication. The incoming handler is still synchronous, and offline aggregate
coverage is still not a formal live frame-time ceiling. All three timing paths
retain only count, total, maximum, and last values in session memory.

## Residual runtime stutter boundaries (16.2)

Checkpoint 16.2 extends attribution around the existing direct update path; it
does not move polling into the scheduler or authorize a second automation
owner.

| Aggregate path | Complete measured boundary | Frozen behavior |
| --- | --- | --- |
| `lifecycle.update` | MainLifecycle's complete event-frame update delegate | Sync, DPS, Scheduler, and the direct automation delegate retain their established order. |
| `automation.update` | AutomationRuntime's complete elapsed-time gate, poll, dirty consumption, and optional FSM step | The 0.2-second cadence and fail-closed poll behavior are unchanged. |
| `gameadapter.poll` | One complete direct `GameAdapter.Poll()` call, including failed calls | Failures are counted and returned to the existing containment path; no scheduler or gameplay mutation path is added. |

Automation now retains one immutable Wishlist/settings/lock-target plan context.
Board-only dirtiness and ordinary action deadlines reuse that context; slot/data
signals, catalog revisions, explicit recomputation, and the independent
five-second recovery probe may rebuild it. Owned state, slots, board state,
authorization, and action deadlines remain live reads on every required FSM
step, and every gameplay write still crosses GameAdapter's existing safety
checks.

Leaderboard publication now has a cheap revision/filter currentness probe and
an owned dirty bit. Unchanged requests refresh status only. Active Sync marks
the view dirty without scanning, joining, sorting, copying, or binding rows,
then the visible view publishes once after quiet. Hidden views retain the dirty
state until shown. Failed projections or bindings retain the last-good rows,
and the renderer continues to use its fixed visible-row pool.

## Sync and Store parity boundaries (10.3)

Checkpoint 10.3 adds executable contracts without changing runtime code. The
fixtures separate pure validation/planning from the sole queue and persistence
owners, and link distributed safety coverage to the future extraction seams.

| Contract slice | Exact executable coverage | Frozen owner/invariant |
| --- | --- | --- |
| Sync facade, status projections, diagnostic snapshots, refresh delegation, and session reset | `tests/run_sync_contract_characterization.lua`, `tests/run_sync_facade_parity.lua` | Sync retains exactly 43 callables. SyncDiagnostics owns bounded history/live counters and defensive aggregate views; SyncSession owns peer/window/recovery/convergence/status state; reset identities and coordinator order remain unchanged while projections admit no packets or mutate SavedVariables. |
| Wire limits, accepted legacy forms, canonical hashes, current-peer deltas, and synchronous inbound order | `tests/run_sync_inbound_parity.lua`, `tests/run_sync_compatibility_parity.lua`, `tests/run_sync_wire_limits.lua`, `tests/run_private_sync_compat.lua`, `tests/run_sync_hash_cache.lua`, `tests/run_sync_baseline_delta.lua` | The inbound owner preserves sender-bound validation, exact assembly, and ordered validated callbacks without a FIFO; the read-only compatibility owner preserves exact wire/hash results, revision-keyed candidate reuse, and one-row resumability before catalog mutation or transport admission. |
| Request correlation, ambient protocol-7 compatibility, and bounded DPS responder fanout | `tests/run_sync_request_correlation.lua`, `tests/run_dps_fanout_bound.lua` | Marked request context attributes only matching accepted or rejected work; requestless traffic remains ambient, stale/foreign work remains unrelated, multipart contexts never mix, and the existing claim/election owner bounds equivalent relay fanout while retaining every direct owner. |
| Queue caps/durability, fair retry/expiry, responder payload admission, and claim timing | `tests/run_sync_transport_owner.lua`, `tests/run_sync_transport_safety.lua`, `tests/run_sync_response_backpressure.lua`, `tests/run_sync_reconciler_parity.lua` | The sole transport owner preserves production caps, atomic admission, control/FIFO order, retained retries, and exact saturation durability; the reconciler performs at most one expensive unit per update, expires saturated work by absolute age, reuses prepared work, and requests claims only after payload admission. |
| Sender/author ownership, tombstones, and mesh convergence | `tests/run_sync_owner_claims.lua`, `tests/run_tombstone_mesh_relay.lua`, `tests/run_sync_integration.lua` | Build/DPS/tombstone mutation remains behind validated authoritative owners. |
| Store pre-init access, root/subtable identity, ordered owners, future/unknown fields, dependency failure, and retry | `tests/run_store_contract_characterization.lua`, `tests/run_store_additive_migrations.lua` | Store is the sole `NexusDB` binder; evidence initializes before catalog and compaction, and later owners never run after an earlier failure. |
| Legacy-only/current-only/both-present authority, malformed/empty/future inputs, same-root retry, durable completion, namespace conflict, and TOC retention | `tests/run_store_legacy_retirement.lua` | Store adopts only a valid legacy root when current is absent/empty, never deep-merges, and clears the legacy global only after every ordered owner succeeds and the marker is durable. |

Checkpoint 11.1 now makes the previously characterized rename path executable.
The decision matrix distinguishes absent, empty, malformed, valid, future,
same-root, and already-completed states. Distinct both-identical and
both-different roots use current authority; injected owner failure and marker
ownership conflicts retain both recovery references without false completion.
Non-nil non-table values under either SavedVariables name fail closed before
binding; only an absent or empty-table current root may adopt legacy data.
The real ADDON_LOADED and PLAYER_ENTERING_WORLD paths keep Store failures
session-only and skip persistent diagnostic owners until Store succeeds.
The independent delayed Changelog callback also no-ops while the current root
is non-table, so it cannot create a competing database after bootstrap blocks.
The dual SavedVariables TOC declaration remains frozen. The Sync fixture still
does not introduce an inbound FIFO or alter transport timing.

## Main and GameAdapter parity boundaries (10.4)

Checkpoint 10.4 adds executable coordinator and service-boundary contracts
without changing runtime code. It freezes where decisions are computed, where
actions may be submitted, and which data/status paths must remain passive.

| Contract slice | Exact executable coverage | Frozen owner/invariant |
| --- | --- | --- |
| Addon/world initialization, event/slash routing, Sync/DPS-per-frame work, and direct poll/full-step triggers | `tests/run_main_lifecycle_parity.lua`, `tests/run_main_commands_parity.lua`, `tests/run_main_commands_actions.lua`, `tests/run_main_contract_characterization.lua`, `tests/run_full_boot_polish.lua` | Main alone registers frame events/scripts and slash globals; MainLifecycle sequences boot/event/update owners, MainCommands invokes one injected action, pre-player readiness remains inert, and the unchanged direct 0.2-second cadence reaches one AutomationRuntime. |
| Identical Model/Policy input and decision snapshots, one intent beat, deadline submission, and recompute counters | `tests/run_automation_runtime_parity.lua`, `tests/run_main_contract_characterization.lua`, `tests/run_main_refusal_recovery.lua`, `tests/run_integration.lua` | AutomationRuntime solely owns the FSM; only Main's direct cadence delegate may translate a prepared decision into an ordered GameAdapter action. |
| HUD, diagnostic, audit, export, status, panel-toggle, editor-toggle, and scheduled-view calls while an action is armed | `tests/run_main_contract_characterization.lua` | Passive status/view providers submit zero gameplay actions. `Nexus.RefreshPanel` is intentionally excluded: it is the established explicit stateful full-step entry point, not a passive HUD renderer. |
| Defensive reads, association identity, dirty-set consumption, retry limits, in-flight spacing, and external-action consumption | `tests/run_gameadapter_contract_characterization.lua`, `tests/run_snapshot_wishlist_association.lua`, `tests/run_echo_catalog_revision.lua` | GameAdapter owns captured service state and returns defensive projections where specified; latches are consumed exactly once. |
| Ordered `ToggleTomeEcho`, `SelectPerk`, `BanishPerk`, `RequestReroll`, `FreezePerk`, `ActivateServerBuildSlot`, and `SaveServerBuildSlot` calls | `tests/run_gameadapter_contract_characterization.lua`, `tests/run_integration.lua` | Gameplay writes stay behind GameAdapter validation, spacing, in-flight, and retry safeguards. |
| Project Ebonhold automation access boundary | Static source assertion in `tests/run_gameadapter_contract_characterization.lua` | Main, MainLifecycle, AutomationRuntime, Model, Policy, Ratchet, Strategy, and Relay contain no direct Project Ebonhold service/global access; visual frame integration outside automation remains unchanged. |

Main's completed passive diagnostic, HUD, slash-router, automation-runtime, and
lifecycle extractions keep frame/event/slash registrations plus public delegates
in Main while single stateful owners coordinate lifecycle and gameplay. Future
GameAdapter extraction may normalize captured values in pure
helpers, but service reads, hooks, and gameplay writes remain GameAdapter-owned.

## Community and Wishlist parity boundaries (10.5)

Checkpoint 10.5 closes the last offline parity rows without moving current UI
code. These modules are still internally coupled; the characterization records
the exact seams a later extraction must introduce behind the same facades.

| Contract slice | Exact executable coverage | Frozen owner/invariant |
| --- | --- | --- |
| Community facade, single owner instances, stable frame names, popup drafts/actions, show/hide/toggle, compatibility navigation, stable-ID selection, incomplete-loadout request, and hidden Panel projection | `tests/run_community_facade_parity.lua`, `tests/run_community_contract_characterization.lua`, `tests/run_builds_discoverability.lua` | `Nexus.CommunityBuilds` retains all public entry points and exactly one projection/controller/renderer; `NexusCommunityBuildsFrame`, `NexusPostPopup`, and `NexusEditPopup` remain stable, and selection survives virtualization but is projected only while the main frame is shown. |
| Saved-loadout publication, owner-only edit/delete/update, exact DPS build identity, lock intent, admission/broadcast order, and retry payload | `tests/run_community_controller_parity.lua`, `tests/run_community_contract_characterization.lua`, `tests/run_community_builds.lua`, `tests/run_build_edit_lock.lua`, `tests/run_record_identity_integrity.lua`, `tests/run_sync_late_post.lua`, `tests/run_spacing_fix.lua` | BuildCatalog remains the mutation owner, Sync receives only validated controller intentions, and retries retain one snapshotted exact payload for at most 12 retry uploads. |
| Community filtering, exact dual-record DPS eligibility, immutable projections, renderer separation, active-Sync dirty publication, and bounded visible rows | `tests/run_community_dps_eligibility.lua`, `tests/run_community_projection_contract.lua`, `tests/run_community_renderer_parity.lua`, `tests/run_builds_sort_filter.lua`, `tests/run_builds_virtualization.lua`, `tests/run_community_refresh_budget.lua`, `tests/run_freeze_attribution.lua` | The real revision-scoped DPS index intersects only finite positive full-fingerprint records; projection/cache keys remain revision-driven; renderer owns stable main/detail frames, binds only the visible window plus bounded overscan, and performs no heavy receive-window rebuild or persistence/transport/gameplay mutation. |
| Wishlist facade, `NexusEditorFrame`/`NexusDisplayPopup`, exact associated open, candidate/new-draft resets, malformed/valid EBH1 import, chosen name, and defensive draft diagnostics | `tests/run_wishlist_contract_characterization.lua`, `tests/run_wishlist_editor.lua`, `tests/run_editor_resilience.lua` | Invalid input is a no-op; valid imports are new drafts and never inherit an editing slot, selection, fulfilled lock target, or scroll offset. |
| Wishlist association, create/update confirmation, retained apply retry, expiry, exact upload, and persistence preferences | `tests/run_wishlist_contract_characterization.lua`, `tests/run_snapshot_wishlist_association.lua`, `tests/run_wishlist_upload.lua`, `tests/run_wishlist_tracking.lua` | GameAdapter/Store own association and persistence writes; UI retry preserves exact Echo/lock values and expires after the established 12 unsuccessful retries. |
| Wishlist row binding, scrolling, icons, overlay/display state, and failure recovery | `tests/run_editor_scroll_icons.lua`, `tests/run_editor_autorefresh.lua`, `tests/run_wishlist_overlay.lua`, `tests/run_overlay_lock_sync.lua`, `tests/run_overlay_zorder.lua` | Frame pooling/reset remains bounded, frame names and z-order remain stable, and cosmetic API failures cannot leave a half-built controller. |

### Selected future UI extraction seams

- Community catalog/controller is now extracted behind the public facade:
  `EnsureDpsBuildForEchoes` through `DeleteBuild`, stable selection,
  filter/sort inputs, popup drafts, and loadout/Sync intentions live in
  `CommunityController`. It mutates only through BuildCatalog, DPS, Sync, and
  GameAdapter owner APIs and creates no frames.
- Community projection: compose the immutable resumable
  `ViewProjections.RequestBuilds/PumpBuilds` list/cache with one selected
  exact-build/DPS/context snapshot. It performs no second catalog walk, DPS
  identity join, final copy, or sort and owns no frame, transport, adapter, or
  SavedVariables access.
- Community renderer extraction is complete: `CommunityRenderer` owns
  `EnsureFrame`, pooled cards/detail rows, scroll binding, status text,
  `NexusPostPopup`, `NexusEditPopup`, and all presentation callbacks. It
  consumes projections and controller intentions but owns no BuildCatalog,
  Sync queue, SavedVariables, or gameplay mutation. `CommunityBuilds` is the
  thin single-instance assembly/delegation facade.
- Wishlist model extraction is complete: one `WishlistModel` instance owns
  family/stack/budget transitions, imported/server draft normalization,
  canonical upload/export entries, locked reconciliation, name trimming, and
  lock-commit planning from captured plain values. Codec remains the EBH1 byte
  owner.
- Wishlist controller extraction is complete: `WishlistController` owns draft
  and fulfilled-target maps, selection/session identity, filter/scroll values,
  EBH1 import/export plans, exact association intentions, Store lock-target
  commits, confirmation payloads, and bounded apply retry. It creates no frames,
  preserves the first spacing payload for at most 12 retry uploads, and writes
  only through injected Adapter/Store owner APIs.
- Wishlist rendering extraction is complete: `WishlistRenderer` owns
  `NexusEditorFrame`, `NexusDisplayPopup`, `NexusScaleSlider`, named switch
  menus and inputs, tooltips, scrolling, and the fixed 19/18 visible-row pools.
  It receives controller projections and emits intentions through owner APIs;
  it owns no SavedVariables, association, upload, gameplay, or transport path.

Community list/detail preparation and interaction state are frame-free behind
`CommunityProjection` and `CommunityController`; all Community presentation,
including post/edit popups and bounded row binding, is isolated in
`CommunityRenderer`. `CommunityBuilds.lua` retains only public delegation and
single-instance assembly. `WishlistEditor.lua` now assembles one pure model,
one frame-free controller, and one complete editor renderer while retaining
public delegation, popup confirmation/import/export intentions, and messages.
Old and extracted model/controller/render paths never run together.

The pre-existing Community spacing-counter limitation was repaired by explicit
product decision in Stage 14.2. One snapshotted payload now accumulates up to 12
retry uploads; spacing cannot reset its lifetime, and expiry performs no
thirteenth retry upload.

## Stage 28 source-only final audit (28.7)

The final offline audit covers exact range
`e6756a2e5fbc1101a931c009193658f28aaf6243..a6b20b594fd104999e39e1c83286673c9d9d9e8d`.
The combined characterization exercised 1,159 builds, 595 DPS rows, 74 Echo
roll states, several thousand Sync packets, mixed legacy/current records, and
multiple peers while preserving Stage 25 automation and Stage 26 convergence,
ownership, tombstone, UI, diagnostic, wire, paging, queue, and compatibility
contracts.

The complete source-only result is 166/166 Lua suites and 483/483 Lua 5.1
parses. All 2,536 functions in 63 TOC-loaded Lua files satisfy the WoW 3.3.5a
60-upvalue limit; the boundary fixture passes at 60 and fails at 61.
`AutomationRuntime.Step` uses 16 upvalues. The highest reviewed production
functions remain the unchanged `ui/Panel.lua` `EnsureFrame` at 60 and
`M.Render` at 58; both stay explicit maintenance-margin advisories rather than
being broadened into this repair.

Boot reaches the registered AutomationRuntime factory, Main resolution, two
polls, and the normal startup banner without a suppressed error. Integration
passes 70/70, the deterministic Sync robustness fixture passes 4,000/4,000,
and exporter determinism, the read-only SavedVariables analyzer, module
inventory, privacy/security, StutterAlert integration, metadata, and Git diff
checks pass. Future TOC-derived packages expose `Author: Valentine` while
upstream Boganic attribution remains preserved.

This receipt is offline evidence only. It does not claim replacement-artifact,
installation, SavedVariables, WoW startup, two-client convergence, or live
performance proof. Test.11 remains the immutable failed live artifact; test.12
creation and every Stage 29 action require separate authorization.

## Deferred live verification (not an offline parity gap)

Complete incoming Sync handling remains synchronous. The 100-message and
1,000-build/1,200-DPS fixtures make aggregate cost attributable and prove
coalescing plus bounded Community/Leaderboard construction, but they cannot
guarantee WoW client frame time. A capped incoming FIFO still requires a new
live trace showing that measured path is expensive. No Stage 17 result
authorizes transport changes, deployment, or deletion/extraction of current
code.
