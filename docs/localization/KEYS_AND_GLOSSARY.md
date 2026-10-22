# Translation keys, context and English terms (proposal)

Refs #123 (L10N-01). Status: proposal for review. Nothing here is
implemented: no key table, loader, locale or preference exists. L10N-02 and
L10N-04 decide the runtime form.

This is a localization reference. It is not the domain glossary: root
`CONTEXT.md` remains the place for domain terms (`docs/agents/domain.md`), and
this document creates none.

## Keys

1. **Shape.** Every segment is ASCII lowercase letters and digits, starting
   with a letter, with words inside a segment joined by `_`. Segments are
   separated by dots. A key has exactly one of two forms:
   - **Window-family key:** `<family>.<surface>.<meaning>`, three segments,
     in that order.
     - Families follow [INVENTORY.md](INVENTORY.md#window-families): `panel`,
       `setup`, `help`, `consent`, `orb`, `journal`, `editor`, `overlay`,
       `library`, `leaderboard`, `unit_tooltip`, `loading`, `support`, `log`,
       `release_note`.
     - Surfaces: `title`, `heading`, `label`, `button`, `tooltip`, `status`,
       `body`, `error`.
     - A disabled reason that belongs to one window uses that window's
       `status` or `tooltip` surface.
   - **Shared-group key:** `<group>.<meaning>`, two segments. It is for text
     that several families show, where the calling code chooses the surface.
     - Groups: `chat`, `reason`, `term`, `count`.
     - A reason mapped from a code, a reference term and a count unit each use
       their group.
   - No family name is a group name, so the first segment alone tells which
     form a key has. `<meaning>` is always one segment.
2. **Meaning, not wording.** A key never comes from the English text.
   Rewording the English keeps the key; a changed meaning gets a new key.
3. **Codes stay codes.** A reason or policy code maps to its key through one
   explicit table. The code keeps its spelling in data, protocol and
   diagnostics (`core/UserText.lua:1-2`). A key is never built from a code's
   text, from user text or from game data.
4. **Whole sentences.** One key per complete sentence or label. Fragments
   joined at run time, such as `"  +" .. n .. " more"` (`ui/Panel.lua:381`),
   become one template.
5. **English base.** The English text of a key is the current source text,
   verbatim. Adopting keys must not change English output (L10N-02 acceptance).

Illustrative mapping (not implemented):

| Proposed key | English base | Source |
|---|---|---|
| `help.title.start_page` | Getting started | `ui/Help.lua:8` (page `id="start"`) |
| `setup.title.welcome` | Welcome to Nexus | `ui/QuickStart.lua:184` |
| `consent.body.overwrite_risk` | Auto can overwrite your active game Saved Build. … | `ui/OverwriteWarning.lua:6` |
| `consent.body.keep_auto_off` | Choose No to keep Auto OFF. Opening this warning does not enable Auto. | `ui/OverwriteWarning.lua:7` |
| `orb.status.refresh_failed` | Orb panel refresh failed. Controls are unavailable. | `ui/OrbPanel.lua:346` |
| `panel.tooltip.locked_remaining` | Locked targets remaining | `ui/Panel.lua:370` |
| `panel.tooltip.more_count` | +{count} more | `ui/Panel.lua:381` (now a fragment) |
| `reason.save_in_progress` | Saving is still in progress; wait for its final result | mapped from code `ROOT_MUTATION_PENDING`, `core/UserText.lua:31` |
| `count.run_copies` | rolled copies this run | `COUNT_UNITS.run`, `core/UserText.lua:238` |
| `term.my_builds` | My Builds | `core/UserText.lua:332` |

The first seven rows are window-family keys and the last three are
shared-group keys. The reason key names the meaning, not the code (rule 3); the
mapping table pairs `ROOT_MUTATION_PENDING` with `reason.save_in_progress`.

## Context recorded per key

- The window family and surface, plus the source location at the current pin.
  For a shared-group key, record each family and surface that shows it.
- The fit policy from `docs/UI_TEXT_LAYOUT.md`: a one-line label whose
  tooltip carries the full text, a fixed box with a full-text tooltip, or flowed
  text.
- Whether the text states a consequence, a refusal or consent. Such text must
  stay complete and must keep its meaning about spending, assigning, sending
  or saving (for example `ui/OverwriteWarning.lua:6-7` and `ui/Help.lua:10`).
- Each placeholder's meaning and type, and any markup present.

## Placeholders

- **Named and typed.** Use `{count}` (number), `{slot}` (number), `{name}` (user
  text) and `{echo}` (game name), so that a translation can reorder them.
- **Substitution in Nexus code.** Standard Lua 5.1 `string.format` has no
  positional arguments such as `%1$s`, and whether this client accepts them is
  UNKNOWN. Nexus code would therefore substitute named placeholders itself.
- **Literal `%`.** A literal `%` stays literal in a template; the `%%` escape
  belongs only to `string.format` strings.
- **User text** enters only through a `{name}`-type placeholder, after
  `T.SafeName` (`core/UserText.lua:147-159`). It is never translated or
  transliterated.
- **Unknown is not zero.** A count placeholder is never filled with 0 for an
  unknown value. The source already writes "unavailable" instead
  (`core/UserText.lua:245-254`, `core/UserText.lua:340`).
- **Plurals and number formats** wait for verified locales (L10N-04).

## Markup

- **WoW markup in visible text:** colour codes `|cAARRGGBB…|r` and line breaks
  `\n`.
- **Prefer markup in code around the translated text.** The chat prefix
  `|cff7fd5ffNexus:|r` is added by code (`core/Main.lua:24`).
- **Markup inside a text:** a translation keeps every `|c…|r` pair and every
  line break. L10N-06 validates both.

## Not translated

- Everything listed under [Exclusions](INVENTORY.md#exclusions): codes,
  identifiers, patterns, slash command words, protocol tokens, settings values,
  English-name matching, user-authored data, game data and diagnostics.
- Product and component names: Nexus, EchoWeaver (`ui/Help.lua:138`), Project
  Ebonhold, Nexus Support Reports (`companion/NexusSupport/NexusSupport.toc:2`).

## English reference terms

Use these terms consistently in English copy and in translator context. A
translated form of a game term (Echo, Orb, Saved Build, Take, Freeze, Banish,
Reroll) should follow the client's own wording. That wording is UNKNOWN until
a verified client reference exists.

| Term | Meaning in Nexus copy | Source |
|---|---|---|
| Echo | the game's Echo; an Echo family counts once whatever its copies | `core/UserText.lua:236-242` |
| Wishlist | a plan of target Echo copies assigned to a Saved Build | `core/UserText.lua:9-10`, `ui/Help.lua:27` |
| Saved Build | the game's saved build slot, labelled `Saved Build '<name>' (slot N)` | `core/UserText.lua:161-170` |
| My Builds | the game's page that lists your Saved Builds | `core/UserText.lua:331-332` |
| Build Library | the Nexus window of shared builds | `core/UserText.lua:333-335`, `ui/Help.lua:69` |
| All Shared / Mine | the Build Library scopes; Mine is internal scope `mine` | `ui/Help.lua:69`, `core/UserText.lua:333-335` |
| first-run target | the destination when no Saved Build is in use | `core/UserText.lua:206`, `core/UserText.lua:336` |
| locked target | a planned copy for a locked Echo slot | `core/UserText.lua:240`, `ui/Panel.lua:370-374` |
| rolled copies planned / this run | the plan's copies versus copies rolled in this run, different counts | `core/UserText.lua:236-242` |
| Best known | the best shared record this client holds; not a complete or server-wide ranking | `core/UserText.lua:279-282` |
| Auto (Auto ON / Auto OFF) | the Automation master switch; unrelated to any language option | `ui/OverwriteWarning.lua:6-7`, issue #123 |
| Orb, Orb mode | refining rolled Echoes with Orbs (Lost Memories) | `ui/Help.lua:82` |
| Take, Freeze, Banish, Reroll | the game's board actions | `core/UserText.lua:19-27` |
| guaranteed offer | an offer the server marked guaranteed; no future offer is assumed | `core/UserText.lua:39-43` |
| Echo-availability control | the player-facing name for a Tome lever | `core/UserText.lua:44`, `core/UserText.lua:52` |
| Echo Journal, Nexus Progress | the game's journal and Nexus's tab in it | `ui/JournalTab.lua:2-3` |
| Menu and status | the `...` button on the Nexus panel | `core/UserText.lua:328`, `core/UserText.lua:343` |
| unavailable | a value that is not known; never shown as 0 | `core/UserText.lua:340` |
| Sync request | traffic Nexus may send to other players; reading never sends one | `ui/Help.lua:10` |
