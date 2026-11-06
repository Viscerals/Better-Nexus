# Client locale and font evidence matrix

Refs #123 (L10N-01). Status: evidence record for the first L10N-01 slice. Source
pin `18dc5b0313033dbc522bec1ab89c304078aa5645` (tree
`6eed3f67c90b98fa7a58e6bccf2e73429b9ffda5`).

Nexus presents English text only at this pin. This record verifies no Project
Ebonhold client locale, locale alias or font glyph coverage. Every per-locale
value below stays UNKNOWN until an exact versioned client/export reference is
supplied, read under `docs/agents/domain.md` and cited here.

## Pinned by the source

| Fact | Value | Where |
|---|---|---|
| Interface | 30300 | `Nexus.toc:1` |
| Client build target | 12340 | `docs/agents/domain.md:24` |
| Lua | 5.1 | `CONTRIBUTING.md:7` |
| Nexus font objects | `NexusFontSmall`, `NexusFontNormal`, `NexusFontLarge` at 10, 12 and 14; face from `STANDARD_TEXT_FONT` when that is a string, otherwise the literal `Fonts\\FRIZQT__.TTF` | `ui/LayoutMetrics.lua:20-25`, `ui/LayoutMetrics.lua:73-91` |
| Blizzard template fonts | Named templates passed to `CreateFontString`, for example `GameFontNormal` and `GameFontHighlightSmall` | `ui/WishlistEditor.lua:547-584`; also `ui/Panel.lua` |

The interface and build numbers identify the client generation that Nexus
targets. They do not establish which locales Ebonhold distributes, which locale
code an installation reports, or which glyphs its fonts contain.

## Exact client/export reference

| Item | Status |
|---|---|
| Versioned Ebonhold client/export reference | ABSENT: none was supplied for this slice, and this checkout has no local `.native-reference/` |
| Export version or manifest hash | none to cite |
| Client locale list | UNKNOWN |
| Verified locale aliases | UNKNOWN |
| Font face per locale (`STANDARD_TEXT_FONT` value) | UNKNOWN |
| Glyph coverage per font | UNKNOWN |

## Locale matrix

Only locales that an exact reference actually lists get a row. No locale code
is added from general knowledge, from other clients or from another addon.

| Presentation | Locale code reported by the client | Evidence | Aliases | Font face | Glyph coverage | Native layout | Kind |
|---|---|---|---|---|---|---|---|
| English source text (current baseline) | UNKNOWN | none | UNKNOWN | UNKNOWN | UNKNOWN | not checked for localization | baseline presentation, not a verified locale |

"Kind" separates an actual client locale from an optional community language.
No community language is proposed.

## Not accepted as evidence

- A reference addon's locale list, locale files or translations.
- General knowledge of retail clients or other 3.3.5a distributions.
- The presence of English literals in the source.
- The offline font models in `tests/prototype/layout_geometry_support.lua`.
  They are models, not native measurement (`docs/UI_TEXT_LAYOUT.md`).

## Locale reads in the source

A text search of every tracked `*.lua` file at the pin for `GetLocale` and
`GetBuildInfo` found them only in `tests/prototype/harness.lua:168-169`. Those
are offline test stubs: `GetBuildInfo()` returns `'3.3.5','12340','Jun 24 2010',30300`
and `GetLocale()` returns `'enUS'`. No runtime Nexus file calls either
function by name. The stub values are test fixtures, not client evidence, and
they verify no Ebonhold locale or build. A text search would not find a call
made through a constructed name.

## Leads for L10N-05

These are review leads, not verified defects. Native measurement takes
precedence wherever the client reports a width or height.

- The fallback face `Fonts\\FRIZQT__.TTF` applies only when
  `STANDARD_TEXT_FONT` is not a string (`ui/LayoutMetrics.lua:77-78`). Its glyph
  coverage on any Ebonhold client is UNKNOWN.
- `ControlWidth` estimates a label from its byte length
  (`ui/LayoutMetrics.lua:560`, `ui/LayoutMetrics.lua:565`), so a multibyte
  UTF-8 character counts more than once.
- `TextRows` and `FitButtonWidth` count UTF-8 characters with a Latin-width
  model (`ui/LayoutMetrics.lua:200-225`, `ui/LayoutMetrics.lua:354-371`).
  Wide-glyph scripts are not modelled.
- Layout code chooses some visible labels itself, for example
  `"Orb mini panel"` or `"Mini"` by available width
  (`ui/LayoutMetrics.lua:432`).

## Updating this record

When an authorized exact reference is supplied, record its version or
manifest hash, add a row only for each locale it lists, and cite the path or
symbol for every value. Keep private client content out of the repository
(`docs/agents/domain.md`). Record native font and layout evidence separately
from offline string checks and from the availability of translated files.

## Deferred

Runtime locale loading, locale selection or preference, translations
(L10N-02 to L10N-06) and native glyph or layout acceptance are out of scope for
this slice.
