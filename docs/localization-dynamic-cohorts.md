# Dynamic localization: first cohort and remaining work

This first cohort moves two existing wait meanings and the compact charge row
through the reviewed English seam. Panel owns conversion of its raw status and
recommendation. It does not complete every dynamic window, ship seven language
packs, or establish native font fit or fluent-speaker acceptance. The selected
language set is enUS, frFR, deDE, esES, plPL, ptBR and ruRU; only the English base
and explicitly injected synthetic candidates are exercised here.

## Classification and ownership

| Text or token | Classification | Producer, consumer and conversion owner |
| --- | --- | --- |
| `waiting for three-card board`, `waiting for pending-pick count` | Invariant producer inputs, coupled to visible rewrite | `logic/EchoWeaver.lua` emits the exact reasons; `core/UserText.lua` maps them to `reason.wait_three_choices` and `reason.wait_pending_pick_count`. Panel presents once. Never translate the producer reason or matching key. |
| `ROOT_MUTATION_PENDING`, `CURSOR_REQUIRED`, `STORE_PENDING` | Invariant producer inputs, coupled to visible rewrite | Existing Main/Store runtime codes map through UserText to `reason.save_in_progress`, `reason.list_preparing`, `reason.saved_data_reading`. Their English messages remain unchanged. |
| Six semantic keys, including `readout.charge_counts` | Invariant lookup/schema identities | `data/LocalizationEnglish.lua` owns the English values; `core/Localization.lua` owns validation, base fallback and count substitution. A candidate may replace only an admitted English key. |
| Five English reason messages and valid candidate messages | Visible output | `Localization.Text` returns exact scalar-text bytes. UserText carries validated base/candidate provenance to Panel; an unavailable message with a raw Details suffix has no such provenance. |
| `waiting: `, `L<n> -- `, `L%d`, `TARGET:`, `ARMED`, `UNARMED`, and other legacy `Message` patterns | Coupled producer/rewrite pairs | Runtime reason compositions and UserText's legacy rules must be changed together in a later cohort. They remain raw matching inputs. Reviewed candidate output is never passed through those rules a second time. The code-owned level prefix retains the scalar-text length check. |
| `B:{banish} R:{reroll} F:{freeze}` and reordered candidate rows | Visible whole-row template | `Readout.ChargesLine` normalizes only the supplied facts, builds typed known/unknown slots, calls `Localization.Format`, then appends the estimate marker. If English is unavailable it uses the exact code-owned legacy builder with those same observations. |
| `banish`, `reroll`, `freeze`, `known`, `value` | Invariant schema/field identities | Code-owned named count slots; translations may reorder placeholders, never change their type or meaning. Unknown is represented explicitly, not filled with an invented zero. |
| `{name}`, `{{`, `}}`, `%` | Template syntax / literal visible bytes | Localization parses each placeholder once. Doubled braces are literal braces; percent bytes are literal and are never a formatting operation. Control bytes, pipes, malformed UTF-8 and over-limit text are rejected. |
| `?`, ` ~` | Code-owned visible output | Readout owns unknown and estimate semantics. The marker follows the complete row, with two bytes reserved by the schema. No count policy or server observation is changed. |
| `Status: `, `Menu and status`, `Charges`, and existing legend paragraphs | Visible output, still English | Panel's actual menu hover exposes the committed status. The charge hover exposes the complete current row followed by the existing legend. Recommendation overflow uses `LayoutMetrics.FullTextTooltip`. These labels and the legend are not claimed translated. |
| `B, R and F` in `ChargesLegend` versus translatable row abbreviations | Coupled row/legend pair, remaining work | `ui/Readout.lua` owns both. A later cohort must translate/explain the legend and abbreviation vocabulary together; the reordered fixture is not language acceptance. |
| `_nexusPanelPresentation`, its `version`, `raw`, `text`, and `_nexusChargeLine` | Invariant in-memory presentation metadata | Panel owns these names. They are not saved settings, protocol fields or producer decisions. The namespaced raw/text record is shape-checked without record metamethods. The generic producer field `presentation` is retained and ignored. |

## Public Panel contract

`Panel.Render(model)` accepts raw `status` and `recommendation`. Its committed
copy exposes presented text under those same fields and an owned
`_nexusPanelPresentation` record. Rendering a committed model or copy re-presents
each unchanged field from its own recorded raw value. Equality with that field's
valid record takes precedence over an identical-byte raw override. A raw caller
copying a committed model removes `_nexusPanelPresentation` to declare raw intent.
Malformed, foreign, nonplain or ill-typed records are ignored.

`Panel.SetStatus(status)` always takes raw text. Even when the resulting visible
bytes are unchanged it refreshes raw provenance, returns false and does no layout.
Reserved-roll release and refused Auto-click renders retain the recorded raw
source. Owned localization provenance is committed separately from caller model
metadata and tied to the actual displayed bytes. The actual menu hover revalidates
that result under Localization's scalar-text rules; other raw/untrusted statuses
retain Identity's display gate. Identity itself is unchanged. No locale, font,
client setting, saved key, gameplay action or network rule changes here.

## Remaining dynamic cohorts for tickets 04–06

- Remaining EchoWeaver/Policy waits: assignment, action confirmation, exact
  targets, locked Echo state, unavailable planner and absent/irregular boards.
- Runtime compositions: level prefixes, wait action/type, paused reasons,
  finishing-run counts, save destination/check duration, SelectWait and world
  holds. Convert complete sentences with their raw producer/rewrite pairs.
- `AutomationRuntime` SelectPoll pre-conversion, `Effective`,
  `Readout.AutoHoldText`/`AutoHoldNote`, and Panel Auto-tooltip pre-conversion.
  They are outside this first cohort and must share a raw presentation boundary
  when their meanings are localized.
- `Readout.Status`: level text and its separate second charge line still use
  legacy English formatting; it has a different knownness contract.
- `ChargesLegend` abbreviation/translation coupling; CardLine annotations,
  recommendation target composition, `+N more`, queue labels and predictions.
- Per-language plural/grammatical rules, count forms, complete annotation
  templates, dates/times, remaining window families and real pack selection.

The existing three-card wait also covers any board whose length is not exactly
three, including malformed or oversized boards. The pending-pick wait covers
unavailable and invalid horizons; zero is a valid horizon. Their exact English
bytes are retained; linguistic improvements require separate acceptance.

## Upstream count and evidence limits

`GameAdapter.Charges` already normalizes some absent per-field data to zero once
either banish or reroll data has arrived. A partial push `{remainingBanishes=5}`
can therefore yield `B:5 R:0 F:0`; a freeze-only push may still be wholly unknown.
Ledger minima and dead-latch zeros are policy estimates, not proof of fresh
server counts. The first-cohort consumer preserves the adapter's supplied
evidence and does not repair that upstream knownness contract. The partial-push
regression characterizes the limitation; it is not end-to-end server acceptance.
A separate display-only knownness/adapter task needs its own scope.

Count rendering retains the legacy `tostring` numeric behavior, including huge
numbers/exponent notation and runtime precision limits. No arbitrary cap or
overflowing integer formatter is introduced. Offline LuaJIT checks establish
exact bytes under that runtime; they do not establish every Lua numeric/API
variant, native glyph rendering, pixel fit, frame timing or language fluency.

The test observer checks listed modeled mutation APIs, Sync admissions and
sends, chat/print, transient popup events, actual warning state, nonempty
assignment tokens, settings, Auto choice and known scheduler boundaries. Its
setup calls `Sync.Stats` once (that getter updates diagnostic metadata), then
reads the live numeric admission counter. Matched real Policy inputs, raw Render
models and time constrain producer comparisons. Fixture `H.Board` delivery is
outside the explicit `RefreshPanel` window. Legitimate producer logging and
maintenance are allowed; there is no general no-side-effect guarantee for
unmodeled clients or arbitrary deferred queues.
