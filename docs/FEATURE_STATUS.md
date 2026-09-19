# P1.5 integrated prototype — feature status

This is the terminology/help and Orb-refinement successor to the exact supplied
P1.4 source. It is not a new merge of the user's separate T3 branch.

| Feature | Status |
|---|---|
| Ordinary LoadoutPilot-derived rolling, Snapshot distinctions, resource guards | Retained; original 10,000-case policy comparison and real-action tests retained |
| Wishlist retry fix, ownership-cache fix, explicit/current-lock-default role handling | Retained; prior editor/reload regressions retained |
| Startup, local tools during shared loading, current-phase progress display | Retained; existing startup tests and readiness behavior retained |
| Community, DPS, Leaderboard and existing Sync | Retained; terminology updated, underlying storage/transport/ranking not redesigned |
| 55 approved terminology and help groups | Implemented in player-facing labels, messages, guides, and documentation; internal protocol and diagnostic identifiers retained |
| Persistent Help | Seven pages, main/Welcome entries, pre-ready help/guide/tutorial commands |
| Orb/Lost Memories refinement | Implemented full single-Orb spend/offer/select/confirm/continue loop; explicit source pool, run cap, optional recycling, Pause/Resume/Stop, passive restart reconciliation |
| Orb client capability | Read-only discovery and unavailable reason; cannot establish actual client/server behavior without native testing |
| Orb same-ID and ambiguous outcomes | Fresh-response/one-Orb/diff reconciliation; no automatic mutation replay; unresolved exposure remains reserved |
| Native UI click/layout, Orb operation, game resources, performance | NOT TESTED |
| Original upstream inventory, LuaJIT/plain Lua 5.1, hosted CI, fresh independent review | NOT RUN for P1.5 |
| Runtime used for offline prototype checks | Lua 5.4 with test-only compatibility shims |
| Full historical architecture acceptance and old player-video attribution | Not claimed; unchanged deferred obligations remain |

See P1_5_TERMINOLOGY_IMPLEMENTATION.md for all approved IDs, ORB_MEMORY_MODE.md
for the actual lifecycle and adaptations, and README-PROTOTYPE.md for the current
user procedure. Older P1.x notes are preserved as historical evidence.
