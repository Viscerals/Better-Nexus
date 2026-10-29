# Nexus all41 acceptance matrix (issue #131)

Source/offline reconciliation of the canonical 41 rows (`UX-01`–`UX-18`, `LP-01`–`LP-18`, `J1`–`J5`) against the final source pin `8393f5f4b61a0d62b5043b861539be868ebf80f6` (tree `8c1397ba8856d6d6973d5dd28e7fa0aecebb4ada`). **This is not tester, native, release or whole-feature acceptance. No row is accepted.** Native criteria are pending under [#133](https://github.com/Viscerals/Better-Nexus/issues/133).

The machine-readable companion is [`ALL41_ACCEPTANCE.json`](ALL41_ACCEPTANCE.json); each of its rows keeps the canonical object unchanged (input SHA-256 `ceb0e37ce467ebe5fe494c04db49aafc7d5b0dcf71d4ffd52e0b6e668f3a9e44`, schema `nexus-m7-current-sanitized-public41-requirements/1`). For this revision all 41 objects and their order were compared with that input again: 18 UX, 18 LP and 5 J rows, byte-equal. J5 remains an optional journey with its safety boundaries.
Claude Opus 5.5 wrote the matrix; the existing Nexus coordinator is accountable for it. Dispositions are the author's own, carried from the reviewed `c7d2b74` revision, except UX-10, which follows the recorded coordinator decision. Independent Spec and Standards review of this rebinding is pending with Codex.

**Final pin.** Source symbols, line citations and assertions are rebound from `c7d2b74` to `8393f5f` (24 commits, 54 changed paths). Thirteen cited files changed. Their citations were remapped from git line maps: 1,997 cited lines are byte-identical at their new positions. Five cited ranges touched changed lines and were re-read at `8393f5f`. The root coordinator's complete CI at this pin is terminal and PASSED: Lua 599 of 599 listed fixtures passed, 0 failed, 0 not run; both registered Python test files passed (84 cases); exit 0. Every fixture cited by a row passed (64 of 64, exit 0). Source custody: the raw source inventory was captured after the run; committed-source custody and 99 runtime hashes matching the working files support sourceUnchanged, but no measured raw pre/post comparison exists.

**Revision.** This revision supersedes `be8af43cd392b117437f9bd799b623819fb2e134` (tree `854daa4667f2b499d5b44e4c68f1c8b91a8acc40`), which bound the same `8393f5f` pin and carried UX-10 pending a coordinator decision. Changes in this revision:

- UX-10: met-offline -> met-offline-adopted-interpretation by the recorded coordinator decision (the approved short Auto hover with an accessible full-details view). The canonical object is unchanged.
- UX-10 adds crimson_panel_auto_help A1/A6/A8 anchors and binds that fixture to the 8393f5f results (PASS, exit 0, 61 checks) beside ux_automation_scope (PASS, exit 0, 97 checks).
- Current totals are 25 met-offline / 8 met-offline-adopted-interpretation / 8 partial; 26/7/8 is kept as historical. No other disposition, native status or citation changed. The final-pin CI binding is unchanged; no rerun.

The `be8af43` revision superseded `f770bc4244a8fed4ae70fbaeba50eeb3c955bcbb`, which is integrated byte-identically in `8393f5f` and described `c7d2b74`. The earlier `8ae217f` text described `f399dd0`, and `2aaaecca` described `9bfb2bb`. Changes made by `be8af43`:

- Final pin is now 8393f5f (tree 8c1397b). c7d2b74 -> 8393f5f merges the Orb terminal dismissal (#167), panel usability (#165 #168 #169 #170 #171 UI), whole-addon session pause (#171), Continue cadence (#172) and the native-menu/FAQ repair (87de3ff, 8393f5f).
- Every cited source and fixture path was checked against the 8393f5f blob: 13 cited files changed, plus 2 executed-only fixtures (help, help_action_first). Shifted citations are remapped from git line maps; bare ':N' citations were resolved to their file and checked against the c7d2b74 line content.
- Five cited ranges touched changed lines and were re-read: UX-02 Panel heading (new session-pause branch), UX-10 Auto hover (replaced), J4 accept callback (session-pause refusal), LP-06 K6 and UX-17 H1 (Reference page count 7 -> 8).
- Per-row execution (status, exit, checks) is re-read from the passing 8393f5f complete CI; c7d2b74 execution is kept per row as priorPinExecution. help_action_first checks changed 6052 -> 6493 (FAQ page); every other cited fixture's check count is unchanged.
- UX-10: a new source observation is recorded for a coordinator decision; its disposition is carried, not re-confirmed. Dispositions and counts are otherwise unchanged; no row is promoted.

Nothing was rerun for this revision, and no product, test or canonical requirement changed. The complete CI above ran on `8393f5f`; it is not a run of this later documentation commit.

## Evidence used

- **Source lineage:** `c7d2b74` → `8393f5f` merges the Orb terminal dismissal (`ebc990c`, #167), panel usability (`397f6c7`, #165 #168 #169 #170 #171 UI), the session-pause core (`3020df6`, #171), the Continue cadence (`3457617`, #172) and the native-menu/FAQ repair (`87de3ff`, `8393f5f`). Merge subjects record those lanes as accepted; their review receipts were not re-read here. Both matrix documents at `8393f5f` equal `f770bc4`.
- **Re-read changed regions:** UX-02 `ui/Panel.lua:4950-4991` → `ui/Panel.lua:5268-5312` (new first session-pause heading branch; cited branches byte-identical); UX-10 `ui/Panel.lua:2370-2389` → `ui/Panel.lua:2638, :5960-6061, :3168-3172; ui/Help.lua:307-316` (Auto hover replaced by a short summary; per-permission list moved to Options > Auto explained); J4 `core/AutomationRuntime.lua:4684-4716` → `core/AutomationRuntime.lua:4715-4748` (accept callback also refuses during the session pause); LP-06 `tests/prototype/ux_setup_checklist.lua:222-335` → `same lines` (Reference page count expectation 7 -> 8); UX-17 `tests/prototype/ux_help_navigation.lua:96-99` → `same lines` (Reference page count expectations 7 -> 8). Ranges with inserted lines: UX-01/J4 core/AutomationRuntime.lua:4653-4669 -> 4679-4700 (session-pause refusal); J5 core/OrbRuntime.lua:3356-3392 -> 3383-3420 (session-pause refusal in M.Resume).
- **Complete CI at `8393f5f`:** The root coordinator's complete CI at this pin is terminal and PASSED: Lua 599 of 599 listed fixtures passed, 0 failed, 0 not run; both registered Python test files passed (84 cases); exit 0. Every fixture cited by a row passed (64 of 64, exit 0). Source custody: the raw source inventory was captured after the run; committed-source custody and 99 runtime hashes matching the working files support sourceUnchanged, but no measured raw pre/post comparison exists. Receipts: `RECEIPT.json` SHA-256 `862607b14c0d36dd8254c4b960370a815a492d98454a32c2f3172c00b1f64d43`, `results.json` SHA-256 `be61f5092076369c36c1a08641f8de1a9753912259d88a843ce52ab5a6e34040` (maintainer-held, not committed). Each row binds its own cited fixtures' status, exit and check count from `results.json`; UX-10 also binds `crimson_panel_auto_help` (PASS, exit 0, 61 checks), which exists only from this lane onward. Aggregate totals, registration, header IDs or a grep hit do not establish a row's behavior.
- **Previous pin (historical):** the complete CI at `c7d2b74` passed Lua 580/580 and 84 Python cases; each row keeps that execution as *prior pin execution*. The failed `f399dd0` complete CI (Lua 579/580; uncited `lifecycle_counter_accounting`, repaired by `63ff470`) stays failed and historical.
- **Lane runs (not the final pin):** UX-13 focused 10/10 at `62f16c7`; UX-02/J4 focused 23/23 at `82b7695`; discriminating RED of the new R10 against predecessor `0d16ba7` (one expectation failure, no guard or setup failure). Command form: `python -B tools/ci_check.py --output <local file> --only <selected>`; the JSON lists each selection.
- **Independent reviews of the code:** the `8393f5f` Spec review (passed, 0 material findings) and Standards refresh (passed, 0 material findings) cover the final source and fixtures of the native-menu/FAQ delta (`b1ef408...8393f5f`). They do not accept this documentation, and they are not execution or native acceptance. The earlier final2 (`c7d2b74`), final combined (`f399dd0`) and lane reviews remain as recorded in the JSON.
- **Current intake (bounded):** the older #131/#148 queue reconciliation at `87de3ff` records ordinary Help → coach and *Assigned now* versus guide-local choice as source-implemented, with native incomplete. The 163012 native sample of a private `b1ef408` build (1760×990, 100% main HUD) fitted the manual Welcome/Step 5 replay and opened Options → Questions (FAQ) on page 8/8 with Auto OFF. First login and full setup were not run, and an Options menu repeat-close failure was recorded. This is historical evidence for that sample only, not first-login, full-flow or `8393f5f` acceptance.
- **Tracker scope:** the latest current-scope comment, [#131 comment 6502167124](https://github.com/Viscerals/Better-Nexus/issues/131#issuecomment-6502167124), records owner approval of a shorter first Auto explanation with an accessible complete view, plus passive Help/FAQ. It retains the native scenarios listed below. The stale issue opening does not reinstate cleared transfer/provider blockers.
- **Historical material:** the issue's top status paragraphs, the earlier e8 matrix (0 whole items accepted), older projected maps, the `9bfb2bb`, `f399dd0` and `c7d2b74` matrix revisions and their runs are historical only. Crimson's separate N/H 41 feedback topics are a different inventory and are not used here.

## Recorded interpretation conflicts

**UX-01.** The canonical proposal says *"Fresh profile: No -> Welcome shown, Auto OFF, no overwriteWarnings write"*. Current consent behaviour differs, and it is kept:

- The first-launch warning's answers are *Continue — Auto stays OFF* and *Close*.
- An explicit Close, No, X or Escape declines. It then opens the Welcome frame as **information-only setup** (`ui/OverwriteWarning.lua:143-146` → `QuickStart.ShowSetup`).
- `ui/QuickStart.lua:728` returns on `declined`. It shows no first-time Welcome or coach and writes no acknowledgement.

**UX-13.** The canonical proposal says *"No 79/79 next to saved/assigned without planned"*. The assigned Saved Build counts are Wishlist copies found in that Saved Build, not planned copies, so they are qualified with the existing unit *Wishlist copies in this Saved Build* (`core/UserText.lua:667`) instead of the literal word. No mathematics changed.

**UX-02 / J4 (adopted reading).** *"Exactly one marked and named"* is met for the adaptive Freeze by a separate Freeze mark (`[Freeze]` row, `> Freeze` tag) and a named recommendation. The Take marker (`>>`, `> Wishlist pick`) keeps meaning Take. The same Echo offered twice still marks nothing.

**UX-10 (approved short-hover reading).** The canonical proposal says *"Tooltip lists each enabled action with on/off"*. Under the coordinator decision (the user's existing approval of the assessed usability suggestions, #169), the short Auto hover gives the current state, the next action, the essential charges/Saved Build consequence and an explicit route, *Full details: Options > Auto explained.* The separate Auto explained view (the Help Auto page), the Auto warning and Help disclose each current permission on/off and the tome behavior. That view is not itself a tooltip.

These adopted readings are recorded rather than changed to make a row pass. Changing either side needs an owner decision.

## Open gaps and interpretations (not fixed here)

- **LP-04:** SCOPE GAP: setup checklist/coach do not render the shared strip (ui/QuickStart.lua checklist rows; ui/GuidedSetup.lua:151). Owner decision whether shared facts suffice or the strip itself is required.
- **UX-07:** INTERPRETATION: the Play-panel Orb line (ui/OrbPanel.lua:1664-1684 UI.PanelRunLine) shows state, usage, wait and reason, but not the changed target. It offers no Resume (Open only). Owner decision whether 'all surfaces' includes it.
- **UX-07:** TEST GAP: no fixture clicks a still-enabled Resume after the assignment changed without a redraw (orb_target_review.lua:243-249 calls UI.Refresh first). Current code is correct (ui/OrbPanel.lua:602 re-reads, :612 compares).
- **LP-13:** No test that the shared formatter is used by every count surface.
- **LP-14:** SCOPE GAP G-LP14: Build Library 'BEST RECORDS FOR THIS LOADOUT' lines (core/CommunityProjection.lua:114-125; ui/CommunityRenderer.lua:2784-2793) show DPS/holder/your best only - no qualifier, duration, level or date where a row carries them; combined rows (ui/Leaderboard.lua:1004-1007) likewise. Untested.
- **UX-15:** COVERAGE GAP: evidence covers only the labels checked by ux_record_scope_terms, terminology and terminology_consumers. One-meaning coverage across the whole UI and Help is absent (same scope as LP-15 G-LP15).
- **LP-15:** COVERAGE GAP G-LP15: lint scope bounded; e.g. core/CommunityController.lua is outside it (tests/prototype/ux_record_scope_terms.lua:202-207 UI_FILES). The UX-13 description string (core/CommunityController.lua:1379) is guarded by fixture assertions, not by the lint.
- **UX-16:** INTERPRETATION: 'Same usage words on all three surfaces' - owner decision whether shared vocabulary with differing separators suffices.
- **J3:** UNRESOLVED EDGE G-J3 (source-only): Saved Build slot contents replaced in the game between chooser click and a delayed Auto-ON accept. AssignWithConsent re-checks owner only (ui/JournalTab.lua:154-176); A.SetLoadoutWishlist checks the slot is populated (core/GameAdapter.lua:3247), not that it is the same Saved Build; the chat line names the captured loadoutName. Associations are keyed by slot index by design, so this may be intended; no test replaces a populated Saved Build before a delayed accept. Owner decision whether 'recycled slot' includes Saved Build slots.

Each is source-verified only. None was executed as a failing test. They are scoped to the cited paths, and this documentation-only change leaves production code and tests untouched. The UX-10 source observation is resolved by the coordinator decision below; it was not a gap.

## Resolved coordinator decision

- **UX-10:** the observation recorded in `be8af43` (the 8393f5f Auto hover no longer lists each permission; the list is on Options → *Auto explained (full details)*) is resolved by the coordinator UX-10 decision (record SHA-256 `92fd208d03766da6bc175bcdeb5f98235db78176398df08f5be7fccceb7a13a6`): current disposition `met-offline-adopted-interpretation` under the approved short-hover reading above. The canonical object, every other disposition, runtime behavior and native status are unchanged.

## Resolved in the final source

- **UX-02 G-UX02-a** (unmapped experimental Freeze label; no card identified): resolved by `0d16ba7` → `82b7695` (count-neutral *Freeze one of the needed offers*).
- **UX-02 G-UX02-b** (Auto OFF heading read *Active: Slot N* under Orb guidance): resolved by `0d16ba7`, unchanged through `82b7695`.
- **J4:** both inherited UX-02 gaps, as above.
- **UX-13 G-UX13** (bare N/M in the generated assigned-Saved-Build description): resolved by `62f16c7`.

All are integrated unchanged in `f399dd0`, `c7d2b74` and `8393f5f`. Their cited fixtures passed in the complete passing runs at `c7d2b74` and at `8393f5f`. Their native observation is pending.

## Summary

| Row | Title | Spec | Standards | Row disposition |
|---|---|---|---|---|
| UX-01 | Answering No at first launch removes the Welcome; Welcome cannot be reopened | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported-with-recorded-conflict; native pending |
| LP-01 | State-derived per-character/loadout setup checklist | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-02 | Auto OFF recommendation does not identify the card | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported under the adopted reading of 'marked'; cited fixtures pass in the complete passing run at 8393f5f; native pending |
| LP-02 | Compact charges row | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-03 | Save/assign outcome chat-only; generic saved follows not-assigned | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported; native pending |
| LP-03 | Explicit Save changes / Save & assign controller intents | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-04 | Destination not named in confirmations or the main panel; first-run plan shows None | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-04 | Shared character/Saved Build/Wishlist/state strip | partial | no-hard-violation-found | offline-partial (scope); native pending |
| UX-05 | Picker assigns on one click, silent success, Auto-ON consequence tooltip-only | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-05 | Destination strip and setup checklist integration | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-06 | Assign Wishlist lands on the game page, not the chooser | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-06 | Checklist direct assignment links | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-07 | Orb Resume after target change adopts a new target from unnamed compact controls | partial | no-hard-violation-found | offline-partial (Play-line interpretation open; test gap recorded); native pending |
| LP-07 | Full-window re-review after changed Orb target | met-offline | no-hard-violation-found | offline-supported; test gap recorded; native pending |
| UX-08 | Pause/Resume share a button in full window and main-panel strip | met-offline | no-hard-violation-found | offline-supported; native double-click pending |
| LP-08 | Separate fixed Pause and Resume controls | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-09 | Why Auto is not acting is hidden behind ... | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-09 | Unified Auto/Sync/Orb status and inline reason area | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported; native pending |
| UX-10 | What Auto will do is not listed (actions, automatic save, tome changes) | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported under the approved short-hover interpretation (Auto explained view, warning and Help disclose each permission and tomes); native pending |
| LP-10 | Existing-permission Automation scope/settings panel | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-11 | Copy into Editor and Share Build share one button; publish unconfirmed | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-11 | Dedicated Share action area | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported; native pending |
| UX-12 | Automatic sends not disclosed; Sync status jargon | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-12 | Optional in-game Sync mode choice; defaults unchanged | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-13 | 79/79 and complete mean four different things | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported under a retained interpretation; cited fixtures pass in the complete passing run at 8393f5f; native pending |
| LP-13 | Shared qualified count formatter | partial | no-hard-violation-found | offline-partial (reach); no native-only criterion beyond UX-13 |
| UX-14 | DPS and Leaderboard labels overstate scope | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-14 | Record detail with available date/duration/level | partial | no-hard-violation-found | offline-partial (scope gap for a separate lane); native pending |
| UX-15 | Label collisions | partial | no-hard-violation-found | offline-partial (checked labels only; coverage gap shared with LP-15) |
| LP-15 | Terminology lint | partial | no-hard-violation-found | offline-partial (coverage) |
| UX-16 | Orb wording: usage x3, dense blocks, reload advice conflict, history lost on reload | partial | no-hard-violation-found | offline-partial (interpretation); native pending |
| LP-16 | Unified Orb status vocabulary | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-17 | Help and Welcome structure | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-17 | Restructured Help and contextual deep links | met-offline | no-hard-violation-found | offline-supported; native pending |
| UX-18 | Practical accessibility minimums | met-offline | no-hard-violation-found | offline-supported; native pending |
| LP-18 | Accessibility pass per window family | met-offline | no-hard-violation-found | offline-supported; native gaps enumerated; native pending |
| J1 | Fresh import/no Saved Build | met-offline | no-hard-violation-found | offline-supported; native pending |
| J2 | Existing Saved Build/unassigned plan | met-offline | no-hard-violation-found | offline-supported; native pending |
| J3 | Multiple characters/Saved Builds | partial | no-hard-violation-found | offline-partial (unresolved edge); native pending |
| J4 | Manual recommendations then optional Automation | met-offline-adopted-interpretation | no-hard-violation-found | offline-supported under the UX-02 adopted reading; cited fixtures pass in the complete passing run at 8393f5f; native pending |
| J5 | Optional Orb pause/target change/recovery | met-offline | no-hard-violation-found | offline-supported (optional journey, safety boundaries retained); native pending |

Counts:
- **Rows:** 41 (18 UX, 18 LP, 5 J).
- **Spec (current):** met-offline 25, met-offline-adopted-interpretation 8, partial 8.
- **Spec (historical, `f770bc4` and `be8af43`):** met-offline 26, met-offline-adopted-interpretation 7, partial 8; UX-10 was met-offline there.
- **Rows with pending native criteria:** 38 (3 rows have no native criterion beyond offline scope).
- **Accepted whole rows:** 0.
- **Final-pin execution:** complete suite PASSED at 8393f5f (Lua 599/599, 0 not run; Python 2/2 files, 84 cases; exit 0); all 64 cited fixtures PASS, exit 0.
- **Prior pin execution:** complete suite PASSED at c7d2b74 (Lua 580/580, 0 not run; Python 2/2 files, 84 cases); historical.

## Rows

### UX-01 — Answering No at first launch removes the Welcome; Welcome cannot be reopened

Canonical (verbatim):

```json
{"id": "UX-01", "kind": "originalUXfindingDesiredOutcome", "title": "Answering No at first launch removes the Welcome; Welcome cannot be reopened", "requiredM7Disposition": "Finish state-derived checklist/replay composition; no consent from No/Close.", "acceptanceProposals": ["Fresh profile: No -> Welcome shown, Auto OFF, no overwriteWarnings write", "Welcome reopenable same and later session", "Auto click after No still shows Auto warning"]}
```

- **Adopted/current interpretation:** Canonical wording 'No -> Welcome shown' is preserved. Current consent behaviour is kept: the first-launch warning's answers are 'Continue — Auto stays OFF' and 'Close'; an explicit Close/No, X or Escape declines and opens the Welcome frame as information-only setup ('Nexus setup (information only)'); QuickStart.ShowIfFirstTime returns on 'declined' without the first-time Welcome, guided coach or hasSeenQuickStart write. The canonical object is not edited to obtain green.
- **Conflict:** INTERPRETATION CONFLICT (kept explicit): canonical 'No -> Welcome shown' vs current ui/QuickStart.lua:728 `if outcome == "declined" then return true end`. What is shown after a decline is the information-only Welcome (ui/OverwriteWarning.lua:143-146 -> QuickStart.ShowSetup, ui/QuickStart.lua:461-479), not the first-time Welcome or the coach. Recorded as adopted behaviour; owner decision required to change either side.
- **Production symbols:** `ui/OverwriteWarning.lua:120 Finish(yes, closing, explicit)`; `ui/OverwriteWarning.lua:110 ShowInformation`; `ui/OverwriteWarning.lua:318 M.EnsureOnboarding`; `ui/OverwriteWarning.lua:327 M.RequestAuto`; `ui/OverwriteWarning.lua:245 ONBOARDING_YES`; `ui/QuickStart.lua:461 M.ShowSetup`; `ui/QuickStart.lua:724 M.ShowIfFirstTime`; `ui/QuickStart.lua:447 M.Show (consent-bound)`
- **Callback chain:** warning No/Close/Escape (ui/OverwriteWarning.lua:210,213,228) -> Finish(false,...,explicit=true) -> onboardingOutcome='declined' (:132) -> same root/owner check (:143-145) -> ShowInformation (:110) -> QuickStart.ShowSetup (ui/QuickStart.lua:461): _informational=true, SETUP_TITLE/SETUP_HINT, no write ‖ later Auto click -> AutomationRuntime ToggleAuto (core/AutomationRuntime.lua:4679-4700) -> OverwriteWarning.RequestAuto (:327): onboarding is 'declined' not 'pending' -> Show('auto') unless the player saved its suppression
- **Discriminating assertions:**
  - tests/prototype/ux_setup_replay.lua:204-205 S1 No declines; `NexusDB.overwriteWarnings==nil and Seen()==nil` (real warning handlers)
  - tests/prototype/ux_setup_replay.lua:210 S1 No opens the Welcome at once as information only
  - tests/prototype/ux_setup_replay.lua:213 the consent-bound QuickStart.Show() still returns false
  - tests/prototype/ux_setup_replay.lua:231-239 replay reopenable in the same session; :405 and :418 a seen/later-session boot can replay
  - tests/prototype/ux_setup_replay.lua:261-264 after No, Auto still asks its own warning; declining keeps Auto OFF
  - tests/prototype/ux_setup_replay.lua:299 S2 Close and S7 Escape (scenario at :483) open the informational Welcome
- **Negative controls:** early No before reading delay answers nothing (:197); raw OnHide declines only, opens nothing (S8); stale answer after root/owner change opens nothing (S9/S10); Auto warning No/Close/Escape/CancelAuto open no Welcome (:275)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_setup_replay` PASS (229), `overwrite_warning` PASS, `overwrite_warning_welcome` PASS (26), `overwrite_warning_lifecycle` PASS (76), `overwrite_auto_gate` PASS, `quickstart_seen_guard` PASS (76), `guided_first_entry` PASS (195)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_setup_replay` PASS (229), `overwrite_warning` PASS, `overwrite_warning_welcome` PASS (26), `overwrite_warning_lifecycle` PASS (76), `overwrite_auto_gate` PASS, `quickstart_seen_guard` PASS (76), `guided_first_entry` PASS (195)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_setup_replay` PASS (229), `overwrite_warning` PASS, `overwrite_warning_welcome` PASS, `overwrite_warning_lifecycle` PASS (76), `overwrite_auto_gate` PASS, `quickstart_seen_guard` PASS (76), `guided_first_entry` PASS (195)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - The cited Auto request path (core/AutomationRuntime.lua:4679-4700) gained one refusal before RequestAuto: while the session pause (#171) holds, an Auto click keeps Auto OFF ('Auto stays OFF while Nexus is paused. Resume Nexus first.'). Additive; the decline/consent chain and its assertions are unchanged.
  - ux_setup_replay S2 now expects the Reference to open on 'Page 1 / 8' (FAQ page appended by #169); the cited UX-01 assertions are unchanged lines.
- **Spec:** `met-offline-adopted-interpretation`. All three canonical acceptance proposals have discriminating passing assertions under the adopted reading; 'Welcome shown' is satisfied by the information-only Welcome, not the first-time Welcome. Conflict recorded above.
- **Standards:** `no-hard-violation-found`. Consent is not inferred from No/Close; no SavedVariables write on decline. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Interpretation conflict above (owner decision).
  - Native Escape capture/UISpecialFrames order NOT_RUN (fixture header).
- **Native (#133, pending):** Fresh profile in the client: Close/Escape on the first-launch warning shows the information-only Welcome, Auto stays OFF, no overwriteWarnings key written; Options > Setup information (read only) reopens it in the same and a later session; Auto click after Close still shows the Auto warning
- **Row disposition:** offline-supported-with-recorded-conflict; native pending

### LP-01 — State-derived per-character/loadout setup checklist

Canonical (verbatim):

```json
{"id": "LP-01", "kind": "largerProposal", "title": "State-derived per-character/loadout setup checklist", "requiredM7Disposition": "Finish state-derived checklist/replay composition; no consent from No/Close."}
```

- **Adopted/current interpretation:** Delivered as two surfaces: the read-only 'Setup checklist and status' window (ui/QuickStart.lua:489-686, rows from Panel.SetupFacts via UserText.SetupChecklist) and the guided setup coach (core/GuidedSetup.lua, ui/GuidedSetup.lua) whose steps complete only from bound receipts plus fresh read back; the place is kept per character (PLACE_KEY guidedSetupPlaceV1) but no result is kept across reload.
- **Production symbols:** `ui/QuickStart.lua:542 RefreshChecklist`; `ui/Panel.lua:1081 M.SetupFacts`; `core/UserText.lua SetupChecklist / StatusLines`; `core/GuidedSetup.lua:74 ReadPlace, :125 Save, :255 G.Resume, :321 G.Recheck, :800 G.Summary`; `ui/QuickStart.lua:712 ShowFirstUseCoach, :706 CoachClosed`
- **Callback chain:** checklist OnShow/OnUpdate 0.5 s (ui/QuickStart.lua:659-665) -> Panel.SetupFacts -> UserText.SetupChecklist -> row text; no writer ‖ coach Show -> G.Resume (core/GuidedSetup.lua:255) -> ReadPlace/Apply/Readopt; outcomes re-read via G.AssignStatus/TargetFacts ‖ replay G.Replay (:182) clears choices/results, never Wishlist, Saved Build or Auto
- **Discriminating assertions:**
  - tests/prototype/ux_setup_checklist.lua K1-K5 (:115-221): done only when true now; unknown/loading/restoring/unavailable apart; Welcome and Auto warning are not facts (K4 :168)
  - tests/prototype/guided_setup_resume.lua (138 checks): place kept per character; outcomes read again; read-only/foreign/loading session-only
  - tests/prototype/guided_setup_flow.lua F1 (:154) navigation moves the guide only; F4 (:286) honest summary
- **Negative controls:** skipped is never done (core/GuidedSetup.lua:757-762, Summary :815-816); owner/epoch/session change clears evidence (R6, guided_setup_readback.lua:158-177); foreign/other-version place record never read or written (core/GuidedSetup.lua:66-101,143,149)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878), `guided_setup_resume` PASS (138), `guided_setup_readback` PASS (135), `ux_setup_replay` PASS (229)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878), `guided_setup_resume` PASS (138), `guided_setup_readback` PASS (135), `ux_setup_replay` PASS (229)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878), `guided_setup_resume` PASS (138), `guided_setup_readback` PASS (135), `ux_setup_replay` PASS (229)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ux_setup_checklist and ux_setup_replay changed only their Reference page-count expectation (7 -> 8 pages, FAQ appended); the cited checklist assertions are unchanged lines.
- **Spec:** `met-offline`. State-derived checklist and replay composition exist; no consent from No/Close (see UX-01).
- **Standards:** `no-hard-violation-found`. Place record is a new versioned, bounded field written only through StoreAuthorityOwner.UpdateStateV1 on a durable row; unknown fields of a v1 record preserved. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - 163008 native screenshots reported guide-local choice vs current assignment confusion on Step 2/Step 7; current source adds CurrentAssignment/'Assigned now' (core/GuidedSetup.lua:399-427; tests/prototype/visual_guide_context_163009.lua V1-V5) - not natively re-observed at this pin.
- **Native (#133, pending):** Coach Step 2 shows the already-assigned Wishlist as 'Assigned now' without completing the step; Step 7 readable; /reload resumes the step with every outcome read again; checklist rows/fonts at supported scales
- **Row disposition:** offline-supported; native pending

### UX-02 — Auto OFF recommendation does not identify the card

Canonical (verbatim):

```json
{"id": "UX-02", "kind": "originalUXfindingDesiredOutcome", "title": "Auto OFF recommendation does not identify the card", "requiredM7Disposition": "Verify accepted chosen-card/charges behavior composes with checklist and no-choice ready state.", "acceptanceProposals": ["Two Needed cards -> exactly one marked and named", "Auto OFF heading never says active", "No engine name in recommendations"]}
```

- **Adopted/current interpretation:** With Auto OFF the HUD identifies a card only when the runtime's current decision has one definite card target. A Take carries the Take marker ('>>' row, '> Wishlist pick' tag; core/AutomationRuntime.lua:3298-3299 highlight, ui/Readout.lua:81 MarkedCard). The adaptive Freeze for two or more different Needed offers (PAIR_FREEZE_SECOND_NEEDED) carries a separate, display-only Freeze mark ('[Freeze]' row, '> Freeze' tag; core/AutomationRuntime.lua:3303-3304, ui/Readout.lua:98 FreezeCard), never the Take marker, and the unstepped recommendation names that card. The canonical 'marked' is read as this action-specific mark: the Wishlist pick tag means Take, so a Freeze is not shown as a pick. The same Echo offered twice, or a decision without a card target, marks and names nothing (no guess). Reason text passes through UserText.Message (core/UserText.lua:93); its reasons table maps the three experimental adaptive labels without the engine name (:30-32). The Freeze wording is count-neutral ('Freeze one of the needed offers'). Policy (logic/EchoWeaver.lua) is unchanged.
- **Production symbols:** `core/AutomationRuntime.lua:3291-3308 cardLines: highlight (Take, :3298-3299), freeze display flag (:3303-3304)`; `core/AutomationRuntime.lua:3316 recommendation = action.reason`; `ui/Readout.lua:81 MarkedCard, :98 FreezeCard, :184 RecommendationWithTarget, :219 OFFER_FREEZE_TAG, :221 OfferCard (Freeze tag :259-261)`; `ui/Panel.lua:5268-5312 heading branches; :5286-5295 Orb-guidance branch, Auto OFF 'You choose' at :5291-5292`; `ui/Panel.lua:5316-5329 marked/frozen rows, :5340-5341 RenderOfferCards(..., frozen), :5348-5354 named body`; `ui/Panel.lua:3914 M.RenderOfferCards(lines, marked, auto, responsive, facts, frozen)`; `core/UserText.lua:21-32 reasons (experimental adaptive labels :30-32), :93 T.Message`; `logic/EchoWeaver.lua:199-211 LABELS, :369-387 adaptive PAIR_FREEZE redirect (unchanged)`
- **Callback chain:** offer -> Policy/EchoWeaver.DecideNexus -> decision.reason=LABELS[code] (logic/EchoWeaver.lua:317) -> runtime panel model with highlight/freeze per card (core/AutomationRuntime.lua:3294-3308, :3316) -> Panel ApplyModel heading (ui/Panel.lua:5268-5312) -> MarkedCard or FreezeCard (:5316-5322) -> row prefix and offer-card tag (:5326-5327, :5340-5341) -> UserText.Message reason + RecommendationWithTarget body (:5348-5354)
- **Discriminating assertions:**
  - tests/prototype/ux_manual_recommendation.lua:123-124 R1 Auto OFF heading says you choose, not active; :126-128 exactly one marked and named Take card (single Needed card)
  - :142-144 R1 duplicate same Echo -> no mark, no name; :149-150 no Take target -> no mark, reason without a guessed target
  - :475-499 R7 Auto OFF with Orb guidance: heading says you choose with the destination, never Active (:494); Open Orbs button and pause reason remain (:495-496); no effect (:499)
  - :512-548 R8 two different Needed offers: the real adaptive decision Freezes card 1 (:523); exactly that card is identified as a Freeze (:527), no Take marker (:529), named with Freeze wording (:532), no engine name in visible text (:534); fallback row '[Freeze] Echo 1 (Uncommon)' (:543)
  - :628-654 R10 three different Needed offers: exactly the decision's Freeze card identified (:646), no Take marker (:647), visible text makes no 'two needed'/'of two' claim (:651), no engine name (:653)
  - tests/prototype/orb_guidance_navigation.lua:218-223 real HUD, unknown Orb state, Auto OFF: heading not Active and says you choose; pause reason and inspection button stay; nothing performed
  - tests/prototype/terminology_consumers.lua:28 no '(EchoWeaver)' on the real Take path; :49-51,:57-58 the three experimental labels reach the actual Panel without the engine name; :1740-1741 actual policy PAIR_FREEZE_SECOND_NEEDED -> runtime -> Panel fontstring carries no engine name
- **Negative controls:** R1 duplicate same Echo and no Take target mark nothing (tests/prototype/ux_manual_recommendation.lua:142-150); R9 duplicate same-Echo Freeze marks and names nothing (:592-594); unknown charges keep the Take marker without a Freeze mark (:607); long name named whole (:620-621); R8 reordered board moves the Freeze mark (:561-563); an ordinary Take keeps its Wishlist pick marker and no Freeze mark remains (:569-570); no choice marks nothing (:574); R3/R8 Auto ON held and waiting headings keep their own words and no marker (:178,:180,:551,:554); R4 no Echo choice: no marker, nothing performed (:183-191); effects captured after setup unchanged: actions, sends, assignment calls, settings, Auto (:499,:548,:575,:654)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_manual_recommendation` PASS (124), `terminology_consumers` PASS, `terminology` PASS, `orb_guidance_navigation` PASS (70)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_manual_recommendation` PASS (124), `terminology_consumers` PASS, `terminology` PASS, `orb_guidance_navigation` PASS (70)
- **Lane runs (not the final pin):** `ux02-focused-82b7695` (23/23 passed at `82b7695`); `ux02-predecessor-red-0d16ba7` (expected RED: 1 expectation failure, 0 guard/setup failures)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_manual_recommendation` PASS (68), `terminology_consumers` PASS, `terminology` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - The cited heading region (ui/Panel.lua:5268-5312) gained a first branch for the session pause ('Nexus paused', model._nexusSessionPaused). The Orb-guidance branch (:5286-5295), Auto OFF 'You choose' (:5291-5292), Auto ON 'Active' (:5294) and the marking/naming code (:5316-5354) are byte-identical, only shifted.
- **Spec:** `met-offline-adopted-interpretation`. All three canonical proposals now have discriminating offline assertions through the real TOC boot, adapter, policy, runtime and Panel: two (and three) different Needed offers -> exactly the decision's card identified with a Freeze mark and named (R8, R10); Auto OFF heading never Active, including with Orb guidance (R7, orb_guidance_navigation); no engine name in visible recommendation or status text (R8-R10, terminology_consumers). Met under the adopted reading of 'marked' above. The former candidate gaps G-UX02-a and G-UX02-b are resolved in the final source. Its cited fixtures passed in the terminal complete passing runs at c7d2b74 and at 8393f5f.
- **Standards:** `no-hard-violation-found`. The Freeze flag is display metadata only: no decision, permission or action consumer reads it, and the Take highlight that automation reads is unchanged. Policy, consent, adapter and saved-data owners are unchanged. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - RESOLVED in final source (was CANDIDATE GAP G-UX02-a): the experimental adaptive labels are mapped (core/UserText.lua:30-32) and the Freeze target is identified separately from the Take marker. Lineage 6dcb46c -> 0d16ba7 -> 82b7695 (count-neutral wording), integrated unchanged in f399dd0.
  - RESOLVED in final source (was CANDIDATE GAP G-UX02-b): the Orb-guidance heading branch says 'You choose' with Auto OFF (ui/Panel.lua:5291-5292) and keeps 'Active: Slot N' for Auto ON only (:5294).
  - Coverage advisory retained from the independent UX-02 Spec review: an unresolved earlier-Orb state with Auto OFF is not directly tested (the tests drive an unknown Orb state); the negative 'Active' checks are case-sensitive, while the positive 'you choose' checks discriminate.
  - With Orb guidance shown the body is not rewritten to name a target (ui/Panel.lua:5351), as before for the Take marker.
  - Native font, scale, edge fit and screenshot usability of the new heading and Freeze tag are unverified.
- **Native (#133, pending):** Live board with two (and three) different Needed offers and Auto OFF: exactly the Freeze target shows the Freeze tag, no card shows the Wishlist pick tag, the recommendation names it, no engine name; Live board with one Needed offer and Auto OFF: exactly one card marked and named; Auto OFF heading never 'Active' including while Orb state is unknown; Heading and Freeze tag fit at supported font and UI scales
- **Row disposition:** offline-supported under the adopted reading of 'marked'; cited fixtures pass in the complete passing run at 8393f5f; native pending

### LP-02 — Compact charges row

Canonical (verbatim):

```json
{"id": "LP-02", "kind": "largerProposal", "title": "Compact charges row", "requiredM7Disposition": "Verify accepted chosen-card/charges behavior composes with checklist and no-choice ready state."}
```

- **Adopted/current interpretation:** Compact charges row 'B:n R:n F:n' (unknown '?', untrusted '~') shown only with Auto OFF and a board.
- **Production symbols:** `core/AutomationRuntime.lua:3087 Adapter.Charges read once per decision`; `core/AutomationRuntime.lua:3347 model.charges (Auto OFF only)`; `ui/Panel.lua:5784 _nexusChargeLine, :5363-5371 show/hide`; `ui/Readout.lua:308 ChargesLine`
- **Callback chain:** GameAdapter A.Charges (core/GameAdapter.lua:948) -> state.charges -> panelModel.charges -> Panel.Render -> charges text
- **Discriminating assertions:**
  - tests/prototype/ux_manual_recommendation.lua:351 'B:20 R:20 F:10' from the real producer
  - :371 unreported -> 'B:? R:? F:?' (unknown is not zero)
  - :377 untrusted '~'
  - :382 re-render makes no charge read
  - :390,:417 hidden between boards and with Auto ON
- **Negative controls:** partial host push upstream limitation stated (:359-365)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_manual_recommendation` PASS (124)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_manual_recommendation` PASS (124)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_manual_recommendation` PASS (68)
- **Spec:** `met-offline`. Composes with the no-choice ready state (no board -> no row).
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Freshness of real host charge pushes is native-only.
- **Native (#133, pending):** Charges row values match the game's own counters on a live board
- **Row disposition:** offline-supported; native pending

### UX-03 — Save/assign outcome chat-only; generic saved follows not-assigned

Canonical (verbatim):

```json
{"id": "UX-03", "kind": "originalUXfindingDesiredOutcome", "title": "Save/assign outcome chat-only; generic saved follows not-assigned", "requiredM7Disposition": "Verify accepted saved/unassigned/partial and save-intent results survive integrated refresh/cancel/context changes.", "acceptanceProposals": ["Generic success cannot replace unassigned/partial line", "Assign now / Cancel never uploads", "Failure line uses plain words"]}
```

- **Adopted/current interpretation:** The persistent save-result row in the editor carries saved/unassigned/partial/failed results and cannot be replaced by the generic success line; the generic 'Wishlist saved' chat line still follows in chat (accepted ordering, ux_save_assignment_result.lua:307). Assign now reuses the Journal chooser and never uploads.
- **Production symbols:** `core/WishlistController.lua:2591-2597 ApplyAndRecord`; `:2686 SaveResultCurrent`; `:2723 SaveResult`; `:2750 AssignNowCheck`; `:2484/:2500/:2511 chat lines`; `ui/WishlistRenderer.lua:3426 AssignNow -> JournalTab.OpenBuilds(true)`
- **Callback chain:** editor Save button -> confirmation popup -> ApplyAndRecord/TryApply -> GameAdapter writer -> state.saveResult -> RenderSaveResult ‖ Assign now... -> AssignNowCheck -> JournalTab.OpenBuilds(true) (UX-05 chain)
- **Discriminating assertions:**
  - tests/prototype/ux_save_assignment_result.lua:324 generic line does not replace the unassigned result row
  - :384 failure before generic; :392 no '_' code in the row; :397 partial row persists
  - :356,:426 no second upload from Assign now
  - tests/prototype/ux_auto_assignment_consent.lua:158 Cancel uploads nothing
- **Negative controls:** Cancel; refused upload; destination changed during host call (A10); owner change (:539); Saved Build emptied (C4b)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_save_assignment_result` PASS (155), `ux_save_intents` PASS (149), `ux_auto_assignment_consent` PASS (57), `ux_save_retry_intent` PASS (82)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_save_assignment_result` PASS (155), `ux_save_intents` PASS (149), `ux_auto_assignment_consent` PASS (57), `ux_save_retry_intent` PASS (82)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_save_assignment_result` PASS (155), `ux_save_intents` PASS (149), `ux_auto_assignment_consent` PASS (57), `ux_save_retry_intent` PASS (82)
- **Spec:** `met-offline-adopted-interpretation`. 'Generic success cannot replace unassigned/partial line' is met for the persistent row; the chat generic line is retained by accepted design.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Chat failure line appends the raw lowercase adapter reason in brackets (e.g. '(store unavailable)'); plain words, not a code - wording only.
- **Native (#133, pending):** Real editor save/unassigned/partial result row visible after refresh and chat ordering in the client
- **Row disposition:** offline-supported; native pending

### LP-03 — Explicit Save changes / Save & assign controller intents

Canonical (verbatim):

```json
{"id": "LP-03", "kind": "largerProposal", "title": "Explicit Save changes / Save & assign controller intents", "requiredM7Disposition": "Verify accepted saved/unassigned/partial and save-intent results survive integrated refresh/cancel/context changes."}
```

- **Adopted/current interpretation:** Explicit intents: Save changes (no assignment writer), Save & assign (bound destination writer), Create unassigned; intent and destinationKey bound into the confirmation and checked again before upload.
- **Production symbols:** `core/WishlistController.lua:183 INTENT, :1970-1985 IntentOf/DefaultIntent, :2232 destination re-check, :2381-2395 saveOnly`; `core/GameAdapter.lua:3268 UpdateWishlistAssociationAfterSave (token check)`; `ui/WishlistRenderer.lua:3033-3054 labels`
- **Callback chain:** intent button -> confirmation carries intent+destinationKey -> accept -> TryApply -> saveOnly or bound writer
- **Discriminating assertions:**
  - tests/prototype/ux_save_intents.lua:760 Save changes uploads once, assignment unchanged
  - :775 Save & assign through the existing writer
  - tests/prototype/ux_save_retry_intent.lua:197 retry runs no assignment writer
  - ux_save_retry_intent.lua R6-R8 (:331-365) refused before upload when the bound Saved Build was reassigned/unassigned
- **Negative controls:** retry, outside reassign/unassign, replayed confirmation (I5), host error (I7/I8)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_save_intents` PASS (149), `ux_save_retry_intent` PASS (82), `ux_auto_assignment_consent` PASS (57)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_save_intents` PASS (149), `ux_save_retry_intent` PASS (82), `ux_auto_assignment_consent` PASS (57)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_save_intents` PASS (149), `ux_save_retry_intent` PASS (82), `ux_auto_assignment_consent` PASS (57)
- **Spec:** `met-offline`. Distinct from UX-03: adds the controller intents themselves.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Intent buttons and confirmations in the client; one upload per confirmed save
- **Row disposition:** offline-supported; native pending

### UX-04 — Destination not named in confirmations or the main panel; first-run plan shows None

Canonical (verbatim):

```json
{"id": "UX-04", "kind": "originalUXfindingDesiredOutcome", "title": "Destination not named in confirmations or the main panel; first-run plan shows None", "requiredM7Disposition": "Finish shared captured destination strip across setup/status/editor and nil/unavailable/empty states.", "acceptanceProposals": ["Switch active Saved Build mid-edit -> dialog names captured destination", "First-run plan labelled as such"]}
```

- **Adopted/current interpretation:** Confirmations name the destination captured when editing began (WishlistController DestinationDescriptor), never the currently active slot; a first-run plan is labelled first-run (short Saved Build cell 'None' with state cell 'First run').
- **Production symbols:** `core/WishlistController.lua:1870 DestinationDescriptor`; `core/UserText.lua:208 SavedBuildLabel, :286 first-run short cell, :379 DestinationLines, :416 DestinationFields`; `ui/Panel.lua:922 DestinationFacts`
- **Callback chain:** editor open captures context -> DestinationDescriptor -> confirmation text / destination row
- **Discriminating assertions:**
  - tests/prototype/ux_captured_destination_labels.lua:283 dialog names Fire PvE, not Arena, after a mid-edit switch
  - :379 first-run plan labelled first-run
  - :402 empty captured Saved Build refused
  - tests/prototype/ux_destination_context.lua:192,:196
- **Negative controls:** draft begun with no Saved Build (A09b); unknown slot data (A14u)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_captured_destination_labels` PASS (452), `ux_destination_context` PASS (54)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_captured_destination_labels` PASS (452), `ux_destination_context` PASS (54)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_captured_destination_labels` PASS (452), `ux_destination_context` PASS (54)
- **Spec:** `met-offline`. Both canonical proposals asserted.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Mid-edit Saved Build switch in the client: dialog names the captured destination; first-run plan label legible in the HUD
- **Row disposition:** offline-supported; native pending

### LP-04 — Shared character/Saved Build/Wishlist/state strip

Canonical (verbatim):

```json
{"id": "LP-04", "kind": "largerProposal", "title": "Shared character/Saved Build/Wishlist/state strip", "requiredM7Disposition": "Finish shared captured destination strip across setup/status/editor and nil/unavailable/empty states."}
```

- **Adopted/current interpretation:** Shared four-cell destination strip (character / Saved Build / Wishlist / state) on the HUD and the editor; the setup checklist and coach word the destination from the same Panel.SetupFacts/TargetOptions facts but do not render the strip.
- **Production symbols:** `ui/Panel.lua:645 CreateDestinationRow, :668 UpdateDestinationRow (HUD :2121,:5686)`; `ui/WishlistRenderer.lua:1352,:2841 editor strip`; `core/UserText.lua:526 SetupChecklist`; `ui/GuidedSetup.lua:151 TargetLabel`
- **Callback chain:** Panel.Render/editor render -> UpdateDestinationRow from DestinationFacts
- **Discriminating assertions:**
  - tests/prototype/wishlist_editor_context_label.lua reads the four real cells
  - tests/prototype/ux_destination_context.lua D1-D5, D10-D12 empty/unassigned/unavailable/kept-unconfirmed/restoring
  - tests/prototype/ux_captured_destination_labels.lua B2/F4 font scale 2 and world-session invalidation
- **Negative controls:** nil/unavailable/empty states (D-scenarios)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_destination_context` PASS (54), `ux_captured_destination_labels` PASS (452)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_destination_context` PASS (54), `ux_captured_destination_labels` PASS (452)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_destination_context` PASS (54), `ux_captured_destination_labels` PASS (452)
- **Spec:** `partial`. Canonical disposition says 'across setup/status/editor'; strip is shared by status and editor only. Setup surfaces state the same facts in their own words.
- **Standards:** `no-hard-violation-found`. Possible Duplicated Code (judgement): destination wording exists in UserText.SetupChecklist and GuidedSetup TargetLabel beside the strip. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - SCOPE GAP: setup checklist/coach do not render the shared strip (ui/QuickStart.lua checklist rows; ui/GuidedSetup.lua:151). Owner decision whether shared facts suffice or the strip itself is required.
- **Native (#133, pending):** Strip fit and truncation at supported scales in HUD and editor
- **Row disposition:** offline-partial (scope); native pending

### UX-05 — Picker assigns on one click, silent success, Auto-ON consequence tooltip-only

Canonical (verbatim):

```json
{"id": "UX-05", "kind": "originalUXfindingDesiredOutcome", "title": "Picker assigns on one click, silent success, Auto-ON consequence tooltip-only", "requiredM7Disposition": "Integrate assignment readback/checklist; retain explicit distinct Auto-ON consent.", "acceptanceProposals": ["Auto OFF: one click assigns with visible confirmation", "Auto ON: confirm shown; Cancel changes nothing", "No Auto change without explicit click"]}
```

- **Adopted/current interpretation:** Auto OFF: one chooser click assigns to the captured destination and prints a visible confirmation. Auto ON (numbered non-empty target): NEXUS_ASSIGN_WISHLIST_AUTO_ON confirmation first; Cancel writes nothing; no Auto change from assignment.
- **Production symbols:** `ui/JournalTab.lua:1428 AssociateWishlistOnly`; `ui/JournalTab.lua:154 M.AssignWithConsent (owner re-check, accept once)`; `ui/JournalTab.lua:1454 A.SetLoadoutWishlist, :1470 confirmation line`; `ui/WishlistEditor.lua:720 ResolveAndAssignWishlist -> RolePicker (:516-546)`; `core/GameAdapter.lua:3236 A.SetLoadoutWishlist`
- **Callback chain:** chooser row OnClick -> AssociateWishlistOnly -> GuideOrigin -> AssignWithConsent -> (Auto ON) StaticPopup accepted later -> assign() -> A.SetLoadoutWishlist -> GuideAssign receipt -> RefreshAssociations -> chat confirmation ‖ no lock evidence -> ResolveAndAssignWishlist -> RolePicker confirm later -> SetLoadoutWishlist -> GuideNote('assign', origin='rolepicker')
- **Discriminating assertions:**
  - tests/prototype/ux_auto_assignment_consent.lua:312 Auto OFF assigns at once; :315 visible line
  - :335 Auto ON asks first; :346 Cancel writes nothing, Auto unchanged
  - :368 captured slot 2 written, not current active; :392 owner change refuses
  - tests/prototype/ux_assignment_consent_routes.lua:335,:465,:604 every Auto-ON route asks first; answer once
- **Negative controls:** cancel, stale owner, active selection changed, confirmation unavailable (N1), repeated answer
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_auto_assignment_consent` PASS (57), `ux_assignment_consent_routes` PASS (104), `guided_setup_readback` PASS (135)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_auto_assignment_consent` PASS (57), `ux_assignment_consent_routes` PASS (104), `guided_setup_readback` PASS (135)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_auto_assignment_consent` PASS (57), `ux_assignment_consent_routes` PASS (104), `guided_setup_readback` PASS (135)
- **Spec:** `met-offline`. All three canonical proposals asserted through real row clicks and popup handlers.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Chooser click with Auto OFF/ON in the client; Cancel leaves assignment and Auto unchanged
- **Row disposition:** offline-supported; native pending

### LP-05 — Destination strip and setup checklist integration

Canonical (verbatim):

```json
{"id": "LP-05", "kind": "largerProposal", "title": "Destination strip and setup checklist integration", "requiredM7Disposition": "Integrate assignment readback/checklist; retain explicit distinct Auto-ON consent."}
```

- **Adopted/current interpretation:** Assignment results feed the coach and checklist only through bound receipts plus fresh read back (core/GuidedSetup.lua G.Note/BeginAssign/AssignStatus).
- **Production symbols:** `core/GuidedSetup.lua:609 G.BeginAssign, :623 G.Note, :681 G.AssignStatus, :443 G.ReadAssignment`; `ui/JournalTab.lua:182 GuideAssign, :196 GuideOrigin`; `ui/WishlistEditor.lua:546,:644,:735 GuideNote`
- **Callback chain:** coach RouteChooser (ui/GuidedSetup.lua:2070) -> G.ArmAssign -> JournalTab.OpenBuilds(true) -> row click GuideOrigin -> outcome GuideAssign -> G.Note claims[r]=request -> AssignStatus verified only if token==read.action and read.key==wishlist key
- **Discriminating assertions:**
  - tests/prototype/guided_setup_readback.lua R2 :113-124 verified/unknown/stale
  - R5 :150-155 early/other-destination/forged never verify
  - R7 :211-216 delayed role choice pending until its own receipt
  - R9-R12 :295-338 old role choice / old Auto-ON confirmation not verified for a re-armed request
  - R15 :364-373 Cancel only for its own request
  - tests/prototype/ux_setup_checklist.lua:696-699 checklist readback 3 of 3
- **Negative controls:** R3 refused, R4 other Wishlist, R13 missing/foreign origin, R14 operation before any request
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `guided_setup_readback` PASS (135), `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `guided_setup_readback` PASS (135), `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `guided_setup_readback` PASS (135), `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Spec:** `met-offline`. Distinct from UX-05: adds readback/checklist integration; Auto-ON consent unchanged.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Delayed role picker and Auto-ON confirmation timing in the client
- **Row disposition:** offline-supported; native pending

### UX-06 — Assign Wishlist lands on the game page, not the chooser

Canonical (verbatim):

```json
{"id": "UX-06", "kind": "originalUXfindingDesiredOutcome", "title": "Assign Wishlist lands on the game page, not the chooser", "requiredM7Disposition": "Verify direct assignment chooser link without assignment on open/cancel.", "acceptanceProposals": ["Assign Wishlist -> picker visible with destination title"]}
```

- **Adopted/current interpretation:** Every Assign Wishlist route opens the Echo Journal with its Wishlist chooser already open and titled 'Assign to: <destination>'; opening/cancelling assigns nothing; an empty Saved Build's chooser says assigning is refused.
- **Production symbols:** `ui/Help.lua:467 H.OpenAssignment -> Panel.OpenAssignment`; `ui/QuickStart.lua:636 checklist Assign Wishlist...`; `ui/GuidedSetup.lua:2070 U.RouteChooser`; `ui/JournalTab.lua OpenBuilds(true)`
- **Callback chain:** Help/checklist/panel Assign -> guarded Panel.OpenAssignment -> JournalTab.OpenBuilds(true) -> chooser titled with captured target
- **Discriminating assertions:**
  - tests/prototype/ux_help_navigation.lua:135 chooser open and titled 'Assign to: One'; :136 opening assigns/acts/sends nothing; :139 closing assigns nothing
  - :203 empty Saved Build chooser 'assigning is refused'
  - tests/prototype/ux_setup_checklist.lua J2 (tests/prototype/ux_setup_checklist.lua:645) title=='Assign to: Fire PvE'
- **Negative controls:** missing Character Progression button said before closing windows (H3 :150-164); loading refusal (H1 :106-114)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_help_navigation` PASS (32), `ux_setup_checklist` PASS (192)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_help_navigation` PASS (32), `ux_setup_checklist` PASS (192)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_help_navigation` PASS (32), `ux_setup_checklist` PASS (192)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ux_help_navigation and ux_setup_checklist changed only their Reference page-count expectations (7 -> 8 pages); the cited assertions are unchanged lines.
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Real Character Progression/Echo Journal page opens with the chooser visible and titled
- **Row disposition:** offline-supported; native pending

### LP-06 — Checklist direct assignment links

Canonical (verbatim):

```json
{"id": "LP-06", "kind": "largerProposal", "title": "Checklist direct assignment links", "requiredM7Disposition": "Verify direct assignment chooser link without assignment on open/cancel."}
```

- **Adopted/current interpretation:** Checklist and coach provide direct assignment links (checklist 'Assign Wishlist...', coach chooser/My Builds routes) that only navigate.
- **Production symbols:** `ui/QuickStart.lua:624-638 route()/f.assign`; `ui/GuidedSetup.lua:2070 RouteChooser, :2100 RouteBuilds`
- **Callback chain:** checklist Assign -> Help.OpenAssignment (see UX-06); coach Open chooser -> G.ArmAssign then OpenBuilds(true); refused route shown in window (f.notice)
- **Discriminating assertions:**
  - tests/prototype/ux_setup_checklist.lua K6 (:222-335) buttons/routes only navigate; :271-274 refused coach reason in the window
  - J2 (tests/prototype/ux_setup_checklist.lua:640-658) Assign Wishlist... opens chooser, cancel assigns nothing
  - tests/prototype/guided_setup_flow.lua F14/F15 (:1015,:1138) target routes and My Builds route
- **Negative controls:** F16 stale My Builds answer after Close/reopen changes nothing
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ux_setup_checklist K6 (:222-335) changed one expectation: the Reference opens on 'Page 1 / 8' (FAQ appended). The K6 navigation-only guards are unchanged.
- **Spec:** `met-offline`. Distinct from UX-06: links originate in the checklist/coach.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Checklist/coach links open the real Journal chooser and My Builds page
- **Row disposition:** offline-supported; native pending

### UX-07 — Orb Resume after target change adopts a new target from unnamed compact controls

Canonical (verbatim):

```json
{"id": "UX-07", "kind": "originalUXfindingDesiredOutcome", "title": "Orb Resume after target change adopts a new target from unnamed compact controls", "requiredM7Disposition": "Reconcile actual accepted-M6 target review and fix rendered-key race if still present.", "acceptanceProposals": ["Target change while paused -> all surfaces name the new target before Resume"]}
```

- **Adopted/current interpretation:** A changed target while paused is named on the full window, strip and mini; Resume is refused until the exact current key was drawn and reviewed; the click re-reads OrbRuntime.Status and compares the fresh key. No rendered-key race found.
- **Production symbols:** `ui/OrbPanel.lua:137-153 review/reviewHeld/reviewRefusal`; `ui/OrbPanel.lua:601-615 Resume handler (fresh Status, reviewRefusal)`; `ui/OrbPanel.lua:690-713 Review target (drawnKey==shownKey==fresh key)`; `core/OrbRuntime.lua:3383 M.Resume, :3412-3420 adopt/limit/token`; `core/OrbRuntime.lua:3750,:3778-3782 resumeTargetView key`
- **Callback chain:** Pump marks targetChanged and pauses (core/OrbRuntime.lua:3087-3094) -> Status().resumeTarget kind 'changed' -> window/strip/mini name it -> Review click (key check) -> Resume click re-reads Status -> reviewRefusal -> OrbRuntime.Resume -> Rebind/adopt
- **Discriminating assertions:**
  - tests/prototype/orb_target_review.lua:157 "New target: Resume would use 'New legitimate target' instead of 'Orb test'"
  - :172-174 strip and :191 mini name the new target
  - :207-208 window Resume refuses 'Review the new target first'
  - :227 no effect across window/Start/strip/hidden primary/mini Resume
  - :263 Resume adopts exactly the reviewed assignment
  - tests/prototype/orb_review_identity.lua:100-124 stale Review/Cancel
- **Negative controls:** third assignment different key (:246-250); closing window clears review (:255); returned target (I3)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_target_review` PASS (152), `orb_review_identity` PASS (77), `orbs_target_changes` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_target_review` PASS (152), `orb_review_identity` PASS (77), `orbs_target_changes` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_target_review` PASS (152), `orb_review_identity` PASS (77), `orbs_target_changes` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ui/OrbPanel.lua adds a session-only 'Hide until next run' on the main-panel strip for a settled, ended run only (#167); it replaces Pause/Resume/Stop only for such a run and is not offered for a paused, changed-target or recovery state. core/OrbRuntime.lua M.Resume (:3383-3420) gained a session-pause refusal. The cited target-review chains are byte-identical, only shifted.
- **Spec:** `partial`. Window, strip and mini name the new target before Resume, and the rendered-key race is not present at this pin (the click re-reads and compares the fresh key). The canonical proposal says all surfaces, but the Play-panel Orb line does not name the changed target. Whether that line counts as a surface is an unresolved owner interpretation, so the row is not unqualified met.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - TEST GAP: no fixture clicks a still-enabled Resume after the assignment changed without a redraw (orb_target_review.lua:243-249 calls UI.Refresh first). Current code is correct (ui/OrbPanel.lua:602 re-reads, :612 compares).
  - INTERPRETATION: the Play-panel Orb line (ui/OrbPanel.lua:1664-1684 UI.PanelRunLine) shows state, usage, wait and reason, but not the changed target. It offers no Resume (Open only). Owner decision whether 'all surfaces' includes it.
- **Native (#133, pending):** Target change while paused in the client: window, strip and mini name the new target before Resume
- **Row disposition:** offline-partial (Play-line interpretation open; test gap recorded); native pending

### LP-07 — Full-window re-review after changed Orb target

Canonical (verbatim):

```json
{"id": "LP-07", "kind": "largerProposal", "title": "Full-window re-review after changed Orb target", "requiredM7Disposition": "Reconcile actual accepted-M6 target review and fix rendered-key race if still present."}
```

- **Adopted/current interpretation:** Full-window re-review: review is per key, cleared on any key change and on close; the hidden legacy primary path applies the same review.
- **Production symbols:** `ui/OrbPanel.lua:137 review, :396 clear on key change, :690-713 per-key review, :161-168 primary path`
- **Callback chain:** Refresh sets drawnKey/shownKey from one target (:476,:528-531) -> Review only when drawn==shown==fresh -> Resume enabled when not held (:513-515)
- **Discriminating assertions:**
  - tests/prototype/orb_target_review.lua:247-248 review never carries to another assignment
  - :255 close clears review
  - tests/prototype/orb_review_identity.lua:106-107 only the redrawn button reviews B; I3 :152 returned target needs review
- **Negative controls:** stale Cancel; returned target
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_target_review` PASS (152), `orb_review_identity` PASS (77)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_target_review` PASS (152), `orb_review_identity` PASS (77)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_target_review` PASS (152), `orb_review_identity` PASS (77)
- **Spec:** `met-offline`. Distinct from UX-07: the re-review gate itself.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Same stale-enabled Resume test gap as UX-07.
- **Native (#133, pending):** Re-review flow in the client window
- **Row disposition:** offline-supported; test gap recorded; native pending

### UX-08 — Pause/Resume share a button in full window and main-panel strip

Canonical (verbatim):

```json
{"id": "UX-08", "kind": "originalUXfindingDesiredOutcome", "title": "Pause/Resume share a button in full window and main-panel strip", "requiredM7Disposition": "Preserve actual accepted-M6 fixed controls; reserve real double-click proof for M8.", "acceptanceProposals": ["Double-click Pause leaves run paused"]}
```

- **Adopted/current interpretation:** Separate Pause and Resume buttons; repeated Pause keeps PAUSED and has no effect; real double-click proof reserved for native (M8/#133).
- **Production symbols:** `ui/OrbPanel.lua:597-600 Pause (re-reads running)`; `ui/OrbPanel.lua:1329-1333 strip Pause, :1792-1809/:1836 mini`; `core/OrbRuntime.lua:3330 M.Pause`
- **Callback chain:** Pause click -> Status().running check -> OrbRuntime.Pause -> notify -> Refresh disables Pause
- **Discriminating assertions:**
  - tests/prototype/orb_fixed_pause_resume.lua:69-72 Pause then two direct Pause calls keep PAUSED, Same(before,Effects())
  - :76 Pause after an offer never resumes
  - :117-118 strip
  - tests/prototype/orb_mini_panel.lua:30-31 repeated Pause never resumes or spends
- **Negative controls:** repeated Resume adds nothing (:82-83,:124-125)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_fixed_pause_resume` PASS (51), `orb_mini_panel` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_fixed_pause_resume` PASS (51), `orb_mini_panel` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_fixed_pause_resume` PASS (51), `orb_mini_panel` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - The main-panel strip shows 'Hide until next run' instead of Pause/Resume/Stop only for a settled, ended run (#167), where those controls are disabled anyway; M.Resume (core/OrbRuntime.lua:3383-3420) and Pump gained session-pause holds. The cited Pause/Resume controls and assertions are unchanged, only shifted.
- **Spec:** `met-offline`. Native double-click explicitly reserved by the canonical disposition.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Native OnDoubleClick/disabled-button hit testing not covered (fixture header says not a native double-click proof).
- **Native (#133, pending):** Real double-click on Pause in window/strip/mini leaves the run paused
- **Row disposition:** offline-supported; native double-click pending

### LP-08 — Separate fixed Pause and Resume controls

Canonical (verbatim):

```json
{"id": "LP-08", "kind": "largerProposal", "title": "Separate fixed Pause and Resume controls", "requiredM7Disposition": "Preserve actual accepted-M6 fixed controls; reserve real double-click proof for M8."}
```

- **Adopted/current interpretation:** Fixed controls: Pause/Resume replace Start in the same row with fixed labels; strip hides the shared primary.
- **Production symbols:** `ui/OrbPanel.lua:438-439 window swap`; `:1325 strip hides f.primary, :1329-1338 pause/resume`; `:1874-1875 mini`
- **Callback chain:** Refresh shows fixed Pause/Resume per state
- **Discriminating assertions:**
  - tests/prototype/orb_fixed_pause_resume.lua:53 Pause and Resume replace Start
  - :56-60 same row, >=6 px padding
  - :66,:119 labels never change
  - :99 strip primary hidden
  - :146-149 mini positions
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_fixed_pause_resume` PASS (51), `orb_mini_panel` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_fixed_pause_resume` PASS (51), `orb_mini_panel` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_fixed_pause_resume` PASS (51), `orb_mini_panel` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - Same strip change as UX-08 (settled ended run only); the fixed Pause/Resume controls cited are byte-identical, only shifted (ui/OrbPanel.lua:1874-1875).
- **Spec:** `met-offline`. Distinct from UX-08: control layout itself.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Pixel geometry is the 7 px text model only.
- **Native (#133, pending):** Pause/Resume positions and labels at supported scales
- **Row disposition:** offline-supported; native pending

### UX-09 — Why Auto is not acting is hidden behind ...

Canonical (verbatim):

```json
{"id": "UX-09", "kind": "originalUXfindingDesiredOutcome", "title": "Why Auto is not acting is hidden behind ...", "requiredM7Disposition": "Finish shared visible Auto/Sync/Orb current reason without triggering work.", "acceptanceProposals": ["Refused Auto click shows a visible reason", "Ready state reads in plain words"]}
```

- **Adopted/current interpretation:** A refused Auto click stores a visible reason shown in the roll block for 60 s ('Auto stayed OFF: ...' plus 'What helps:'); hold reasons visible in heading/body; ready state reads 'Roll status' / 'No Echo choice is showing.'.
- **Production symbols:** `ui/Panel.lua:2626-2635 Auto button OnClick`; `ui/Panel.lua:6365-6401 M.NoteAutoClick`; `ui/Panel.lua:6079-6113 M.AutoNoteFor`; `ui/Readout.lua:465 AutoRefusalText, :456 AutoHoldNote`; `core/AutomationRuntime.lua:4625 ToggleAuto, :4536 actionHold.Effective`
- **Callback chain:** Auto click -> callbacks.ToggleAuto (core/MainLifecycle.lua:809) -> AutomationRuntime.ToggleAuto -> refusal/RequestAuto -> Panel.NoteAutoClick -> re-render -> AutoNoteFor -> roll-block body
- **Discriminating assertions:**
  - tests/prototype/ux_automation_scope.lua:499 'Auto stayed OFF: an Orb run is active or unresolved' + 'What helps:' (real click)
  - :506 cleared after Auto ON
  - :465 'Auto ON — paused' with reason
  - tests/prototype/hud_roll_footprint.lua:180-182 waiting + AutoHoldNote; :125,:192 ready state 'Roll status' / 'No Echo choice is showing.'
- **Negative controls:** P14 :502 refused click does no work; P15 :536 answered No is not a refusal
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_automation_scope` PASS (97), `ux_status_composition` PASS (81), `overwrite_auto_gate` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_automation_scope` PASS (97), `ux_status_composition` PASS (81), `overwrite_auto_gate` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_automation_scope` PASS (97), `ux_status_composition` PASS (81), `overwrite_auto_gate` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ToggleAuto gained a session-pause refusal that keeps Auto OFF; the cited Orb-run refusal path and HUD assertions (ux_automation_scope.lua:465, :499, :506) are unchanged, only shifted. The AutoTooltip helper change in ux_automation_scope is not used by this row's cited assertions.
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Refusal kinds other than Orb-block ('warning', status fallback) have no fixture.
  - Tooltip 'Now: ready' not asserted.
- **Native (#133, pending):** Refused Auto click reason visible without hover in the client
- **Row disposition:** offline-supported; native pending

### LP-09 — Unified Auto/Sync/Orb status and inline reason area

Canonical (verbatim):

```json
{"id": "LP-09", "kind": "largerProposal", "title": "Unified Auto/Sync/Orb status and inline reason area", "requiredM7Disposition": "Finish shared visible Auto/Sync/Orb current reason without triggering work."}
```

- **Adopted/current interpretation:** One shared three-line status (Auto / Sync / Orb) from Panel.SetupFacts via UserText.StatusLines in the setup checklist; reading does no work. A refused-click reason with Auto OFF appears in the roll block, not in this shared line.
- **Production symbols:** `ui/Panel.lua:1081-1111 SetupFacts`; `core/UserText.lua:639-658 StatusLines, :612 OrbLine`; `ui/QuickStart.lua:562-563`
- **Callback chain:** checklist refresh -> Panel.SetupFacts -> UserText.StatusLines -> status lines
- **Discriminating assertions:**
  - tests/prototype/ux_status_composition.lua:233 Auto OFF reads OFF; :238 'Auto: ON' + 'not acting now'
  - :256 each Sync mode stated; :261 unreadable mode 'not known'
  - :342-352 real OrbRuntime pause reason and 'Open Orbs'; read does no work
- **Negative controls:** :239 reading turns nothing ON; :289; :354
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_status_composition` PASS (81), `ux_setup_checklist` PASS (192)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_status_composition` PASS (81), `ux_setup_checklist` PASS (192)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_status_composition` PASS (81), `ux_setup_checklist` PASS (192)
- **Spec:** `met-offline-adopted-interpretation`. Unified status area exists in the checklist; HUD keeps its own roll-block reason.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - If LayoutMetrics failed to load, AutoNoteFor could return AUTO_ON_NOTE for an acting Auto (ui/Panel.lua:6098-6101) -> 'not acting now' would be untrue; TOC loads LayoutMetrics, so failure-mode only.
- **Native (#133, pending):** Checklist status lines legible and current in the client
- **Row disposition:** offline-supported; native pending

### UX-10 — What Auto will do is not listed (actions, automatic save, tome changes)

Canonical (verbatim):

```json
{"id": "UX-10", "kind": "originalUXfindingDesiredOutcome", "title": "What Auto will do is not listed (actions, automatic save, tome changes)", "requiredM7Disposition": "Verify accepted existing-permission disclosure/defaults and no change from viewing settings.", "acceptanceProposals": ["Tooltip lists each enabled action with on/off", "Help mentions tome changes"]}
```

- **Adopted/current interpretation:** Approved presentation alternative (coordinator decision for UX-10 at 8393f5f, under the user's existing approval of the assessed usability suggestions; public scope #169): the short Auto hover gives the current state, the next action, the essential consequence (charges and Saved Build changes; Orb runs need their own approval) and an explicit route to the full details ('Full details: Options > Auto explained.'). The separate Auto explained view (the Help Auto page opened from Options > 'Auto explained (full details)'), the Auto warning and Help disclose each current permission with on/off from current settings and the tome behavior. That full view is not itself a tooltip; the canonical wording 'Tooltip lists each enabled action with on/off' is preserved verbatim and met under this adopted reading.
- **Production symbols:** `ui/Readout.lua:497-526 AutomationScopeLines, :532 TOME_PARAGRAPH`; `ui/Panel.lua:2638 Auto OnEnter -> :6043-6061 M.ShowAutoTooltip, :6008-6041 M.AutoSummaryLines (short hover: state, next click, essential consequence, 'Full details: Options > Auto explained.'; no per-permission list)`; `ui/Panel.lua:3168-3172 Options 'Auto explained (full details)' -> Help.Show('rolling'); :5960-6004 M.AutoDetailLines (Readout.AutomationScopeLines with current values, hold, Now)`; `ui/Help.lua:307-316 rolling page appends Panel.AutoDetailLines below its complete text`; `ui/OverwriteWarning.lua:18-38 BodyText`; `ui/Help.lua:58 'rolling' page`; `data/DefaultProfile.lua:32-46 defaults`
- **Callback chain:** Auto hover OnEnter (ui/Panel.lua:2638) -> M.ShowAutoTooltip -> M.AutoSummaryLines: state, next click, consequence, details route; no permission list ‖ Options 'Auto explained (full details)' (ui/Panel.lua:3168-3172) -> Help.Show('rolling') -> Help page body + Panel.AutoDetailLines (ui/Help.lua:307-316) -> Readout.AutomationScopeLines(settings), read only ‖ Auto warning Show -> BodyText (ui/OverwriteWarning.lua:18-38) -> AutomationScopeLines(settings) + TOME_PARAGRAPH, read only
- **Discriminating assertions:**
  - tests/prototype/crimson_panel_auto_help.lua:66-69 A1 real Auto OFF hover (OnEnter): the Short check (:52-55) holds it to at most 6 lines / 420 characters, without '(autoPick)' or '(autoBanish)' (:53-54), naming 'Options > Auto explained' (:55); it says Auto is OFF and you choose (:67), what to click (:68) and that ON may spend charges and change the Saved Build (:69)
  - :112-128 A6 the real Options 'Auto explained (full details)' row is offered (:112) and opens the Help Auto page (:115); its body includes every existing disclosure and each permission with its current value, (autoPick) through (autoLockEchoes), the tome-permission wording, Activate a Saved Build: never, Orb runs: never by Auto, and the hold and Now lines (:117-124, check at :123); the complete Auto reference stays first (:128)
  - :152 A8 hovering and showing and closing Help, FAQ and the details page change no setting, consent, tutorial state, assignment, action, send or Auto
  - tests/prototype/ux_automation_scope.lua:183-190 the real hover plus the Help page opened through the real Options 'Auto explained (full details)' row (helper :91-105) name each permission with its value and existing control, Activate never and Orb runs never
  - :228 after a real '/nexus reroll off', the same joined hover + details text shows (autoReroll): off
  - :523-531 warning lists permissions and TOME_PARAGRAPH
  - :548-553 Help 'What Auto may do:' and tome paragraph
- **Negative controls:** :191-192 hover changes nothing; :534; :559; tests/prototype/crimson_panel_auto_help.lua A2-A5 (:75, :84, :93, :103): the selected-ON, held, refused-click and session-paused hovers stay short without the permission list
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_automation_scope` PASS (97), `session_permissions` PASS, `crimson_panel_auto_help` PASS (61)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_automation_scope` PASS (97), `session_permissions` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_automation_scope` PASS (97), `session_permissions` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - Changed region: the Auto hover was replaced by a short summary (#169). At c7d2b74 the hover itself listed Readout.AutomationScopeLines; at 8393f5f the per-permission list with current values is on the Help Auto page reached through Options > 'Auto explained (full details)', and the hover ends 'Full details: Options > Auto explained.'. tests/prototype/crimson_panel_auto_help.lua (new at 8393f5f, PASS, 61 checks) is now cited for the short hover (A1) and the full view (A6, A8). It has no c7d2b74 or 9bfb2bb execution.
- **Spec:** `met-offline-adopted-interpretation`. Met under the approved short-hover interpretation above. Proposal 1: the short hover's state, next action, consequence and details route are asserted by crimson_panel_auto_help A1 (and A2-A5 stay short); each permission with its current on/off value is asserted in the Auto explained view by A6 and by ux_automation_scope P1/P3 through the real Options row, and in the Auto warning by P15. Proposal 2: the Help Auto page and the warning carry the tome paragraph (P15, P16; A6). Viewing changes nothing (A8; P1, P15, P16 guards). History: met-offline at c7d2b74, when the hover itself listed the permissions; carried pending a coordinator decision in be8af43; resolved to this disposition by the coordinator decision recorded below.
- **Coordinator decision (resolved at 8393f5f):** met-offline-adopted-interpretation: the short hover gives state, next action, essential charges/Saved Build consequence and an explicit full-details route; the separate Auto explained view, the warning and Help disclose each current permission on/off and the tome behavior. The separate view is not called a tooltip. Authority: the user's existing approval of the assessed usability suggestions (2026-10-29), which includes the shorter Auto summary with accessible detailed consequences; public scope #169; recorded by the root coordinator. Decision record SHA-256 `92fd208d03766da6bc175bcdeb5f98235db78176398df08f5be7fccceb7a13a6`. Resolved observation: NEW SOURCE OBSERVATION (not resolved here): the canonical proposal 'Tooltip lists each enabled action with on/off' is no longer met by the Auto hover at 8393f5f (ui/Panel.lua:6008-6061); the per-permission list is on Options > 'Auto explained (full details)' -> Help 'rolling' page (ui/Panel.lua:3168-3172, :5960-6004; ui/Help.lua:307-316). Issue #131 comment 6502167124 records owner approval of a shorter first Auto explanation with an accessible complete consequences view. The cited assertion ux_automation_scope.lua:183-188 passes on the joined hover + details text. Coordinator/owner decision: keep met-offline, record met-offline-adopted-interpretation (the complete view counts as the tooltip), or partial. Counts are unchanged until then.
- **Standards:** `no-hard-violation-found`. Defaults unchanged (data/DefaultProfile.lua). Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Tooltip wrapping and Help text legibility in the client
- **Row disposition:** offline-supported under the approved short-hover interpretation (Auto explained view, warning and Help disclose each permission and tomes); native pending

### LP-10 — Existing-permission Automation scope/settings panel

Canonical (verbatim):

```json
{"id": "LP-10", "kind": "largerProposal", "title": "Existing-permission Automation scope/settings panel", "requiredM7Disposition": "Verify accepted existing-permission disclosure/defaults and no change from viewing settings."}
```

- **Adopted/current interpretation:** Automation settings submenu/window over existing permissions: only Reroll and Freeze act, through their existing slash setters; other rows display or navigate.
- **Production symbols:** `ui/Readout.lua:543-580 AutomationSettingsRows`; `ui/Panel.lua:6124-6167 AutomationMenuItems`; `ui/SettingsWindow.lua:66-69,:117`
- **Callback chain:** menu row click -> MenuAction -> SlashCmdList.NEXUS('reroll|freeze on|off') -> existing setter
- **Discriminating assertions:**
  - tests/prototype/ux_automation_scope.lua:405-411 every row and value
  - :414-417 Take/Activate disabled with func==nil
  - :427 Reroll row changes only autoReroll
  - :440 Lock row opens editor, changes no setting
  - tests/prototype/full_ui_settings.lua:28-29 serialized NexusDB unchanged across categories
- **Negative controls:** :418-419 opening menu changes nothing, Auto OFF
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_automation_scope` PASS (97), `full_ui_settings` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_automation_scope` PASS (97), `full_ui_settings` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_automation_scope` PASS (97), `full_ui_settings` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - The cited menu assertions (ux_automation_scope.lua:405-419, :427, :440) read the Automation settings submenu, not the changed AutoTooltip helper; they are unchanged, only shifted.
- **Spec:** `met-offline`. Distinct from UX-10: the settings surface.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - full_ui_settings does not assert autoEnabled directly (saved bytes/actions/sends only).
- **Native (#133, pending):** Dropdown drawing and row clicks in the client
- **Row disposition:** offline-supported; native pending

### UX-11 — Copy into Editor and Share Build share one button; publish unconfirmed

Canonical (verbatim):

```json
{"id": "UX-11", "kind": "originalUXfindingDesiredOutcome", "title": "Copy into Editor and Share Build share one button; publish unconfirmed", "requiredM7Disposition": "Close stale Share approval and Retry Share truthfulness while retaining accepted distinct Copy/Share/consent behavior.", "acceptanceProposals": ["Clicking Share on own Saved Build shows confirmation; Cancel sends nothing"]}
```

- **Adopted/current interpretation:** Copy into Editor and Share are separate buttons; Share on an own Saved Build shows NEXUS_SHARE_SAVED_BUILD; Cancel/Escape/closed Library/changed owner or content share nothing; only the latest shown approval is live; Retry Share states its reason and actual outcome.
- **Production symbols:** `ui/CommunityRenderer.lua:2088-2126 Copy (:2103 never shares a Saved Build)`; `:2384-2433 Share OnClick, :2253-2341 ConfirmedShare, :2343-2377 dialog and OnHide retirement`; `:2151-2190 Retry Share`; `core/CommunityController.lua:3364-3532 PublishImportedBuild, :3059-3173 retry`
- **Callback chain:** Share click -> approval stored -> StaticPopup -> Accept -> ConfirmedShare (approval/identity/Library checks) -> PublishImportedBuild -> Finish re-checks -> BroadcastIfPossible -> actual admission line
- **Discriminating assertions:**
  - tests/prototype/ux_share_confirmation.lua:269 opening confirmation sends nothing
  - :319 Cancel shares nothing
  - :301 Copy on a Saved Build shares nothing
  - :382 Accept shares the confirmed build, not the selected one
  - :426 approval cannot share twice
  - tests/prototype/ux_share_approval_retirement.lua:227-266 late/retired approvals share nothing
  - tests/prototype/ux_retry_share_feedback.lua:153-226 truthful Retry
- **Negative controls:** Escape, closed Library + late Accept, changed title/player, pending Share (:474)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_share_confirmation` PASS (327), `ux_share_approval_retirement` PASS (40), `ux_retry_share_feedback` PASS (36), `ux_share_admission` PASS (129)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_share_confirmation` PASS (327), `ux_share_approval_retirement` PASS (40), `ux_retry_share_feedback` PASS (36), `ux_share_admission` PASS (129)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_share_confirmation` PASS (327), `ux_share_approval_retirement` PASS (40), `ux_retry_share_feedback` PASS (36), `ux_share_admission` PASS (129)
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Native popup OnAccept/OnHide ordering relied on (ui/CommunityRenderer.lua:2360) is modelled only.
- **Native (#133, pending):** Share confirmation in the client; Cancel sends nothing on the wire
- **Row disposition:** offline-supported; native pending

### LP-11 — Dedicated Share action area

Canonical (verbatim):

```json
{"id": "LP-11", "kind": "largerProposal", "title": "Dedicated Share action area", "requiredM7Disposition": "Close stale Share approval and Retry Share truthfulness while retaining accepted distinct Copy/Share/consent behavior."}
```

- **Adopted/current interpretation:** Dedicated Share position: Share (or Delete/Stop Sharing) alone at the right of the action row; Copy/Retry/Edit on the left; mutually exclusive by state.
- **Production symbols:** `ui/CommunityRenderer.lua:384-408 layout, :2749-2761 refresh exclusivity`
- **Callback chain:** detail refresh -> button visibility/placement
- **Discriminating assertions:**
  - tests/prototype/ux_share_confirmation.lua:291 BOTTOMRIGHT/BOTTOMLEFT anchors
  - :287 Copy hidden on a Saved Build
  - :433 'Update Shared Build...' label
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_share_confirmation` PASS (327)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_share_confirmation` PASS (327)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_share_confirmation` PASS (327)
- **Spec:** `met-offline-adopted-interpretation`. 'Action area' implemented as a separate right-hand position in the shared row, not a separate panel region.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Action row layout and wrapping in the client
- **Row disposition:** offline-supported; native pending

### UX-12 — Automatic sends not disclosed; Sync status jargon

Canonical (verbatim):

```json
{"id": "UX-12", "kind": "originalUXfindingDesiredOutcome", "title": "Automatic sends not disclosed; Sync status jargon", "requiredM7Disposition": "Close full/detail/linked-DPS/refusal disclosure and source-policy controls without new policy/defaults.", "acceptanceProposals": ["Welcome/Help state what may be sent automatically", "Same Sync words in Library and Leaderboard"]}
```

- **Adopted/current interpretation:** Welcome, Help, Build Library and Leaderboard disclose what Automatic Sync may send; Library and Leaderboard Sync Now tooltips use identical words; viewing never sets a mode.
- **Production symbols:** `core/SyncModePolicy.lua:37 Mode, :46 Text, :146 Allows`; `ui/QuickStart.lua:32-42 SyncNote`; `ui/CommunityRenderer.lua:18, :3707-3716, :4008-4011`; `ui/Leaderboard.lua:1295-1307`; `ui/Help.lua sharing page`
- **Callback chain:** window show/tooltip -> SyncModePolicy.Mode/Text read only -> text
- **Discriminating assertions:**
  - tests/prototype/ux_sync_disclosure.lua:232 Welcome line
  - :235 Leaderboard tooltip words == Library tooltip words (real OnEnter)
  - :253 Library status Automatic line
  - :320-356 Help sentences
  - tests/prototype/ux_sync_disclosure_sends.lua:107-121 Automatic sends, Manual/Off send none (two real runtimes)
- **Negative controls:** ux_sync_disclosure.lua:223,:228 viewing changes no send/queue/mode/saved byte
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_sync_disclosure` PASS (154), `ux_sync_disclosure_sends` PASS (27), `ux_sync_dps_page` PASS (256), `ux_share_linked_dps` PASS (71), `ux_sync_status_fit` PASS (7945)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_sync_disclosure` PASS (154), `ux_sync_disclosure_sends` PASS (27), `ux_sync_dps_page` PASS (256), `ux_share_linked_dps` PASS (71), `ux_sync_status_fit` PASS (7945)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_sync_disclosure` PASS (154), `ux_sync_disclosure_sends` PASS (27), `ux_sync_dps_page` PASS (256), `ux_share_linked_dps` PASS (71), `ux_sync_status_fit` PASS (7945)
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. No new policy/default. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Checklist Sync line (core/UserText.lua StatusLines) uses different words from the Library/Leaderboard text (wording only).
  - Settings Sync row detail empty for Automatic (ui/SettingsWindow.lua:75) - wording only.
  - Real network delivery native-only.
- **Native (#133, pending):** Disclosure text legible in Welcome/Help/Library/Leaderboard; observed sends match the stated mode
- **Row disposition:** offline-supported; native pending

### LP-12 — Optional in-game Sync mode choice; defaults unchanged

Canonical (verbatim):

```json
{"id": "LP-12", "kind": "largerProposal", "title": "Optional in-game Sync mode choice; defaults unchanged", "requiredM7Disposition": "Close full/detail/linked-DPS/refusal disclosure and source-policy controls without new policy/defaults."}
```

- **Adopted/current interpretation:** Optional 'Sync mode...' dialog: draft-only radio choice; only Apply writes through StoreAuthorityOwner; default with no saved choice remains Automatic.
- **Production symbols:** `ui/CommunityRenderer.lua:3723-3727 Sync mode button`; `SyncModeDialog Open/Select/Apply (core/SyncModePolicy.lua:74-96 ApplyChoice)`; `core/Store.lua:295-304 default, :2784 UpdateSettingsV1`
- **Callback chain:** button -> dialog draft -> Apply -> ApplyChoice -> UpdateSettingsV1 -> read back
- **Discriminating assertions:**
  - tests/prototype/ux_sync_mode_choice.lua:161-163 opening writes nothing, draft starts Automatic
  - :181-182 Cancel/X/Escape write nothing
  - :236-238 radio alone changes nothing; Apply changes
  - :276 stale draft refused; :313-314 unwritable storage refuses
  - tests/prototype/ux_sync_mode_transitions.lua T1/T2 Apply sends nothing by itself
- **Negative controls:** read-only storage, stale draft
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_sync_mode_choice` PASS (628), `ux_sync_mode_transitions` PASS (79)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_sync_mode_choice` PASS (628), `ux_sync_mode_transitions` PASS (79)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_sync_mode_choice` PASS (628), `ux_sync_mode_transitions` PASS (79)
- **Spec:** `met-offline`. Defaults unchanged.
- **Standards:** `no-hard-violation-found`. Saved setting written only through the existing Store owner; format compatibility preserved. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Radio buttons, Escape and Apply in the client
- **Row disposition:** offline-supported; native pending

### UX-13 — 79/79 and complete mean four different things

Canonical (verbatim):

```json
{"id": "UX-13", "kind": "originalUXfindingDesiredOutcome", "title": "79/79 and complete mean four different things", "requiredM7Disposition": "Compose qualified units/current-vs-recorded counts without changing eligibility mathematics.", "acceptanceProposals": ["No complete while locked targets remain", "No 79/79 next to saved/assigned without planned"]}
```

- **Adopted/current interpretation:** Distinct count units via UserText.COUNT_UNITS/CountText/RunProgressText; 'complete' requires rolled copies met and no locked target outstanding (Panel inline rule). The generated Saved Build mirror description gives its count in the shared Saved Build unit: 'Assigned Wishlist: X - N/M Wishlist copies in this Saved Build.' (core/CommunityController.lua:1378-1381). An ordinary unchanged-signature import rewrites a description this build would generate differently (:1473-1481); owner-kept and ambiguous legacy text is returned unchanged (:1367-1373). The numbers are CommunityController EchoProgress (:385, used at :1300): Wishlist copies found in this Saved Build, not planned copies and not copies rolled this run. Arithmetic is unchanged.
- **Conflict:** INTERPRETATION RETAINED (kept explicit): the canonical proposal says 'No 79/79 next to saved/assigned without planned'. Labelling the Saved Build count 'planned' would misstate it, so the count is qualified with the existing truthful unit (core/UserText.lua:667 COUNT_UNITS.savedBuild) instead of the literal word. Recorded for coordinator/owner disposition; no mathematics changed to obtain green.
- **Production symbols:** `core/UserText.lua:664-704 COUNT_UNITS (savedBuild :667), CountText, RunProgressText, ProgressComplete`; `ui/Panel.lua:1271,:5116,:5156 complete rule; :4389,:5503 RunProgressText`; `ui/CommunityRenderer.lua:4472 CountText('savedBuild')`; `ui/WishlistRenderer.lua:2717 'Planned rolled copies'`; `core/CommunityController.lua:1367-1383 SavedMirrorDescription (unit wording :1378-1381); :1473-1481 unchanged-signature description refresh; :385 EchoProgress`
- **Callback chain:** model.progress -> Panel.Render -> RunProgressText / complete badge ‖ Saved import FinalizeSavedSlot -> SavedMirrorDescription (core/CommunityController.lua:1367) -> rewrite when the signature or the generated description differs (:1473-1481) -> catalog save -> Build Library detail (ui/CommunityRenderer.lua:2549-2557)
- **Discriminating assertions:**
  - tests/prototype/ux_qualified_counts.lua:85-87 Q1 no 'complete' at 79/79 with a target to lock
  - :96 Q2 '12 / 79 rolled copies this run'
  - :225 Q5 Library card 'Wishlist copies in this Saved Build'; :235-237 Q5 the mirror's generated description gives its count only in that unit
  - :295 Q7 editor footer 'Planned rolled copies: 1/79'; :303 Q7 save notice 'rolled copies planned'
  - tests/prototype/saved_mirror_assigned_description.lua:132-136 D1 real import: name, ratio and unit; :158-161 D2 detail pane; :295-299 D4 an earlier build's unqualified generated text is qualified on an ordinary import, :309 a further import writes nothing; :321 D5 title-only owner edit with a holding witness
  - tests/prototype/saved_mirror_assigned_description.lua:115-117 the unit is pinned to UserText.COUNT_UNITS.savedBuild
- **Negative controls:** Q3 79/79 with nothing to lock is complete; :89 counts change nothing; D3 owner-written description kept (tests/prototype/saved_mirror_assigned_description.lua:189); D6 ambiguous legacy text kept (:337-339); IDs, link, signature, assignment, counts and an unknown field unchanged; unassigned wording kept; no game action, upload, send, request or assignment change (:270-279)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_qualified_counts` PASS (33), `ux_record_scope_terms` PASS (37), `terminology` PASS, `saved_mirror_assigned_description` PASS (76)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_qualified_counts` PASS (33), `ux_record_scope_terms` PASS (37), `terminology` PASS, `saved_mirror_assigned_description` PASS (76)
- **Lane runs (not the final pin):** `ux13-focused-62f16c7` (10/10 passed at `62f16c7`)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_qualified_counts` PASS (32), `ux_record_scope_terms` PASS (37), `terminology` PASS
- **Spec:** `met-offline-adopted-interpretation`. 'No complete while locked targets remain' met (Q1). 'No 79/79 next to saved/assigned without planned' met under the retained interpretation recorded as this row's Conflict: the generated assigned-Saved-Build description and the Library card both qualify the count with the Saved Build unit (Q5, D1, D2, D4, D5). The former candidate gap G-UX13 is resolved in the final source. Its cited fixtures passed in the terminal complete passing runs at c7d2b74 and at 8393f5f.
- **Standards:** `no-hard-violation-found`. Ownership-aware refresh reuses the existing marker/witness gate; the witness bound is 1199 bytes, under the unchanged 2048-byte guard (core/CommunityController.lua:1336-1341). A one-time local rewrite advances the mirror's lastModified through the existing save path; it uploads and sends nothing. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - RESOLVED in final source (was CANDIDATE GAP G-UX13): the generated description no longer shows a bare N/M; lineage 6dcb46c -> 62f16c7, integrated unchanged in f399dd0.
  - INTERPRETATION RETAINED: the canonical literal 'planned' versus the actual Saved Build unit (see Conflict). Labelling these numbers 'planned' would misstate them; recorded for coordinator/owner disposition, not a mathematics change.
  - Compact 'N/M' kept in the description (registered provenance and pipe-control fixtures match it) rather than CountText's 'N / M'.
  - Native: wrapping of the longer description in the detail pane and listing, font/scale, and a real upgrade from SavedVariables written by an earlier build are unverified.
- **Native (#133, pending):** Count wording on HUD, editor and Library at supported scales; Generated Saved Build description wraps legibly in the Library detail and listing; First load after upgrading from an earlier build's SavedVariables rewrites the generated description once locally and sends nothing
- **Row disposition:** offline-supported under a retained interpretation; cited fixtures pass in the complete passing run at 8393f5f; native pending

### LP-13 — Shared qualified count formatter

Canonical (verbatim):

```json
{"id": "LP-13", "kind": "largerProposal", "title": "Shared qualified count formatter", "requiredM7Disposition": "Compose qualified units/current-vs-recorded counts without changing eligibility mathematics."}
```

- **Adopted/current interpretation:** Shared formatter exists in core/UserText.lua but reach is partial.
- **Production symbols:** `core/UserText.lua:675 CountText, :687 RunProgressText, :700 ProgressComplete (no callers)`; `core/CommunityController.lua:1378-1381 description uses the COUNT_UNITS.savedBuild unit in equivalent local wording, not CountText`
- **Callback chain:** callers listed under UX-13
- **Discriminating assertions:**
  - tests/prototype/ux_qualified_counts.lua (formatter outputs through real Panel/Library/editor; Q5 :235-237 description unit)
  - tests/prototype/ux_record_scope_terms.lua:211-226 lint rules for old count phrases
  - tests/prototype/saved_mirror_assigned_description.lua:115-117 the description's unit is pinned to the shared vocabulary
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_qualified_counts` PASS (33), `ux_record_scope_terms` PASS (37), `saved_mirror_assigned_description` PASS (76)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_qualified_counts` PASS (33), `ux_record_scope_terms` PASS (37), `saved_mirror_assigned_description` PASS (76)
- **Lane runs (not the final pin):** `ux13-focused-62f16c7` (10/10 passed at `62f16c7`)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_qualified_counts` PASS (32), `ux_record_scope_terms` PASS (37)
- **Spec:** `partial`. Formatter not used by editor footer (ui/WishlistRenderer.lua:2717,3086,3220) or save notice (core/WishlistController.lua:2512). The Saved Build description (core/CommunityController.lua:1378-1381) now uses the shared unit, but as local wording rather than a formatter call. Reach therefore stays partial.
- **Standards:** `no-hard-violation-found`. Judgement call, Duplicated Code: completion rule inlined at ui/Panel.lua:1271,5116,5156 while UserText.ProgressComplete is unused. Not a documented-standard violation.
- **Gaps and limits:**
  - No test that the shared formatter is used by every count surface.
- **Native:** none beyond offline scope
- **Row disposition:** offline-partial (reach); no native-only criterion beyond UX-13

### UX-14 — DPS and Leaderboard labels overstate scope

Canonical (verbatim):

```json
{"id": "UX-14", "kind": "originalUXfindingDesiredOutcome", "title": "DPS and Leaderboard labels overstate scope", "requiredM7Disposition": "Retain source/provenance/category unknowns; integrate available details and no new-transfer implication.", "acceptanceProposals": ["No 'Global' label without 'shared/known' qualifier"]}
```

- **Adopted/current interpretation:** No user-facing 'Global'; records say 'Best known' / shared-record qualifiers.
- **Production symbols:** `ui/Panel.lua:1603-1628 AddDpsTooltip, :3629,:4330 BEST_KNOWN`; `ui/Leaderboard.lua:156 LeaderboardScope, :1480-1481, :1534`; `core/UserText.lua:707-710`
- **Callback chain:** render/tooltip -> UserText scope words
- **Discriminating assertions:**
  - tests/prototype/ux_record_scope_terms.lua:110 no 'Global'
  - :130 no 'Global Best'
  - :116 'not a complete or server-wide ranking'
  - :184 Leaderboard status
  - lint rules :209-210
- **Negative controls:** :121 no 'Level 0'/owner claim when missing; :123 hover sends nothing
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_record_scope_terms` PASS (37)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_record_scope_terms` PASS (37)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_record_scope_terms` PASS (37)
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Real received record fields native-only.
- **Native (#133, pending):** Leaderboard/DPS labels with real shared records
- **Row disposition:** offline-supported; native pending

### LP-14 — Record detail with available date/duration/level

Canonical (verbatim):

```json
{"id": "LP-14", "kind": "largerProposal", "title": "Record detail with available date/duration/level", "requiredM7Disposition": "Retain source/provenance/category unknowns; integrate available details and no new-transfer implication."}
```

- **Adopted/current interpretation:** Record detail with carried duration/level/date (UserText.RecordDetailParts) on the Panel DPS tooltip and single-category Leaderboard detail.
- **Production symbols:** `core/UserText.lua:722 RecordDetailParts, :746 OwnerLine`; `ui/Panel.lua:1619-1622`; `ui/Leaderboard.lua:1012-1018`; `core/CommunityProjection.lua:114-125 RecordText (Library)`
- **Callback chain:** Leaderboard detail -> RecordDetailParts
- **Discriminating assertions:**
  - tests/prototype/ux_record_scope_terms.lua:118-120 '3:00 fight', 'Level 80', 'Recorded ... (UTC)', 'Owner identity not established'
  - :189 Leaderboard detail duration/level/date
- **Negative controls:** missing values omitted, not shown as 0
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_record_scope_terms` PASS (37)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_record_scope_terms` PASS (37)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_record_scope_terms` PASS (37)
- **Spec:** `partial`. Leaderboard single-category and Panel tooltip met; Build Library loadout record lines and combined Leaderboard rows do not integrate carried details.
- **Standards:** `no-hard-violation-found`. Judgement call, Duplicated Code: RecordText exists in core/CommunityProjection.lua:114 and a fallback copy in ui/CommunityRenderer.lua:2784.
- **Gaps and limits:**
  - SCOPE GAP G-LP14: Build Library 'BEST RECORDS FOR THIS LOADOUT' lines (core/CommunityProjection.lua:114-125; ui/CommunityRenderer.lua:2784-2793) show DPS/holder/your best only - no qualifier, duration, level or date where a row carries them; combined rows (ui/Leaderboard.lua:1004-1007) likewise. Untested.
- **Native (#133, pending):** Record detail with real records in Library and Leaderboard
- **Row disposition:** offline-partial (scope gap for a separate lane); native pending

### UX-15 — Label collisions

Canonical (verbatim):

```json
{"id": "UX-15", "kind": "originalUXfindingDesiredOutcome", "title": "Label collisions", "requiredM7Disposition": "Finish shared vocabulary/deep links and terminology checks; internal IDs unchanged.", "acceptanceProposals": ["Each label maps to one meaning across UI and Help"]}
```

- **Adopted/current interpretation:** Shared vocabulary in UserText.Terms/GLOSSARY shown in Help; 'Mine' scope vs the game's 'My Builds'; 'Options' button; internal ids unchanged.
- **Production symbols:** `core/UserText.lua:755-777 Terms/GLOSSARY`; `ui/Help.lua glossary`
- **Callback chain:** render -> UserText terms
- **Discriminating assertions:**
  - tests/prototype/ux_record_scope_terms.lua:143 'Options'
  - :149 Help 'Best known' definition
  - :380 'Mine' + game's 'My Builds' tooltip
  - :383 internal filterScope=='mine' unchanged
  - :291 real 'My Builds' labels kept
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_record_scope_terms` PASS (37), `terminology` PASS, `terminology_consumers` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_record_scope_terms` PASS (37), `terminology` PASS, `terminology_consumers` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_record_scope_terms` PASS (37), `terminology` PASS, `terminology_consumers` PASS
- **Spec:** `partial`. Met offline only for the labels the fixtures check. The canonical proposal covers every label across UI and Help, and no check establishes one meaning per label across the whole UI and Help (see LP-15 G-LP15). The row is therefore bounded by coverage.
- **Standards:** `no-hard-violation-found`. Internal IDs unchanged. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - COVERAGE GAP: evidence covers only the labels checked by ux_record_scope_terms, terminology and terminology_consumers. One-meaning coverage across the whole UI and Help is absent (same scope as LP-15 G-LP15).
- **Native:** none beyond offline scope
- **Row disposition:** offline-partial (checked labels only; coverage gap shared with LP-15)

### LP-15 — Terminology lint

Canonical (verbatim):

```json
{"id": "LP-15", "kind": "largerProposal", "title": "Terminology lint", "requiredM7Disposition": "Finish shared vocabulary/deep links and terminology checks; internal IDs unchanged."}
```

- **Adopted/current interpretation:** Terminology lint is a fixed phrase list (18 rules) over 12 player-facing files plus one file-scoped rule for core/WishlistController.lua.
- **Production symbols:** `tests/prototype/ux_record_scope_terms.lua:202-232 UI_FILES/RULES/SCOPED_FILES`
- **Callback chain:** R5 scenario reads files and searches phrases
- **Discriminating assertions:**
  - tests/prototype/ux_record_scope_terms.lua R5 (:202-280)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_record_scope_terms` PASS (37)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_record_scope_terms` PASS (37)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_record_scope_terms` PASS (37)
- **Spec:** `partial`. A lint exists; it does not check one-meaning-per-label and excludes core/UserText.lua, core/CommunityController.lua, core/Main.lua, ui/GuidedSetup.lua, ui/OrbHistory.lua, ui/SettingsWindow.lua and data/LocalizationPacks.lua.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - COVERAGE GAP G-LP15: lint scope bounded; e.g. core/CommunityController.lua is outside it (tests/prototype/ux_record_scope_terms.lua:202-207 UI_FILES). The UX-13 description string (core/CommunityController.lua:1379) is guarded by fixture assertions, not by the lint.
- **Native:** none beyond offline scope
- **Row disposition:** offline-partial (coverage)

### UX-16 — Orb wording: usage x3, dense blocks, reload advice conflict, history lost on reload

Canonical (verbatim):

```json
{"id": "UX-16", "kind": "originalUXfindingDesiredOutcome", "title": "Orb wording: usage x3, dense blocks, reload advice conflict, history lost on reload", "requiredM7Disposition": "Finish restored PAUSED/recovery/current usage and truthful Continue/reload/history copy.", "acceptanceProposals": ["Same usage words on all three surfaces", "Help and Orb reload advice consistent"]}
```

- **Adopted/current interpretation:** Orb usage uses the shared words 'Orbs used ... approved' with 'pending ... not confirmed yet'; restored PAUSED headline, recovery headlines and truthful Continue/reload/history copy.
- **Production symbols:** `ui/OrbPanel.lua:447-452 window usage, :1399-1407 strip, :1584-1609 mini, :242-258 recovery headlines, :1239-1240 Continue history note`; `ui/Help.lua:125-129 Orbs page`; `ui/OrbHistory.lua:86-89`
- **Callback chain:** Refresh -> usage/headline text from OrbRuntime.Status
- **Discriminating assertions:**
  - tests/prototype/orb_recovery_layers.lua:316 'Orbs used: 0 / 3 approved; pending: 1 Orb requested, not confirmed yet'
  - :322 strip; :324 mini 'Orbs used: 0 of 3 approved'
  - :387-389 Help/Orb reload advice consistency (source text, one direction)
  - tests/prototype/orb_recovery_vocabulary.lua:51,:96-103
  - tests/prototype/batch_orb_restored_wording.lua:68-82
- **Negative controls:** no 'confirmed spend' wording (batch_orb_spend_wording)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_recovery_layers` PASS (124), `orb_recovery_vocabulary` PASS (50), `batch_orb_restored_wording` PASS (23), `orb_continue_affordance` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_recovery_layers` PASS (124), `orb_recovery_vocabulary` PASS (50), `batch_orb_restored_wording` PASS (23), `orb_continue_affordance` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_recovery_layers` PASS (124), `orb_recovery_vocabulary` PASS (50), `batch_orb_restored_wording` PASS (23), `orb_continue_affordance` PASS (7)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - The main-panel strip can be hidden for a settled, ended run until the next run (#167; session-only, presentation only). The usage-word code and assertions cited are unchanged; this row stays partial.
- **Spec:** `partial`. Same vocabulary, not literally identical strings: window/strip use '/', mini 'of', Play line 'Used X of Y approved'; pending phrasing differs per surface and is pinned by tests. Reload-advice check is a one-way source-text grep; runtime reload hints (core/OrbRuntime.lua:2361,2578,3401) not compared against Help.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - INTERPRETATION: 'Same usage words on all three surfaces' - owner decision whether shared vocabulary with differing separators suffices.
- **Native (#133, pending):** Usage and reload/history copy on all Orb surfaces after a real reload
- **Row disposition:** offline-partial (interpretation); native pending

### LP-16 — Unified Orb status vocabulary

Canonical (verbatim):

```json
{"id": "LP-16", "kind": "largerProposal", "title": "Unified Orb status vocabulary", "requiredM7Disposition": "Finish restored PAUSED/recovery/current usage and truthful Continue/reload/history copy."}
```

- **Adopted/current interpretation:** Unified recovery vocabulary: headline, 'What you can do', 'Details:'; continue/recovery phase maps; history 'Now: Paused / last recorded'.
- **Production symbols:** `ui/OrbPanel.lua:183-189 phase maps/phaseText, :242-258 UI.RECOVERY_HEADLINES/recoveryActions`
- **Callback chain:** Refresh -> recovery headline/action lines
- **Discriminating assertions:**
  - tests/prototype/orb_recovery_vocabulary.lua:51-53 headline then action then Details
  - :70,:80 Continue/no-Continue headlines
  - :130,:138-139 history header/report wording
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_recovery_vocabulary` PASS (50), `orb_recovery_layers` PASS (124), `orb_continue_affordance` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_recovery_vocabulary` PASS (50), `orb_recovery_layers` PASS (124), `orb_continue_affordance` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_recovery_vocabulary` PASS (50), `orb_recovery_layers` PASS (124), `orb_continue_affordance` PASS (7)
- **Spec:** `met-offline`. orb_continue_affordance uses a stubbed ContinueView (labels only).
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Recovery vocabulary in the client after a real reload
- **Row disposition:** offline-supported; native pending

### UX-17 — Help and Welcome structure

Canonical (verbatim):

```json
{"id": "UX-17", "kind": "originalUXfindingDesiredOutcome", "title": "Help and Welcome structure", "requiredM7Disposition": "Finish contextual safe Help/direct links and loading access across all journey states.", "acceptanceProposals": ["Any Help page reachable in one click", "Welcome shows setup steps first"]}
```

- **Adopted/current interpretation:** Help is the guided coach at its current step; the long manual is the separately named Reference with one direct button per page (7). Page 1 and the coach Welcome lead with setup.
- **Production symbols:** `ui/Help.lua:16 'start' page text, :421 H.Show, :505 H.OpenGuide, :531 H.OpenHelp, :539 H.OpenReference`; `ui/Panel.lua:3156-3164 Options menu Help/Reference`; `core/Main.lua:1207 /nexus reference, :1496 /nexus guide`
- **Callback chain:** Help button -> Help.OpenHelp -> OpenGuide -> GuidedSetupUI.Show; Reference -> Help.Show(page)
- **Discriminating assertions:**
  - tests/prototype/ux_help_navigation.lua:92 one direct button per page (7)
  - :96-99 direct page and page 1 'Start here'
  - :103 setup row offers Setup / Welcome, Assign Wishlist..., Wishlist Editor
  - tests/prototype/setup_help_entry_points.lua (105 checks) setup Help entries open the coach; Reference separately named
- **Negative controls:** loading refusals stated (H1 :106-114)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_help_navigation` PASS (32), `setup_help_entry_points` PASS (105), `help` PASS, `help_action_first` PASS (6493)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_help_navigation` PASS (32), `setup_help_entry_points` PASS (105), `help` PASS, `help_action_first` PASS (6052)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_help_navigation` PASS (32), `setup_help_entry_points` PASS (105), `help` PASS (406), `help_action_first` PASS (6052)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - Help gained an eighth Reference page, Questions (FAQ), with gold question lines (#169), and Options entries 'Auto explained (full details)' and 'Questions (FAQ)'. help, help_action_first (checks 6052 -> 6493) and ux_help_navigation H1 (:96-99) now expect eight pages; the ordinary-Help-to-coach and Reference routes cited are unchanged, only shifted (ui/Help.lua:421, :505, :531, :539).
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - 163008 native report (Records Help opened the manual) is addressed in source at this pin (ui/Leaderboard.lua:1254 OpenHelp, :1255 OpenReference); native re-observation of every entry pending.
- **Native (#133, pending):** Every Help entry (Records, Library, Plan, Journal, Orbs, Options, /nexus help) opens the coach; Reference opens its page; one-click page access
- **Row disposition:** offline-supported; native pending

### LP-17 — Restructured Help and contextual deep links

Canonical (verbatim):

```json
{"id": "LP-17", "kind": "largerProposal", "title": "Restructured Help and contextual deep links", "requiredM7Disposition": "Finish contextual safe Help/direct links and loading access across all journey states."}
```

- **Adopted/current interpretation:** Contextual Help and Reference per window family (Build Library, Leaderboard, Wishlist Editor, Orb window, Journal Build Progress) and Help's action row to the checklist.
- **Production symbols:** `ui/CommunityRenderer.lua:3486,:3495`; `ui/Leaderboard.lua:1254-1255`; `ui/OrbPanel.lua:722,:724`; `ui/JournalTab.lua:626,:643`; `ui/WishlistRenderer.lua:1444,:1451`; `ui/Help.lua:492 H.OpenChecklist`
- **Callback chain:** window Help -> Help.OpenHelp(page, leave) -> coach; Reference -> Help.OpenReference(page, leave)
- **Discriminating assertions:**
  - tests/prototype/ux_context_help_access.lua X1-X6 (:65-285) each family's Help opens the coach and Reference its page; nothing sent/assigned/saved/spent
  - X5 (:198) Help text names the routes
- **Negative controls:** refused coach (warning open) keeps the calling window and draft (ui/Help.lua:519-537)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_context_help_access` PASS (146), `setup_help_entry_points` PASS (105)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_context_help_access` PASS (146), `setup_help_entry_points` PASS (105)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_context_help_access` PASS (146), `setup_help_entry_points` PASS (105)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - Help page and FAQ additions as UX-17; the contextual Help/Reference routes cited are unchanged lines.
- **Spec:** `met-offline`. Distinct from UX-17: per-window deep links.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Full Reference back stack natively unobserved (remaining scope of the bounded native check at this pin).
- **Native (#133, pending):** Each window family's Help/Reference in the client; Reference back stack
- **Row disposition:** offline-supported; native pending

### UX-18 — Practical accessibility minimums

Canonical (verbatim):

```json
{"id": "UX-18", "kind": "originalUXfindingDesiredOutcome", "title": "Practical accessibility minimums", "requiredM7Disposition": "Complete offline window-family accessibility/visible-reason composition; list exact M8 native gaps.", "acceptanceProposals": ["Blocked reason visible without hover"]}
```

- **Adopted/current interpretation:** Blocked/refused reasons shown in-window (checklist f.notice, Help note, coach notes) without hover; Escape closes each family; long text wraps or has a full-text hover in the modelled fonts.
- **Production symbols:** `ui/QuickStart.lua:602-604 notice, :624-635 route(), :495-540 LayoutChecklist`; `ui/QuickStart.lua:420-442 Escape child`; `ui/Help.lua:437 Refuse`
- **Callback chain:** refused route -> reason returned -> f.notice:SetText -> LayoutChecklist
- **Discriminating assertions:**
  - tests/prototype/ux_context_help_access.lua:346 a refused route shows its reason in the window
  - :319,:332 reasons readable under font models with a long name
  - X8 (:353) Escape closes every family
  - tests/prototype/ux_setup_checklist.lua:271-274 refused coach reason in the checklist; K7-K10 Escape/hide
- **Negative controls:** passive ancestor hide records nothing (K9/K10)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_context_help_access` PASS (146), `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_context_help_access` PASS (146), `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_context_help_access` PASS (146), `ux_setup_checklist` PASS (192), `guided_setup_flow` PASS (2878)
- **Spec:** `met-offline`.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Geometry is the conservative harness model, not native glyphs/scale/hit testing.
- **Native (#133, pending):** Blocked reason visible without hover at 100%/125% text and changed UI scale; Escape order; keyboard focus
- **Row disposition:** offline-supported; native pending

### LP-18 — Accessibility pass per window family

Canonical (verbatim):

```json
{"id": "LP-18", "kind": "largerProposal", "title": "Accessibility pass per window family", "requiredM7Disposition": "Complete offline window-family accessibility/visible-reason composition; list exact M8 native gaps."}
```

- **Adopted/current interpretation:** Offline per-family accessibility composition (wrap/hover, Escape, in-window reasons, coach 420/640 px and 125% text layout). Exact native gaps listed in nativeCriterion.
- **Production symbols:** `ui/LayoutMetrics.lua WrapHeight/FullTextTooltip/FitToScreen/FitButtonWidth`; `ui/GuidedSetup.lua bounded window (Bound, ScreenCap)`
- **Callback chain:** layout passes per window family
- **Discriminating assertions:**
  - tests/prototype/ux_context_help_access.lua X7/X8
  - tests/prototype/guided_setup_flow.lua F5,F6,F8,F11,F20 (420 px, 125%, long UTF-8, footer, 640 px)
  - tests/prototype/ux_sync_status_fit.lua (7945 checks) Library fit/scroll
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_context_help_access` PASS (146), `guided_setup_flow` PASS (2878), `ux_sync_status_fit` PASS (7945)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_context_help_access` PASS (146), `guided_setup_flow` PASS (2878), `ux_sync_status_fit` PASS (7945)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_context_help_access` PASS (146), `guided_setup_flow` PASS (2878), `ux_sync_status_fit` PASS (7945)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ui/LayoutMetrics.lua FitToScreen gained an optional ceiling for the main panel size option (50%-150%, #165/#170); the other cited helpers are unchanged.
- **Spec:** `met-offline`. Offline composition complete for the families covered; native gaps enumerated below as required.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** 125% text and changed UI scale; edge/clamping and all menu entry families/levels; keyboard focus and Escape dispatch order; native font measurement vs the 7 px / conservative models; coach wide vs compact presentation on real screen widths; full Reference back stack; My Builds resize/reopen
- **Row disposition:** offline-supported; native gaps enumerated; native pending

### J1 — Fresh import/no Saved Build

Canonical (verbatim):

```json
{"id": "J1", "kind": "endToEndJourney", "title": "Fresh import/no Saved Build", "originalCompletionContract": "Import remains draft-only until explicit Create; captured first-run target visible; no-choice ready state completes setup Auto OFF with zero resource activity.", "ownerQueueContract": "Draft import/Create/named first-run destination/result; truthful invalid/cancel/no-durable/no-choice AutoOFF zero activity.", "optional": false, "covers": ["UX-01", "UX-02", "UX-03", "UX-04", "UX-06", "UX-13", "UX-17", "UX-18"]}
```

- **Adopted/current interpretation:** Fresh profile: invalid code refused; import opens an editor draft only; Create confirmation names the first-run target; Cancel uploads nothing; explicit Create uploads once and makes one first-run writer call; checklist reads 3 of 3 with Auto OFF and no Echo choice; later refreshes do nothing. Coach import path: Check code (read only) then 'Open it as a draft' -> WishlistEditor.ImportEBH1String; only a later save receipt completes the Wishlist step.
- **Production symbols:** `ui/WishlistEditor.lua ImportEBH1String / CheckImportCode`; `ui/GuidedSetup.lua:2031 U.CheckImport, :2049 U.RouteImport, :1909 U.RouteEnded`; `core/GuidedSetup.lua:431 G.AwaitSave, :437 G.CancelAwaitSave, :623 G.Note('draft'/'save')`; `core/GameAdapter.lua SetFirstLoadoutWishlistIdentity`; `ui/QuickStart.lua:542 RefreshChecklist`
- **Callback chain:** checklist Wishlist Editor -> Help.OpenEditor -> NEXUS_IMPORT_WISHLIST -> naming dialog -> editor draft (no write) -> Create -> WISHLISTREALIZER_CREATE_WISHLIST (Cancel: nothing) -> accept -> upload + first-run identity write -> server mirror poll -> A.Wishlist 'First-run wishlist target' -> Panel.SetupFacts -> checklist ‖ coach: AwaitSave -> import route -> draft receipt (s.draft) -> save receipt SAVED kind -> s.wishlist source='saved' -> AssignStatus origin 'save'
- **Discriminating assertions:**
  - tests/prototype/ux_setup_checklist.lua J1 (:1070-1259): :1141-1143 no Wishlist -> not done, no guessed destination; :1148 invalid code refused visibly, no draft/dialog/upload/write; :1170-1172 import is a draft only; :1177 imported draft completes nothing; :1185 Create confirmation names the first-run target; :1189 Cancel uploads/assigns nothing; :1200 one upload and one first-run writer call; :1204 no other action or spend, Auto OFF; :1205 result names the first-run target; :1227 production readback; :1240-1242 checklist destination/Wishlist done, 3 of 3; :1247 'Auto: OFF'; :1255 later passive refreshes inert, no Echo choice
  - tests/prototype/guided_setup_readback.lua R8 (:219-229) import is draft; Create verified by save receipt; R8b partial and R8c unconfirmed not done
  - tests/prototype/guided_setup_flow.lua F13 (:905) Check code in place, draft a separate action
  - tests/prototype/guided_first_entry.lua (195 checks) healthy first use is the coach
- **Negative controls:** invalid code; Create Cancel; partial upload (R8b); unconfirmed upload (R8c); editor closed without save (U.RouteEnded/CancelAwaitSave)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_setup_checklist` PASS (192), `guided_setup_readback` PASS (135), `guided_setup_flow` PASS (2878), `guided_first_entry` PASS (195), `quickstart_seen_guard` PASS (76)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_setup_checklist` PASS (192), `guided_setup_readback` PASS (135), `guided_setup_flow` PASS (2878), `guided_first_entry` PASS (195), `quickstart_seen_guard` PASS (76)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_setup_checklist` PASS (192), `guided_setup_readback` PASS (135), `guided_setup_flow` PASS (2878), `guided_first_entry` PASS (195), `quickstart_seen_guard` PASS (76)
- **Spec:** `met-offline`. Original completion and owner-queue contracts traced through real handlers; host mirror is synthetic (fixture step 6).
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - Covered rows carry their own gaps (UX-02 candidate gaps do not arise on the J1 no-choice path).
- **Native (#133, pending):** Fresh character: import, Create, first-run label, checklist 3 of 3 with Auto OFF and zero resource activity in the client
- **Row disposition:** offline-supported; native pending

### J2 — Existing Saved Build/unassigned plan

Canonical (verbatim):

```json
{"id": "J2", "kind": "endToEndJourney", "title": "Existing Saved Build/unassigned plan", "originalCompletionContract": "Named valid association accepted/read back; unassigned and partial states persist; Assign now does not re-upload; empty Saved Build refusal remains.", "ownerQueueContract": "Existing Saved Build/unassigned plan; named picker/readback/unassigned result/Assign without upload; distinct AutoON consent.", "optional": false, "covers": ["UX-03", "UX-04", "UX-05", "UX-06", "UX-13"]}
```

- **Adopted/current interpretation:** Existing unassigned Saved Build: checklist names destination and 'None assigned'; Assign Wishlist... opens chooser titled with it; cancel assigns nothing; one choice makes exactly one association write and no upload; production and checklist readback; destination change while chooser is open truthful; a delayed captured callback writes only the captured Saved Build; empty Saved Build refused; Auto-ON consent distinct.
- **Production symbols:** `ui/JournalTab.lua:1428 AssociateWishlistOnly, :154 AssignWithConsent`; `core/GameAdapter.lua:3236 SetLoadoutWishlist (empty-slot refusal :3247-3249)`; `ui/Panel.lua:1081 SetupFacts`; `ui/QuickStart.lua:636 Assign Wishlist...`
- **Callback chain:** checklist Assign -> Help.OpenAssignment -> Panel.OpenAssignment -> JournalTab.OpenBuilds(true) -> row OnClick -> AssignWithConsent -> SetLoadoutWishlist(captured active) -> RefreshAssociations/Panel.Refresh -> chat line -> checklist refresh
- **Discriminating assertions:**
  - tests/prototype/ux_setup_checklist.lua J2 (:591-939): tests/prototype/ux_setup_checklist.lua:634-637 unassigned not complete; tests/prototype/ux_setup_checklist.lua:645 chooser 'Assign to: Fire PvE'; tests/prototype/ux_setup_checklist.lua:651-658 cancel nothing; tests/prototype/ux_setup_checklist.lua:673-678 one write, no upload, named line; tests/prototype/ux_setup_checklist.lua:687-706 production/checklist readback, Auto OFF; tests/prototype/ux_setup_checklist.lua:719-722 refreshes inert; tests/prototype/ux_setup_checklist.lua:734-778 destination change truthful
  - J2b (:940) delayed captured OnClick writes only Saved Build 2 (synthetic queued-callback boundary)
  - J2c (:986) oracle rejects skipped delivery and misrouted write (fixture discriminator, not product evidence)
  - tests/prototype/ux_help_navigation.lua:203-210 empty Saved Build refusal
  - tests/prototype/ux_save_assignment_result.lua:356,:426 Assign now no upload; :397 partial persists
- **Negative controls:** cancel; destination change; delayed callback; empty Saved Build; Auto-ON consent (UX-05)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_setup_checklist` PASS (192), `ux_help_navigation` PASS (32), `ux_save_assignment_result` PASS (155), `ux_auto_assignment_consent` PASS (57), `guided_setup_readback` PASS (135)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_setup_checklist` PASS (192), `ux_help_navigation` PASS (32), `ux_save_assignment_result` PASS (155), `ux_auto_assignment_consent` PASS (57), `guided_setup_readback` PASS (135)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_setup_checklist` PASS (192), `ux_help_navigation` PASS (32), `ux_save_assignment_result` PASS (155), `ux_auto_assignment_consent` PASS (57), `guided_setup_readback` PASS (135)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - ux_help_navigation and ux_setup_checklist changed only their Reference page-count expectations (7 -> 8); the cited J2/J2b/J2c scenarios are unchanged lines.
- **Spec:** `met-offline`. J2b calls the captured production OnClick directly (no native visible-click or timing claim).
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Native (#133, pending):** Existing Saved Build assignment through the real Journal chooser; delayed confirmation timing
- **Row disposition:** offline-supported; native pending

### J3 — Multiple characters/Saved Builds

Canonical (verbatim):

```json
{"id": "J3", "kind": "endToEndJourney", "title": "Multiple characters/Saved Builds", "originalCompletionContract": "Captured inactive owner/destination unchanged by active context, restored association, recycled slot or callback; wrong-owner writes refused.", "ownerQueueContract": "Inactive/captured destination across character/loadout/slot/token changes; stale/reused-slot refusal and owner/unavailable distinction.", "optional": false, "covers": ["UX-03", "UX-04", "UX-05", "UX-13", "UX-15"]}
```

- **Adopted/current interpretation:** Captured destination/owner across character/loadout/slot/token changes: assignment-action tokens per destination and owner epoch; captured editors not redirected; reused Wishlist server slots refused; owner change refuses writes.
- **Production symbols:** `core/GameAdapter.lua:2831-2899 AssignmentActionToken/Snapshot epoch`; `core/GameAdapter.lua:3001 SelectedSavedBuild`; `core/Store.lua:2427 CurrentOwnerKey`; `WishlistRoles.MayWrite in writers (core/GameAdapter.lua:3169,3212,3304)`; `ui/JournalTab.lua:154 AssignWithConsent owner re-check`
- **Callback chain:** capture at open -> token/epoch compare at write -> refuse on change
- **Discriminating assertions:**
  - tests/prototype/wishlist_assignment_action_token.lua (132 checks) T6 owner/DB change makes bound editor stale; T10a newer choice kept
  - tests/prototype/ux_destination_context.lua:192
  - tests/prototype/ux_auto_assignment_consent.lua:368 captured slot, :392 owner change refuses
  - tests/prototype/ux_captured_destination_labels.lua:563 reused Wishlist server slot
  - tests/prototype/stale_server_slot_save.lua (101 checks)
  - tests/prototype/assignment_identity.lua reordered/reused slots
  - tests/prototype/saved_build_wishlist_destination_guards.lua deleted Saved Build
- **Negative controls:** owner change, DB change, reused Wishlist slot, deleted/emptied Saved Build
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `wishlist_assignment_action_token` PASS (132), `assignment_identity` PASS, `stale_server_slot_save` PASS, `saved_build_wishlist_destination_guards` PASS (23), `ux_captured_destination_labels` PASS (452), `ux_destination_context` PASS (54), `ux_auto_assignment_consent` PASS (57), `wishlist_upload_context` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `wishlist_assignment_action_token` PASS (132), `assignment_identity` PASS, `stale_server_slot_save` PASS, `saved_build_wishlist_destination_guards` PASS (23), `ux_captured_destination_labels` PASS (452), `ux_destination_context` PASS (54), `ux_auto_assignment_consent` PASS (57), `wishlist_upload_context` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `wishlist_assignment_action_token` PASS (132), `assignment_identity` PASS, `stale_server_slot_save` PASS, `saved_build_wishlist_destination_guards` PASS (23), `ux_captured_destination_labels` PASS (452), `ux_destination_context` PASS (54), `ux_auto_assignment_consent` PASS (57), `wishlist_upload_context` PASS
- **Spec:** `partial`. Owner/Wishlist-slot/token cases met offline; one uncovered edge depends on what 'recycled slot' covers.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - UNRESOLVED EDGE G-J3 (source-only): Saved Build slot contents replaced in the game between chooser click and a delayed Auto-ON accept. AssignWithConsent re-checks owner only (ui/JournalTab.lua:154-176); A.SetLoadoutWishlist checks the slot is populated (core/GameAdapter.lua:3247), not that it is the same Saved Build; the chat line names the captured loadoutName. Associations are keyed by slot index by design, so this may be intended; no test replaces a populated Saved Build before a delayed accept. Owner decision whether 'recycled slot' includes Saved Build slots.
  - Owner change cannot occur within one native session (character change reloads UI); offline tests replace CurrentOwnerKey.
- **Native (#133, pending):** Multiple characters/Saved Builds: captured destination survives switching; wrong-owner writes refused after relog
- **Row disposition:** offline-partial (unresolved edge); native pending

### J4 — Manual recommendations then optional Automation

Canonical (verbatim):

```json
{"id": "J4", "kind": "endToEndJourney", "title": "Manual recommendations then optional Automation", "originalCompletionContract": "Named selection or no-choice ready state; current scope disclosed; no Automation enablement without explicit consent; hold reasons visible.", "ownerQueueContract": "Manual recommendation or ready no-choice; existing action disclosure; opening Setup/Help/settings cannot start Auto; visible reason and truthful OFF.", "optional": false, "covers": ["UX-02", "UX-05", "UX-09", "UX-10", "UX-17", "UX-18"]}
```

- **Adopted/current interpretation:** Manual recommendation (a named single Take, or the named Freeze target of the adaptive two-or-more-Needed decision, identified with its own Freeze mark as in UX-02) or no-choice ready state ('Roll status' / 'No Echo choice is showing.'); existing permission disclosure in tooltip, warning and Help; Auto turns ON only through the Auto button, /nexus auto or the level-1 tome popup Yes, each via OverwriteWarning.RequestAuto and its explicit Yes (or the player's own earlier saved opt-out); Setup/Help/Settings/guided coach call no Auto setter; hold and refusal reasons visible; OFF read truthfully, including the Orb-guidance heading.
- **Production symbols:** `ui/Panel.lua:2626-2635 Auto button`; `core/AutomationRuntime.lua:4625 ToggleAuto, :4679-4700 RequestAuto path, :4715-4748 accept/CommitToggle`; `ui/OverwriteWarning.lua:327 RequestAuto, :120 Finish`; `core/Main.lua:889 /nexus auto`; `core/GuidedSetup.lua:787 G.AutoState, :794 G.KeepAuto (no setter)`; `ui/GuidedSetup.lua:1020-1058 VIEW.auto (Keep/Review only)`; `ui/Panel.lua:5286-5295 Orb-guidance heading (Auto OFF 'You choose' :5291-5292)`; `ui/Readout.lua:98 FreezeCard; core/AutomationRuntime.lua:3303-3304 freeze display flag`
- **Callback chain:** Auto click -> ToggleAuto -> Orb block refusal or RequestAuto -> warning Yes -> accept re-checks Orb block and OFF -> CommitToggle -> Panel.SetAuto ‖ coach Auto step Keep -> G.KeepAuto records mode read now -> G.Next; Review -> Panel.Show only
- **Discriminating assertions:**
  - tests/prototype/ux_manual_recommendation.lua:123-129 Auto OFF one named Take target, nothing performed; R4 :189-191 no-choice ready state
  - tests/prototype/ux_manual_recommendation.lua:475-499 R7 Auto OFF with Orb guidance: 'you choose', never Active, reason and Open Orbs remain; :512-548 R8 and :628-654 R10 the Freeze target named and identified, no Take marker, no engine name, nothing performed
  - tests/prototype/orb_guidance_navigation.lua:218-223 real HUD unknown Orb state with Auto OFF: truthful heading, Auto stays OFF
  - tests/prototype/ux_automation_scope.lua P17 :608 passive reads change nothing; :618 No keeps OFF; :622 next board still manual; :630 only Yes turns ON, no suppression saved; :640 action targets the board shown at acceptance
  - tests/prototype/overwrite_auto_gate.lua every enable waits for Yes; disable cancels a pending Yes; Orb block re-checked at approval
  - tests/prototype/guided_setup_flow.lua:888 Auto step toggles nothing; :283 Auto kept ON through the guide
  - tests/prototype/full_ui_settings.lua:28-29 settings navigation leaves saved bytes unchanged
- **Negative controls:** warning No/X/Escape/OnHide; first-launch Continue grants no Auto; refused click (UX-09)
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `ux_manual_recommendation` PASS (124), `ux_automation_scope` PASS (97), `overwrite_auto_gate` PASS, `guided_setup_flow` PASS (2878), `full_ui_settings` PASS, `ux_status_composition` PASS (81), `orb_guidance_navigation` PASS (70)
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `ux_manual_recommendation` PASS (124), `ux_automation_scope` PASS (97), `overwrite_auto_gate` PASS, `guided_setup_flow` PASS (2878), `full_ui_settings` PASS, `ux_status_composition` PASS (81), `orb_guidance_navigation` PASS (70)
- **Lane runs (not the final pin):** `ux02-focused-82b7695` (23/23 passed at `82b7695`)
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `ux_manual_recommendation` PASS (68), `ux_automation_scope` PASS (97), `overwrite_auto_gate` PASS, `guided_setup_flow` PASS (2878), `full_ui_settings` PASS, `ux_status_composition` PASS (81)
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - The accept callback (core/AutomationRuntime.lua:4715-4748) also refuses while the session pause holds, and ToggleAuto refuses before RequestAuto while paused; 'only Yes turns ON' is unchanged. P17's passive read (ux_automation_scope.lua:608) now also opens and closes the Auto explained page through the real Options row; its no-change guard still holds.
- **Spec:** `met-offline-adopted-interpretation`. The journey's recorded partial basis was only the two candidate gaps inherited from UX-02 (truthful OFF under Orb guidance; named selection for two distinct Needed offers). Both now have discriminating offline assertions through the real TOC path (R7, R8, R10, orb_guidance_navigation), and the other traced paths are unchanged: no-choice ready state, explicit Auto consent, and Setup/Help/Settings/coach starting no Auto. Met under the same adopted reading of 'named selection' as UX-02 (a Freeze target is named and marked as a Freeze, not as a Take). Its cited fixtures passed in the terminal complete passing runs at c7d2b74 and at 8393f5f.
- **Standards:** `no-hard-violation-found`. Harness acknowledges warnings by default (tests/prototype/harness.lua:314); only P15, P17 and overwrite_auto_gate exercise the real Yes/No dialog - recorded as an evidence limit. The UX-02 Freeze flag is display-only and grants nothing. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - RESOLVED in final source: inherited UX-02 G-UX02-b (Auto OFF Orb-guidance heading) and G-UX02-a (two distinct Needed offers named and identified); see UX-02.
  - Evidence limit retained: the harness acknowledges warnings by default (tests/prototype/harness.lua:314); only P15, P17 and overwrite_auto_gate exercise the real Yes/No dialog.
  - Native client behaviour, font/scale fit and the separate first-time-player screenshot review are pending.
- **Native (#133, pending):** Manual recommendation, Auto warning Yes/No, and opening Setup/Help/Settings without starting Auto in the client
- **Row disposition:** offline-supported under the UX-02 adopted reading; cited fixtures pass in the complete passing run at 8393f5f; native pending

### J5 — Optional Orb pause/target change/recovery

Canonical (verbatim):

```json
{"id": "J5", "kind": "endToEndJourney", "title": "Optional Orb pause/target change/recovery", "originalCompletionContract": "Settlement/current target/original operation and remaining limit clear; deliberate Continue/Resume; no repeat/refund; resource-native proof separately bounded.", "ownerQueueContract": "Optional Orb target/review/pause/recovery; existing settlement/context/limit/token/Continue guards; no repeat/refund implication.", "optional": true, "covers": ["UX-07", "UX-08", "UX-09", "UX-16", "UX-18"]}
```

- **Adopted/current interpretation:** Optional journey; its safety boundaries are retained. Target change while paused -> named, reviewed, deliberate Resume with context/owner/limit/token guards; interrupted run -> recovery Check -> token-bound Continue that archives and stops, sends nothing and never repeats or refunds; opening Orb/Help/guide spends nothing.
- **Production symbols:** `core/OrbRuntime.lua:3383-3420 M.Resume guards`; `core/OrbRuntime.lua:2364 ContinueBegin, :2039 RC.eligible, :2114 RC.check, :2689 ContinueConfirm`; `ui/OrbPanel.lua:684 frame.cont, :1261-1289 Check/Continue/close cancel`
- **Callback chain:** UX-07 chain for target change ‖ Continue -> ShowContinue -> Check -> ContinueBegin -> RC.advance -> token -> Continue click -> ContinueConfirm(token) -> RC.check -> RC.archive -> terminal STOPPED, approval=nil
- **Discriminating assertions:**
  - tests/prototype/orbs_target_changes.lua original settlement and Resume preserve one finite budget
  - tests/prototype/orb_recovery_continue.lua:113-122 spent/limit unchanged, no spend/choice, old run cannot Resume, repeated confirm 'already'
  - :149-159 stale/forged tokens refused
  - tests/prototype/orb_recovery_refusals.lua (477 checks) stale/omitted/rejected/late/changed/failed inputs never release the blocker
  - tests/prototype/orb_bounded_recovery.lua (534 checks) UI exit sends no mutation
  - tests/prototype/orb_guidance_passive_open.lua:132,:161 opening changes nothing during run/recovery
- **Negative controls:** context/level change, pending assignment change, stale token, closed window kills token, slot change withdraws confirm
- **Execution at the final pin (`8393f5f`, complete CI PASSED):** `orb_target_review` PASS (152), `orbs_target_changes` PASS, `orb_recovery_continue` PASS (180), `orb_recovery_refusals` PASS (477), `orb_bounded_recovery` PASS (534), `orb_guidance_passive_open` PASS (25), `orb_continue_affordance` PASS, `orb_mini_panel` PASS
- **Prior pin execution (`c7d2b74`, complete CI PASSED; historical):** `orb_target_review` PASS (152), `orbs_target_changes` PASS, `orb_recovery_continue` PASS (180), `orb_recovery_refusals` PASS (477), `orb_bounded_recovery` PASS (534), `orb_guidance_passive_open` PASS (25), `orb_continue_affordance` PASS, `orb_mini_panel` PASS
- **Historical execution (`9bfb2bb`, focused-61; not proof of changed code):** `orb_target_review` PASS (152), `orbs_target_changes` PASS, `orb_recovery_continue` PASS (180), `orb_recovery_refusals` PASS (477), `orb_bounded_recovery` PASS (534), `orb_guidance_passive_open` PASS (25), `orb_continue_affordance` PASS (7), `orb_mini_panel` PASS
- **Source changes since c7d2b74 (re-read at 8393f5f):**
  - M.Resume (core/OrbRuntime.lua:3383-3420) gained a session-pause refusal, and Continue keeps the ordinary cadence for a newly approved running run (#172). The cited recovery guards are unchanged, only shifted; the optional journey's safety boundaries are retained.
- **Spec:** `met-offline`. Resource-native proof separately bounded as the canonical contract states.
- **Standards:** `no-hard-violation-found`. Checked against AGENTS.md/CONTRIBUTING.md (Lua 5.1, Nexus identity, NexusDB/WishlistRealizerDB compatibility, no live claim from offline checks) and AI_POLICY.md; Fowler smells are judgement calls only.
- **Gaps and limits:**
  - No fixture found reaching the PAUSED Resume refusal for a reached limit with uncertain>0 (core/OrbRuntime.lua:3419).
  - Lost-approval wording has negative checks only.
- **Native (#133, pending):** Real Orb spend/settlement, server responses and reload; no repeat/refund in the client (resource-native, separately authorized)
- **Row disposition:** offline-supported (optional journey, safety boundaries retained); native pending

## Remaining obligations

- Codex's independent Spec and Standards review of this `8393f5f` rebinding. A docs-only integration must be shown to preserve `8393f5f`'s runtime, test and package bytes; this document commit is not itself a complete run.
- Owner decisions on the UX-01 conflict, the UX-13 *planned* interpretation, the UX-02/J4 Freeze-mark reading, and each open interpretation or scope gap above (LP-04, UX-07, LP-13, LP-14, UX-15, LP-15, UX-16, J3).
- Separate lanes for any open gap the owner accepts, each with a meaningful failing test first.
- Native observation under #133 for every pending row criterion, and explicitly:
  - First-launch warning and decline route on a fresh profile (UX-01 information-only Welcome; native Escape capture).
  - Ordinary Help leading to the guided coach versus the optional dense Reference, across every entry family (Records, Build Library, Plan, Journal, Orbs, Options, slash commands), including the new Questions (FAQ) and Auto explained entries.
  - Step 2 'Assigned now' versus the guide-local selection; selected visual and footer agree; Back, reopen and /reload keep truthful evidence without changing the actual assignment.
  - Step 7 summary and post-/reload readability.
  - Historical Step 5 long-option and UI-text-scale variant (the 163012 sample at 1760x990, 100% HUD fitted only that sample).
  - Back, Skip, refusal, replay and suppression behavior of the coach and Welcome.
  - Every per-row native criterion below.
- The next coordinated screenshot pack and a separate first-time-player review. Any new recommendation from it needs owner approval before implementation. The current gold FAQ repair and the separate screenshot usability review do not close #131.
- Final composition, PR and release gates stay as they are. Nothing here closes #131 or accepts any row natively.
