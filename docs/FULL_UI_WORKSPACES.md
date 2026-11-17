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
`BindTabs` links the real windows. `NavigateFrom` opens the destination first.
If shared data are pending, `CommunityBuilds.WaitForStartup` replaces the
source with its guarded `NexusSharedStartupFrame`, which has a close control
and an enabled **Use local Wishlists** return when local data are ready. The
workspace API reports this as `true, "loading"`, not a completed shared view.
Once a ready destination is shown, the source closes and its existing
transient cleanup runs.

Plan tab departure captures the real player GUID and known native/selected
Saved Build context. Returning through Plan or the loading surface resumes
that exact controller draft without calling `BeginShow` again. Save
confirmations and confirmed retries block departure rather than being
cancelled by the editor's normal `OnHide`. If character/selected Saved Build
changes while away, Plan asks for explicit discard before opening a new
context; the old draft is not silently replaced. The Plan view also exposes
**Assign...** and **My Builds (game)** controls routed through the Panel's
existing guarded methods. Opening them does not select a Wishlist or activate
a Saved Build. While an unsaved Plan draft is suspended, unrelated explicit
New/Open/Import routes refuse to replace it until the player returns to Plan.
Opening or switching a workspace performs no Save, Sync, assignment, sharing,
Auto or Orb action; those retain their original explicit buttons and guards.
Build Library may initialize its local filter preference on first view, as it
did before this change.

Integration must load the new module from `Nexus.toc` before any of these
three windows is first constructed. The module has no load-time dependency on
the facade files. The panel's Plan/Explore hubs should call `ShowPlan()` and
`ShowExplore()` with their existing fallback while the module is optional.
The coordinator owns those TOC and panel edits.

`tests/prototype/full_ui_workspaces.lua` covers real startup-pending
transitions, loading-surface return, unsaved Echo draft retention, context
change confirmation, Save guards, Plan action routing, narrow nav geometry,
close behavior and consent/assignment invariants. It is an offline LuaJIT
fixture, not native font, screen-reader or in-game acceptance. A 420px-wide
single-frame layout and the rest of the full #163 design are outside this
module; this integration should not be described as the full overhaul alone.
