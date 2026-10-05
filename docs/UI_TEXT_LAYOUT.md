# UI text and layout policy

Natively, the Open Build detail drew its BEST RECORDS rows and the Details!
note below its panel and window. The panel follows the responsive Community
layout (about 410 px high in the default 1040x640 window), but that content
kept fixed offsets down to y=-512. The Leaderboard cut a Copy/Open refusal to
one 305x18 line. Both were reported from native screenshots. This change fixes
them and applies the same small policy where a source audit found text that
could be cut, overlap a neighbour or leave the window.

## Policy (`ui/LayoutMetrics.lua`)

- **Flowed detail views.** A detail view has a fixed heading, a fixed action
  row and, between them, a scrolled body. The body is exactly as tall as its
  content, measured by the client (`WrapHeight`). The Open Build detail and
  the Leaderboard detail use this. The Leaderboard status text sits above its
  actions and wraps in full. It is capped only above 35% of the panel
  height, and then its tooltip carries the whole text.
- **Fixed row labels** (menu rows, pickers, selectors, role rows) keep one
  line at the row height (`OneLineLabel`). The client shortens the rest. While
  a label is shortened, the row's tooltip shows the complete text. If the row
  already has a tooltip, the complete text is added to it.
- **Fixed multi-line boxes** that must keep their size (Orb status and notices,
  Continue, support report, log viewer status) keep it. While their text
  overflows, a hover area shows the complete text (`FullTextTooltip`).
- **Labels that may grow** take their measured height, and what follows moves
  down: the release note, the loading status, and the On-Screen Wishlist
  settings.
- **Buttons whose label changes** are sized to their label (`FitButtonWidth`).
- **Fixed-size windows wider than the visible UI** are scaled to fit
  (`FitToScreen`). At scale 1 the UI is 1024 px wide on 4:3 screens and 960 px
  on 5:4 screens. This applies to the Wishlist editor and the Leaderboard.
- One-line boxes are at least one 17 px line tall. That is the conservative
  line of a replacement face; the face measured natively for the Quick Start
  fit had 16.1 px lines.

Spell, identity and full-title tooltips are unchanged. Text is not sanitised
any differently. Data, identity, Sync, selection, request counts, button
enablement and actions are unchanged.

## Offline evidence

`community_detail_layout`, `leaderboard_detail_layout`,
`wishlist_menu_label_layout` and `text_overflow_policy` drive the real windows
with synthetic data. The text includes an 80-byte wide title, accented names,
a 2000-byte description, a 2024-byte link, 79 + 6 Echoes and the longest
refusal states. The checks run at several effective UI sizes and font models:
the default face, a 16 px face, and font scales 0.75 and 2. They resolve the
real anchors into rectangles and check that content stays inside its frame,
does not overlap, keeps every wrapped line, has a scroll range that reaches
the last line, and recovers the complete text. The font models are offline
models (`tests/prototype/layout_geometry_support.lua`), not native font
measurement.

## Native status

NOT TESTED. Pixel fit, scroll bars, tooltips and clicks in the game client
still need a native check of each window family at the supported scales.
