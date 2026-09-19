# P1.3 — Locked-role selection and P1.2 loading integration

## Inputs and provenance

- Supplied P1.1 runtime ZIP: `dd993ec516d3a14729e847ec03cd8430e551b5d922d2d78b8e1f916f77f6d116`.
- Supplied P1.2 source ZIP: `41b86aeffe8b9bb3f7bc0d56bb7400eedfc055ed5b070b0224f5978144d9f5ca`.
- Supplied P1.2 runtime ZIP: `ed51593955deec9400d95ee61b8c2c032a81f48a263627cc7ee0999e0834f1e3`.
- Supplied P1.1-to-P1.2 patch: `dd5218a0cab40b8983bca649dfa0f5841a06dfe8a4988f30573ef6a84881bd2a`.

All original uploads are preserved. P1.2 source is the implementation baseline;
its runtime archive matches that source except its supported build-label
transformation. The local Git baseline is an import commit of P1.2 archive
contents, not the original worker's unavailable Git commit/history.

## Observed problem and correction

The user's normal EBH1 import contains 85 one-copy entries with no role marker.
Six explicitly marked versions import, assign, and reload successfully according
to the user. Their current loadout differs from that desired build. P1.1/P1.2
could see permanent ownership but refuse opening the desired build until the
entire current and desired identities matched.

The unchanged P1.2 source fails the new real-editor test at the assertion that
an unresolved existing build opens a role-selection interface. This is a
synthetic reproduction using the exact provided target list and a deliberately
different current build, not a claim to have the user's private saved state.

P1.3 provides explicit locked-target selection for this bounded ambiguity.
It does not infer desired roles merely because six permanent Echoes exist.

### Production changes (six existing files)

- `core/Codec.lua`: optional editor-only ambiguous draft decode. Default decode
  stays strict; malformed markers, over-85 input and field validation remain.
- `core/GameAdapter.lua`: bounded, character-local explicit plan roles; exact
  ID/quality/copy-content binding; server/source revalidation before confirmation;
  typed projection independent of equipped-build equality. Known server roles
  are not silently overridden by an old open dialog.
- `core/WishlistController.lua`: preserve explicit roles without merging them
  twice with the ordinary-only sidecar; remember explicit planned roles on
  actual save; export planned targets without padding unrelated owned locks.
- `ui/WishlistEditor.lua`: a ten-row paginated, cancelable role picker; explicit
  confirm; optional owned-lock suggestions; current-source and active-selection
  checks; shared import/edit/assignment entry handling.
- `ui/WishlistRenderer.lua`: unresolved existing choices stay actionable and
  route to confirmation instead of indefinitely waiting.
- `ui/JournalTab.lua`: the real assignment/menu controls use the same role flow.

The normal Save/Create action still uploads only ordinary target copies through
the existing service. Choosing roles does not unlock, lock, activate, or spend
anything. First-run assignment remains a local explicit target association.

### Persistence

The new `wishlistRoleChoices` field is a bounded character-state array with at
most 128 records. Each carries a version, full normalized content signature and
detached typed target entries. Long identities are stored as VALUES, not new
wide SavedVariables keys. IDs, qualities and copy totals all participate; order
and name do not. Content changes require a new confirmation. Reads do not write
or prune the collection; malformed/full state is refused without deletion.

This is desired-plan evidence, not an assertion about currently granted or
permanent ownership. Existing ownership confirmation, automation checks and
Snapshot guarantees are unchanged.

## Coverage

Four new scripts exercise actual installed modules with synthetic host services:

- `role_selection.lua`: the exact 85-entry input; editor pending baseline; no-write
  cancel/suggestion; correct 79+6; real Save/Create callbacks; associated reopen;
  order independence; mismatched same-name record; live contents changing during
  selection; ordinary strict decoder versus editor-only draft; marked imports;
  malformed/86-copy refusals. **42 named checks.**
- `role_boundaries.lua`: no owned locks; manual desired targets; first-run
  assignment; counted copies of one ID split across roles; six-copy cap;
  active-selection drift; exact ID/quality/copy refusal; newly authoritative
  conflicting roles; 80-copy input; unknown saved-state preservation.
  **32 named checks.**
- `role_persistence.lua`: the actual Editing dropdown and Journal selector;
  no-write cancel; actual Save action; unowned planned targets; preserved
  sidecar; literal serialized account state loaded into fresh modules; renamed
  and reordered server mirror; retained association/targets; different-character
  isolation. **26 named checks.**
- `role_export.lua`: actual export-popup provider, six desired locks different
  from owned permanent locks, exact 79+6, no appended owned records; marked
  re-import without another chooser; no resource/write actions.

The first three contain 100 named checks in addition to the fourth script's
assertions. The 20 inherited scripts remain in the run, including 96 P1.1
lock-evidence assertions, 10,000 LoadoutPilot decision comparisons, and eight
P1.2 startup/failure/preservation regressions.

Some test-development failures were fixture setup errors (popup callbacks do not
return Save's result, and two same-slot candidates must be identified by actual
content/name rather than selecting the last one). They are not claimed as
production expected-red evidence. A test requiring the old "synchronized"
refusal context remained unchanged; the new actionable note preserves that
specific reason rather than erasing it.

## Loading improvements retained

These eight P1.2 production files remain byte-identical:

`core/Store.lua`, `core/MainLifecycle.lua`, `core/CommunityController.lua`,
`core/Main.lua`, `core/Sync.lua`, `ui/CommunityBuilds.lua`, `ui/Leaderboard.lua`,
`ui/Panel.lua`.

The LoadoutPilot-derived planner, Policy, transport wrapper, third-party
scheduler, TOC/load order, and other runtime features are unchanged. Therefore
this build includes P1.2's local-before-shared-readiness behavior and once-per-
source initialization without stacking another scheduling implementation.

## Verification limits

The executed interpreter is **Lua 5.4 with test-only compatibility shims**.
No LuaJIT, plain Lua 5.1, original 245-runner project suite, hosted CI, independent
model review, WoW startup timing, player-profile migration, live network or
in-game action was performed in this task. Runtime closure inspection retains
the target's <=60 non-environment-upvalue check; it is not a native compiler run.

The supplied LoadoutPilot archive is used only as a hash-verified offline
reference. It is not required at runtime and its planner source is not added to
the addon. Existing licensing/provenance files remain intact.

The historical architecture deferrals, CTL-compatible fallback qualifications,
unknown `relayPairs` recovery requirements, and previous native issues are not
silently declared fixed. No automatic data-reset/quarantine code is added.

## User retest

Close WoW, back up Nexus and WTF, and replace only the addon folder with P1.3.
Keep automation OFF. Select an old unresolved entry, use suggestions or choose
the intended locked copies manually, confirm, save normally, reopen and reload.
Do not delete existing entries or rearrange permanent slots to match the log.

Record the displayed build and short error if any. A source/offline pass does
not certify this new visual dialog's behavior in the actual client.
