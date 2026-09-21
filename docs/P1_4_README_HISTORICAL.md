# Nexus — integrated experimental prototype P1.4

## Current locks by default, and a visible nonblocking loader

This version is based on the supplied P1.3 source, retaining the P1.2 startup
repairs and the LoadoutPilot-derived rolling policy. It adds the requested
current-lock default and loading UI. It has **not been run inside WoW** here.

### Unresolved Wishlists

When you open/assign an untagged existing plan or import normal EBH1 text,
Nexus now uses your synchronized **current permanent Echoes that exactly match
IDs/qualities/copies in the plan**, if this yields a complete valid split of at
most 79 ordinary and six locked copies. The equipped ordinary build need not
match. The original 85 entries are not reduced or rewritten to different Echoes.

The choice is remembered as a local desired plan with `current-locks` provenance.
It is order-independent, survives save/reopen/reload, and does not grant ownership,
enable rolling, upload on mere opening, lock/unlock, or spend anything. Explicit
roles or previously confirmed plans take precedence; a later change in your
permanent Echoes does not silently rewrite an existing plan.

If the current locks do not match enough copies, or ownership is unavailable,
Nexus does not guess. The fallback chooser is still available: it now owns only
its visible panel, has a solid background and explicit child input layers, and
hides competing editor/dropdown surfaces. Cancel restores the old editor. Its
native visual/click behavior still needs in-game confirmation.

`/nexus currentlocks off` selects the manual-choice workflow for future unresolved
builds. `/nexus currentlocks on` restores the default. These commands do not alter
previous role choices or turn on automation.

### Loading and feature availability

A small draggable, dismissible **Nexus loading** panel appears during startup.
It displays elapsed time, the actual phase, and completed work. A percentage is
shown only for a current phase with a known finite denominator; it is **not an
invented whole-startup percentage or a time estimate**. Commit/validation work
with unknown total uses a phase/step message. The display never pumps data or
grants readiness. Use `/nexus loading` to reopen it, even before local startup
finishes. It hides after actual shared readiness, without progress chat spam.

Local Wishlist tools and the rolling path remain available once local Store and
Echo readiness checks are complete, even while Community preparation is pending.
Automation keeps its existing ownership/board/resource checks and master switch;
this does not make an unsynced character safe to roll automatically.

Builds and Leaderboard navigation is gray while data is pending. Opening one
shows a Loading placeholder rather than querying incomplete data; a button takes
you back to local Wishlists. Switching away cancels the delayed view-opening.
The requested shared view opens only after actual readiness. Shared Sync and DPS
initialization retain their existing prerequisites too: those are not falsely
advertised as ready merely because the local editor works.

Shared-preparation failure stays visible and does not disable already-ready
local tools. Unsafe local-data validation still blocks local actions. No saved
fields are removed and no startup or manual-processing budget is increased.

### Installation and evidence

Close WoW; back up Nexus and WTF; replace only `Interface/AddOns/Nexus` from the
new ZIP. Keep saved data and unresolved builds. Confirm the **test.9005** label,
keep automation OFF initially, and open the existing untagged build. Where its
six targets match your current locks, the normal editor should open directly.

All tests are synthetic/offline under Lua 5.4 with test-only compatibility shims.
The new code does not claim LuaJIT, native Lua 5.1, live WoW, hosted CI, or
independent-review acceptance. The complete packaged Lua inventory is compiled
by that interpreter and reachable closure upvalues are checked separately.

See `docs/P1_4_CURRENT_LOCKS_LOADING_REPORT.md` and the delivered verification
record for exact test counts and package identity. Historical reports below
remain evidence for their original versions, not claims about unrun native tests.

---

# Historical P1.3 behavior and retained feature description

This build combines the supplied **P1.2 startup improvements** with a corrected
Wishlist import/edit/assignment workflow. It is an experimental package: **not a
stable release and not tested in WoW by this build process**.

## P1.3: resolve missing locked roles without owning the desired build

A legacy EBH1/server Wishlist can contain 80–85 total copies without identifying
which copies are intended as permanent locked targets. Previously those builds
could remain “awaiting lock evidence” unless they exactly matched the current
verified loadout. That is inappropriate for a desired build you do not own yet.

Existing unresolved entries now say **“choose locked targets”** and remain
clickable. Clicking one in the editor or Journal opens an explicit selection
screen. The unmodified three-component EBH1 import opens the same screen.

1. Select the intended locked copies with the `+` and `-` controls (use pages
   to reach all entries). For 85 total copies, select six, leaving 79 ordinary.
2. Optional: **Suggest my matching locks** fills matching exact ID/quality/copy
   suggestions from current synchronized ownership. Review them; this button
   does not confirm, save, lock, or spend anything.
3. Choose **Confirm roles & edit** or **Confirm roles & assign**, depending on
   the entry point. Existing-target confirmation saves only a character-local
   role choice; the assignment variant also applies the user's requested local
   association. Actual Wishlist upload still uses the ordinary Save/Create action.
4. Save normally, reopen the assigned entry, then test `/reload` with automation
   OFF. The selected roles are restored from the saved content-matched choice.

You can choose desired locks you do not currently own. The current active build
need not equal the Wishlist. Display order, server entry order, and rename do
not determine roles. No input entries are silently removed.

**Cancel** makes no role-choice or server write and preserves the old editor
draft. Malformed input, an over-limit split, or a server/active selection changed
while the dialog is open remains a explained refusal—not guessed authority.
If input changes, cancel and reopen the new version.

Already explicitly tagged imports and verified exact-active evidence retain
their existing fast path; no selection is required merely because P1.3 is installed.
The ordinary network/default decoder remains strict. Only the editor can load
a bounded ambiguous draft, which is not usable as an actionable target until
roles are confirmed.

A complete user-chosen design also exports only its intended locked targets,
not extra unrelated currently owned locks. Local role confirmation does not
create owned Echoes, spend resources, unlock anything, or force auto state.

The saved field `wishlistRoleChoices` is character-local and bounded to 128
content records. It compares complete normalized ID/quality/copy contents, not
just slot/name or an ambiguous hash. Invalid/full storage causes an explicit
refusal; existing records and unknown fields are not evicted or deleted.
Normal-client backups remain important before testing new persistent state.

## P1.2 loading improvements retained, not reimplemented

All eight startup/runtime files changed by supplied P1.2 are byte-identical in
this P1.3 build. Evidence initialization remains once per startup source. Safe
local controls are released after actual local Store/catalog readiness, without
waiting for all Community background preparation. Shared views remain guarded
and display preparation while required services finish.

The existing 2 ms soft startup allowance, finite slice bound, failure handling,
and data-preserving validation remain. Large data still takes work; this is not
an instant-start guarantee or a new native timing result. P1.2's own report and
measurements remain in `docs/STARTUP_FIX_REPORT.md` as historical evidence.

## Validation scope

The P1.3 source and extracted runtime package are checked with 24
prototype-specific scripts, including all 20 P1.2 scripts, the 96-assertion P1.1
lock-evidence regression and 10,000-case LoadoutPilot comparison. Four new role
suites cover the supplied 85-entry import, actual editor/Journal controls,
cancel/confirm, unowned targets, copies, live-source drift, export, and literal
save/reload into fresh modules.

Executed runtime: Lua 5.4 with test-only compatibility shims. These tests are not
a LuaJIT, Lua 5.1, full upstream 245-test, independent-review, or native WoW PASS.
See `docs/LOCK_ROLE_FIX_REPORT.md` and the accompanying result JSON.

## What is included

- Ordinary Wishlist recommendation/rolling uses an independent implementation
  of the supplied **LoadoutPilot 1.3.6 / patch 103** policy. No separate
  LoadoutPilot installation is required. Take, conditional Freeze, Banish,
  optional Reroll, exact desired copies and qualities are connected to Nexus's
  existing confirmed-action machinery. Verified Snapshot play retains Nexus's
  separate Snapshot/guarantee policy; planned Wishlist play does not use an
  invented Snapshot future queue.
- Existing Wishlist editor/import/export, first-run/numbered-slot assignment,
  79 ordinary + six designed-lock targets, opt-in Auto-Lock, save/ratchet,
  Community library/publication, Details!-based DPS boards, Journal/HUD,
  startup/persistence, and Sync remain present.
- Pending Wishlist retries now cancel if the confirmed draft changes; targets
  and associations use the accepted upload identity. First-run edits work
  without pretending that a nonexistent numbered loadout exists. Distinct exact
  spell/quality IDs are no longer collapsed by the upload adapter.
- A legitimate confirmed-empty owned-Echo response invalidates the actual
  automation projection cache. No timer or forced `synced=true` bypass is used.
- Build/tombstone hash material preserves numeric versus string ID type.
- CTL-compatible byte scheduling and negotiated addon-message whispers are
  integrated. Legacy channel discovery, broadcasts and unknown peers remain
  supported. No normal dual-send. See the transport qualifications below.
- Orb pending/unknown state prevents ordinary automation and the four ordinary
  choice writes. Automatic Orb spending/Memory mode is **not** included.
- Large diagnostic histories are copied cooperatively; the copy window renders
  pages of at most 16,000 original bytes, retaining the full output in memory.
  Copy all pages in order **without inserting separators** to obtain the complete
  reversible inert report. Page boundaries preserve UTF-8 characters.
- Journal action discovery no longer treats a nearby unidentified button as an
  Edit/More action. Existing idempotent HUD hooks and Legendary labels remain.

## Install for an opt-in test

1. Close WoW. Back up the existing `Interface/AddOns/Nexus` folder and the entire
   `WTF` folder to a location outside the client. Keep a matching code/data pair.
2. Disable other Echo automation addons, including the separate LoadoutPilot
   addon and EchoOptimizer. Do not run competing pickers together.
3. Replace the old Nexus addon folder with the `Nexus` folder from this ZIP. The
   file must be `Interface/AddOns/Nexus/Nexus.toc`, not a nested Nexus/Nexus path.
4. On login, check `/nexus status` for the new test.9004 build label. Start with
   automation OFF, inspect the Wishlist and intended locks, and test save/reopen.
5. Enable resource-consuming automation only when you intentionally want it.
   The normal global auto switch begins OFF. A source-level or synthetic pass
   is not proof of real server behavior.

Useful new commands:

```
/nexus prototype
/nexus reroll on
/nexus reroll off
/nexus freeze on
/nexus freeze off
```

These per-action preferences do not enable the master auto switch. Other Nexus
commands and controls are retained. Existing Reroll behavior remains enabled by
its preference unless explicitly disabled; the separate LoadoutPilot default is
not imported over Nexus settings.

## Network and performance qualifications

Nexus uses the live `wrbuildssync` discovery channel. A separate local folder is
not network isolation. Use ordinary gameplay with consenting testers, not flood,
malformed-packet or synthetic traffic experiments against other players.

A bounded prefix handshake enables `NEXUS_P1` addon whispers for directed packets
that fit the addon envelope. Unknown peers/discovery/broadcasts use the legacy
channel. Oversized addon-envelope packets use one legacy route, not both.
Existing semantic validation and correlation remain in Nexus's inbound owners.

An already-installed compatible global ChatThrottleLib is reused without
replacement. Otherwise a **private, compact v21-derived compatibility scheduler**
is used. This is not a byte-identical official CTL release and does not claim
complete issue-66/native transport acceptance. Nexus retains packets in its own
bounded queue until an immediate CTL send slot is available, avoiding an
uncancellable second Nexus queue inside CTL. If another addon keeps CTL busy,
Nexus can wait and its normal expiry still applies. Native coexistence,
throughput, peer convergence, combat transitions, and long-session fairness
remain unverified.

The original PR #68 receiver cannot reconstruct complete locked-bearing builds;
updated peers are needed for that path. Startup/maintenance latency and copy-box
responsiveness need native measurement. No fixed startup-time promise is made.
Some maximum-data/work-bound and authority-hardening findings from the base
remain deferred. This prototype does not claim full architecture acceptance.

## Stop and rollback

Stop for unexpected actions, missing data, repeated Lua errors, uncontrolled
traffic, or severe repeatable stalls. Close the game before restoring the old
Nexus folder **and its matching pre-test WTF**. A local backup cannot undo spent
resources or already-published server-side actions. Do not clear unknown fields
as a workaround. The one-character relayPairs quarantine from earlier testing
is not included as an automatic migration.

Report the exact build, action, expected/actual outcome, and a short error or
screenshot. Do not post credentials or full player backups. The historical
player reports are not declared fixed without matched reporter confirmation.

## Development and evidence

The source archive includes the complete P1.3 runtime, regression tests and reports.
The P1.2-to-P1.3 patch applies to the supplied P1.2 source archive, not the
original test.28 tree. The local P1.3 Git baseline is an import of those archive
bytes; it is not a claim that the original worker Git history was available.
The P1 feature baseline remains published `eb190c5`. This environment used
Lua 5.4 with test-only compatibility shims. It did **not** execute LuaJIT,
plain Lua 5.1, the original 245-runner suite, GitHub CI or WoW for this prototype.

From the source root, run `python tools/run_prototype_tests.py`. It prefers an
installed LuaJIT, otherwise uses the explicitly labelled liblua5.4 fallback.
Supply `--reference /path/to/LoadoutPilot` for the 10,000-case reference comparison.
`tools/prepare_pilot_reference.py` can extract its two reference files from the
exact user-supplied archive; that archive is not a runtime dependency.

Keep LICENSE.md, UPSTREAM.md, AI_POLICY.md and third-party provenance with this
project. Existing licensing boundaries are not changed by this prototype.
