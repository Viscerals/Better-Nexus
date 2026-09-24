# Approved terminology and Help changes — P1.5

All 55 grouped proposals (T01–T50 and H01–H05) are addressed below.
Stable identifiers, raw diagnostic reasons, policy logic, codecs, saved-data keys, and file/API names are not globally renamed. Player-facing interpretation changes do not make a rejected operation pass. Newly added Orb messages use the same vocabulary. Native text layout/hit-testing remain unverified.

| ID | Implementation | Source |
|---|---|---|
| T01 | Build Library, server My Builds/Saved Build, selected loadout, desired Wishlist and Snapshot defined separately. | `ui/Panel.lua`, `ui/WishlistEditor.lua`, `ui/JournalTab.lua`, `ui/Help.lua` |
| T02 | Assignment/unassignment explained separately from creating, saving or activating; underlying ownership unchanged. | `core/WishlistController.lua`, `ui/JournalTab.lua`, `ui/WishlistRenderer.lua`, `ui/Help.lua` |
| T03 | Zero-slot first run, unavailable and empty-numbered-slot labels distinguished without changing branch selection. | `ui/JournalTab.lua` |
| T04 | My Builds/Open My Builds labels describe navigation rather than promising activation. | `ui/Panel.lua`, `ui/JournalTab.lua` |
| T05 | Set up current build, Import/Create Wishlist, Browse Community builds; no proven-build claim. | `ui/QuickStart.lua` |
| T06 | Current permanent Echoes are counted/displayed; false never-lock/unlock claim removed. Optional automation documented separately. | `core/MainDiagnostics.lua`, `ui/Help.lua` |
| T07 | Current permanent Echoes, permanent-slot targets, frozen offers, read-only Echo list and position-lock vocabulary distinguished. | `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua`, `ui/WishlistOverlay.lua`, `ui/Help.lua` |
| T08 | Automatic permanent-slot text requires both master Automation and the separate option plus validated ownership/capability. | `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua` |
| T09 | Replacement tooltip/notice avoids promising automatic lock changes merely after target selection. | `ui/WishlistRenderer.lua`, `core/WishlistController.lua` |
| T10 | 79 rolled copies plus six permanent-slot targets; save count clearly separate from designed targets. | `ui/WishlistEditor.lua`, `ui/WishlistRenderer.lua`, `core/WishlistController.lua`, `ui/Help.lua` |
| T11 | Permanent-target confirmation terminology; source/role preservation unaffected. | `ui/WishlistRenderer.lua` |
| T12 | Current-lock default explained as matching intended targets; existing confirmed plans are not rewritten. | `core/Main.lua`, `ui/WishlistRenderer.lua`, `ui/Help.lua` |
| T13 | Resolvable permanent-target choice separated from waiting for actual server lock data; raw detail retained, no advice to delete original Wishlist. | `core/UserText.lua`, `core/WishlistController.lua`, `ui/WishlistRenderer.lua` |
| T14 | Unconfirmed-save branch now says request sent, confirmation missing; confirmed branch still requires confirmation. | `core/AutomationRuntime.lua` |
| T15 | Wishlist import code instead of unexplained EBH1; Nexus-only role-marker distinction documented. | `ui/WishlistEditor.lua`, `ui/Help.lua` |
| T16 | Open imported draft; import/save/assignment separate actions. | `ui/WishlistEditor.lua`, `core/WishlistController.lua` |
| T17 | Invalid build/plan/stale draft gives a known reason/action and preserves raw detail without forcing acceptance. | `core/UserText.lua`, `core/WishlistController.lua` |
| T18 | Automation master permission and per-action spending/slot effects explained. | `ui/Panel.lua`, `core/Main.lua`, `ui/Help.lua` |
| T19 | Player action labels omit the engine suffix; the engine is named in About and in the documentation. | `core/UserText.lua`, `ui/Readout.lua`, `ui/Help.lua` |
| T20 | Normal recommendation lines use need/category descriptions rather than unexplained signed priority numbers; diagnostics remain intact. | `ui/Readout.lua`, `ui/Help.lua` |
| T21 | Off-Wishlist picks explained without claiming every choice is correct or guaranteed to be replaced. | `ui/Panel.lua`, `ui/Help.lua` |
| T22 | EXTRA COPIES and complete explanatory tooltip; no delete or future replacement promise. | `ui/Panel.lua`, `core/Main.lua`, `ui/Help.lua` |
| T23 | Permanent targets remaining in place of TO LOCK. | `ui/Panel.lua`, `ui/WishlistRenderer.lua` |
| T24 | Waiting for current Echo data is distinct from shared-build network Sync. | `core/UserText.lua`, `core/MainDiagnostics.lua`, `ui/Help.lua` |
| T25 | Saved-build guarantee confirmation language replaces armed/unarmed on normal display; raw states remain support evidence. | `core/UserText.lua`, `core/Main.lua`, `ui/Help.lua` |
| T26 | Expected later/held offer/remaining-choice language; predictions distinguished from confirmed live-card guarantees. | `core/UserText.lua`, `ui/Readout.lua`, `ui/Help.lua` |
| T27 | Charge names and overlay symbol legend supplied; diagnostic abbreviations retained as stable support format. | `ui/Panel.lua`, `core/Main.lua`, `ui/Help.lua` |
| T28 | Advanced assumption and Echo-availability control terms explained; raw IDs preserved when a reliable display name is unavailable. | `core/Main.lua`, `core/UserText.lua`, `ui/Help.lua` |
| T29 | Server-reported availability explanation replaces categorical claims that Nexus cannot be wrong. | `ui/Panel.lua` |
| T30 | Ordinary rolling waits during Orb-owned/unknown states; real Orb mode uses a distinct permitted path. | `core/UserText.lua`, `core/GameAdapter.lua`, `ui/Help.lua` |
| T31 | Both DPS records / missing required records; no qualification-as-quality implication. | `ui/CommunityRenderer.lua`, `ui/QuickStart.lua`, `ui/Help.lua` |
| T32 | Both records plus explicit highest-single-result ranking and display-only average explanation. | `ui/Leaderboard.lua`, `ui/Help.lua` |
| T33 | Known/shared record language without claiming a live connection or universal best result. | `ui/Nameplate.lua`, `ui/Leaderboard.lua`, `ui/CommunityRenderer.lua`, `ui/Help.lua` |
| T34 | Share Build vocabulary and local save/server-save distinction. | `ui/CommunityRenderer.lua`, `core/CommunityController.lua`, `ui/Help.lua` |
| T35 | Stop Sharing/removing a shared record differs from server My Builds deletion; exact action semantics retained. | `ui/CommunityRenderer.lua`, `ui/Help.lua` |
| T36 | Read-only Echo list tied to DPS records, not a permanent-lock metaphor. | `ui/CommunityRenderer.lua`, `core/CommunityController.lua`, `ui/Leaderboard.lua` |
| T37 | DPS records versus runtime Performance diagnostics. | `ui/Panel.lua`, `ui/LogViewer.lua`, `core/MainDiagnostics.lua`, `ui/Help.lua` |
| T38 | Request full Echo list; copying opens a draft and does not activate/spend. | `ui/Leaderboard.lua`, `ui/CommunityRenderer.lua`, `ui/Help.lua` |
| T39 | Missing/older/class/record mismatch display language; raw fingerprints and support fields are not rewritten. | `ui/CommunityRenderer.lua`, `ui/Leaderboard.lua`, `core/UserText.lua` |
| T40 | Preparing, sent, receiving, cleaning-expired and completion remain distinct; underlying transport unchanged. | `core/Main.lua`, `core/MainDiagnostics.lua`, `ui/Panel.lua`, `ui/CommunityRenderer.lua`, `ui/Leaderboard.lua`, `ui/Help.lua` |
| T41 | Plain-language loading phases replace build identities/commit jargon; no fake readiness or scheduler changes. | `ui/LoadingStatus.lua` |
| T42 | This-step percentage and local versus shared availability explicit; no overall ETA promise. | `ui/LoadingStatus.lua`, `ui/Help.lua` |
| T43 | Advanced troubleshooting commands explained as specific effects, not generic fixes. | `core/Main.lua`, `ui/Help.lua` |
| T44 | Prepare full diagnostic report / Select this page; complete copy requires pages in order. | `ui/LogViewer.lua`, `core/MainDiagnostics.lua`, `ui/Help.lua` |
| T45 | Recent choices, manual overrides, status, permanent-slot actions, performance and advanced peer diagnostics. | `ui/LogViewer.lua`, `core/MainDiagnostics.lua` |
| T46 | No guarantee that export will avoid hitches; large reports may take a moment. | `core/MainDiagnostics.lua`, `ui/LogViewer.lua` |
| T47 | Recommendation wording and server-supported activation limits; no claim every Wishlist is a Snapshot. | `ui/Readout.lua`, `ui/Help.lua` |
| T48 | Known-condition explanations with retained Details/raw codes, not arbitrary suppression or validation bypass. | `core/UserText.lua`, `core/Main.lua`, `core/WishlistController.lua` |
| T49 | Save comparisons use gained/fewer matching copies; separate from the EXTRA COPIES panel. Raw Ratchet reason strings retained. | `core/AutomationRuntime.lua`, `core/UserText.lua`, `core/MainDiagnostics.lua` |
| T50 | Concrete player-task description including optional Orb refinement; experimental limitations and provenance separate. | `Nexus.toc`, `core/Main.lua`, `ui/Help.lua`, `README-PROTOTYPE.md` |
| H01 | Persistent Help/Getting Started controls and seven pages, no mandatory wizard. | `ui/QuickStart.lua`, `ui/Panel.lua`, `ui/Help.lua` |
| H02 | /nexus help/guide/tutorial reopen real guide, not just a terse command list. | `core/Main.lua`, `core/MainCommands.lua`, `ui/Help.lua` |
| H03 | Early help/orbs/loader routing; reroll/freeze/currentlocks/prototype and Orb control meanings documented. | `core/MainCommands.lua`, `ui/Help.lua` |
| H04 | Current P1.5 install/user guide replaces mixed old instructions; full older README preserved only in source history. | `README-PROTOTYPE.md` (the older README is in Git history; its tracked copy was retired on 2026-09-24) |
| H05 | Current P1.5-specific changelog and seen key; no unsupported faster/migration guarantee. | `ui/Changelog.lua` |
