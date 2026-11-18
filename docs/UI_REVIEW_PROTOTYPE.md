# UI review prototype (issue #163)

Status: bounded private prototype, offline-checked only; the full issue #163
redesign is **not complete**. Base: `34229edf0fd2`; the reviewed prototype
source was `f1351f8a9`. A successor branch addresses review findings. The
exact final successor pin and its validation belong in the companion handoff
receipt outside this source tree, because a tracked file cannot cite its own
commit hash. Native client behaviour, pixels, font
coverage and contrast are **NOT RUN**. The review's mockups were HTML, not WoW
frames. Its screenshots covered setup fragments only, so no full-addon visual
audit exists.

## What changed

- **Status vocabulary** (`ui/Readout.lua`): `STATUS_KINDS`, `StatusParts(kind)`,
  `StatusText(kind[, detail])` and `CountText(value[, estimated])`. Each state
  has a glyph and a word. An unlisted kind reads `? Unknown`. A missing,
  invalid, negative or infinite count reads `?`, never `0`, and an estimate
  reads `~N`. The glyphs are ASCII because the client fonts' coverage of
  other symbols is not established. `?` and `~` were already used by
  `ChargesLine`. `Readout.lua` stays a pure formatter.
- **Orb history** (`ui/OrbHistory.lua`): each recorded result also carries its
  vocabulary kind (`status`). The labels and the visible cells are unchanged.
  An unrecorded state is `unconfirmed`.
- **`...` menu** (`ui/Panel.lua`, `M.MoreMenuItems`): titled groups (Help and
  setup, Settings, Notices, Logs, Also on the panel footer, Panel). Earlier
  entries keep their labels and destinations; Hide also prints confirmation
  in chat. The new entries are
  **Support report...** (`/nexus report`'s page) and **Log viewer...**
  (`/nexus log`). **Hide Nexus Panel** says in chat that hiding does not turn
  Nexus off or change Auto, and how the panel comes back.
- **Footer** (`ui/Panel.lua`, `LayoutFooter`): **Auto** keeps its place and
  size and stands apart. After it come three hubs. **Plan** opens a stock
  dropdown with Wishlist Editor, Assign Wishlist... and My Builds (game page).
  **Explore** opens one with Build Library and Leaderboard, the shared-data
  state and the best-known scope. **Orbs** opens the Orb window. The Build
  Library and Leaderboard footer buttons are replaced by Explore, which
  greys while shared data loads, as they did. The header **My Builds** button
  and the setup **Assign Wishlist** button now call the same named routes
  (`M.OpenMyBuilds`, `M.OpenAssignment`), with unchanged bodies.
- **Hub hovers** (`M.HubTooltipLines`): the Orbs hover reads the passive Orb
  reason view only after local start-up (`M.OrbHubLine`). An unread state is
  unknown. A live pending offer is not called a result; a pending result is
  "Awaiting result", and an earlier action restored after a reload is
  "Unconfirmed" without assuming an offer or result occurred.
  The Explore hover reads the start-up snapshot
  (`M.SharedDataLine`).
- **Copy**: Help (Sharing, Orbs), `README-PROTOTYPE.md`, and the prepared
  support report notice ("Nexus does not reload or log out for you").

No new hub or menu route directly assigns, saves, shares, removes, spends,
loads a Saved Build or turns Auto ON. Opening the existing Orb window may
initialize its runtime status and passive observation in memory; that is not
a confirmed spend or a guarantee of zero state changes. No controller,
threshold, timer, queue or permission was added or changed. `EnsureFrame`
gains no upvalue: new handlers reach the module through `M`.

## Recommendation status

| Recommendation | Status |
| --- | --- |
| P1 shared glyph + word statuses; unknown never 0 | Partial: vocabulary module and two hub/status lines. `CountText` and the added Orb result kind are not yet rendered elsewhere; existing panel strings keep their words. Full-surface glyphs and native font fit remain open. |
| P1 requested vs confirmed, sent vs stored, proposed vs actual | Partial: existing Orb history labels, `(proposed)` text, usage/pending lines and Share/Stop Sharing outcomes. The design's separate timeline and columns are not implemented. |
| P1 "Best known" scope wording | Existing (`UserText.RECORD_SCOPE`); also stated in the Explore hub. |
| P2 group navigation; keep old labels | Partial: titled top-level groups in the stock dropdown. This keeps old labels findable, but is a deliberate deviation from nested submenus and makes the menu taller. Native fit remains open. |
| P2 status lines under Settings > Notices | Partial: Notices is a peer top-level group, not a Settings submenu. |
| P2 nested Plan/Explore submenus in `...` | Replaced by one-click footer hub dropdowns; the proposed overflow nesting remains unimplemented. |
| P3 footer Plan / Explore / Orbs; Auto apart | Partial: the three hubs are present; Auto stays in the footer with a gap. The design's header Auto chip remains open. |
| P3 header line two: Saved Build and Wishlist with full tooltips | Partial existing destination row; the design's Wishlist Change link is absent. |
| P3 header line one: Auto chip and close button | Deferred. The destination header geometry (`LayoutMetrics.Panel` header lines) is pinned by its readability and label tests. Moving it needs its own accepted successor and a native check. |
| P3 objective two-line wrap / clipping | Deferred to its separate investigation; no cause is assumed. |
| P4 Plan and Explore as tabbed workspaces | Deferred. The hubs reuse the existing windows instead. |
| P4 consequences at Create/Save/Assign/Share/Remove/Auto/Orb | Partially present in existing editor/Auto/Orb flows. This prototype did not independently audit every consequence or verify an exact Share payload preview. |
| P4 Orb close is not pause | Existing (Orb window notice, mini panel Close hover); repeated in the Orbs hover. |
| P4 support report save boundary | Existing; one sentence added. |
| P4 Changelog entry in the menu | Blocked: `ui/Changelog.lua` has no manual open route. |
| P4 single Settings window | Deferred. Settings are menu-only today; no window is invented. |
| P5 Vista + Amethyst default, Slate + Graphite, Ember, no reset | Existing (`ui/Theme.lua`); unchanged. |
| P5 contrast at the default UI scale | Unverified: needs an in-game measurement. |
| Guided setup | Separate track; Help > Setup / Welcome and the checklist routes are kept, not duplicated. |

## Native checks still needed

- The footer at 272 px: hub labels at font scale 1.25 and above. The new labels
  are English literals, so translated label fit cannot yet be tested. Widths
  come from the offline model only.
- How the ASCII glyphs read in the client fonts.
- Dropdown item tooltips (`tooltipTitle`) show only with the client's beginner
  tips on. The consequence of each hub entry is therefore also a visible
  disabled row.
- Esc, dropdown layering and keyboard reachability of the hub menus.
- Exact native FrameXML reference for the 3.3.5a `EasyMenu`,
  `UIDropDownMenuTemplate` and `UIPanelButtonTemplate` behaviour was **not
  consulted** for this successor. The target remains WoW 3.3.5a client build
  12340 / interface 30300. Record a versioned reference or a native test before
  treating stock-menu placement, disabled rows or tooltip timing as accepted.

## Version of a test package

The repository keeps the build-neutral `Release.version`. The verified private
`test.163001-f1351f8a9` package was produced by `tools/build_package.py`
without `--public` and stamped an `internal` TOC label. Any successor package
needs its own build, content and checksum receipt; packaging alone does not
verify Sync or update comparison in the client. See `docs/UPDATE_NOTICES.md`.

## Tests

`tests/prototype/ui_review_navigation.lua` covers the vocabulary, the menu
groups and kept labels, the footer geometry with and without Auto, the hub
routes (spied owners, real Orb window), the status lines under stubbed passive
sources, the Help copy, the support notice, and no actions, sends, saved-data
or assignment changes on its measured routes. The `f1351f8a9` prototype
passed 562/562 LuaJIT tests and both registered Python suites (8 inventory,
76 catalog methods); this is the prior source receipt, **not** final successor
validation. The final-pin CI/package results and independent review are
recorded outside the checkout. Native testing remains **NOT RUN**.
