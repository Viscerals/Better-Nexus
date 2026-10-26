# #163 Plan and Explore workspace integration

This change makes the existing Wishlist Editor the **Plan** tab and the
existing Build Library and Leaderboard the **Explore** tabs. It is a tabbed
collection of three real windows, not one frame with its children reparented.
Each controller retains its own scroll/filter/draft/confirmation lifecycle.
The top navigation is consistent across all three windows, with Plan,
Explore and Records tabs and full view names in the window title or tooltip.
Help remains on the same row. At 800x600 the existing responsive window
layout keeps this row inside the frame.

`ui/FullUIWorkspaces.lua` supplies `Nexus.FullUIWorkspaces.ShowPlan()`,
`ShowExplore()` (Build Library), `ShowExplore("records")`, and `Show(kind)`.
`BindTabs` links the real windows. `NavigateFrom` opens the destination first;
if shared data are pending, the source remains visible. Once the destination
is actually shown, the source closes and its existing transient cleanup runs.
Opening or switching a workspace performs no Save, Sync, assignment, sharing,
Auto or Orb action; those retain their original explicit buttons and guards.
Build Library may initialize its local filter preference on first view, as it
did before this change.

Integration must load the new module from `Nexus.toc` before any of these
three windows is first constructed. The module has no load-time dependency on
the facade files. The panel's Plan/Explore hubs should call `ShowPlan()` and
`ShowExplore()` with their existing fallback while the module is optional.
The coordinator owns those TOC and panel edits.

`tests/prototype/full_ui_workspaces.lua` covers the real window routing,
selected tab, pending-data fallback, source dismissal, narrow nav geometry,
close behavior and consent/assignment invariants. It is an offline LuaJIT
fixture, not native font, screen-reader or in-game acceptance. A 420px-wide
single-frame layout and the rest of the full #163 design are outside this
module; this integration should not be described as the full overhaul alone.
