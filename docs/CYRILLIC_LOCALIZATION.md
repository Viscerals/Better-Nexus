# Cyrillic UI and Echo display

The Russian UI uses the existing `ruRU` pack and a bundled DejaVu Sans fallback.
The font applies to Nexus widgets. Shared tooltip and menu font faces are restored
when Nexus releases them. English retains the client's original font faces;
individual Cyrillic labels still receive a fallback when needed.

Guided setup includes a Language step after the optional Auto step. English and
Russian are selectable. Español, Deutsch and Français are disabled placeholders
with an unfinished-translation tooltip in each language. Selecting a language
saves the existing Nexus preference; the choice applies on the next reload.
Automatic keeps the existing English default. No new SavedVariables are added.

Echo names and descriptions in the Wishlist editor optionally use the installed
`Ebonhold_Russian` addon's `EbonholdRU_TranslateEchoText` dictionary. This is an
optional dependency: without it, the original server text remains available.
Only presentation changes. Catalog identities, stored names, export codes and
matching by spell ID retain their original values. Search accepts both English
and Russian display names, including Russian uppercase input.

The bridge uses text translation, never the preview/scaling evaluator. Numeric
values and opaque `@...@`, `${...}` and `$spell` fields must survive translation;
otherwise the original line is retained. Unknown dictionary entries also retain
their original text. The external dictionary is not copied into this repository.

The compact HUD reserves one-line space for Nexus, sizes controls in their actual
font, and allows dragging from the grip in either language. Wishlist actions and
the information window use measured text widths or wrapping. These changes do
not authorize gameplay actions or change existing button handlers.

`Fonts/LICENSE_DEJAVU.txt` preserves the font's permission notices. Packaging
includes only the declared font and notice, with fixed size and checksum checks.

Native review should cover both languages, the HUD grip and minimap button,
Guided setup language selection/reload, Wishlist toolbar and footer spacing,
Echo tooltip wrapping and formula preservation, and the information window.
Synthetic or static checks do not establish those native outcomes.
