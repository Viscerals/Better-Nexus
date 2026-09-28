# Nexus — player guide (experimental)

Nexus helps you work toward an Echo build: plan a Wishlist, follow roll
recommendations or let Auto act for you, refine with Orbs, share builds and
compare recorded DPS. This is an experimental build, not a stable release.
The same guide is in the game: `/nexus help`.

## Install and roll back

Close WoW. Back up `Interface/AddOns/Nexus` and your matching `WTF` folder
outside the game folder. Replace only the addon folders; do not merge packages,
reset SavedVariables or delete Wishlists.

The ZIP contains TWO folders. Both go into `Interface/AddOns`:

| Folder | Installed path | What it is |
| --- | --- | --- |
| `Nexus` | `Interface/AddOns/Nexus/Nexus.toc` | the addon (not a nested Nexus/Nexus folder) |
| `NexusSupport` | `Interface/AddOns/NexusSupport/NexusSupport.toc` | storage only, so a support report can be written to its own file |

`NexusSupport` has no gameplay logic. Nexus runs without it; only the report
file needs it. Check the build label and checksum published beside the ZIP.

Turn off any other Echo-picking addon; while Nexus detects one, it pauses Auto
and Orb mode.

To roll back: close WoW and restore the old addon and the matching old saved
data together. A backup cannot undo spent Orbs, changed Echoes or builds already
sent to other players. Do not roll back while an Orb result is unresolved.

## Get started

1. Open the Wishlist Editor: click **...** on the Nexus panel, then
   **Wishlist Editor**, or type `/nexus editor`. Click **Create Wishlist**, or
   **Import** and paste a Wishlist code. Import opens a draft.
2. Check exact qualities, copy counts and the planned locked Echo targets.
   Click **Save Wishlist**.
3. In **My Builds**, select the intended Saved Build and assign the Wishlist to
   it. Assigning only chooses the target; by itself it does not change the Saved
   Build.
4. Read **Automatic save and your Saved Build** below before you turn Auto ON.

A Wishlist is a desired plan; you do not have to own it already. **Saved Builds**
are server slots. **Active Loadout** is the selected server loadout. **Build
Library** shows shared records known to this client. They are different things.

### Automatic save and your Saved Build

Wishlist assignment and automatic save are separate steps:

- **Wishlist assignment** chooses the target a Saved Build/loadout works toward.
  By itself, it does not change the Saved Build. Unassign keeps the Wishlist
  and does not change or restore the Saved Build.
- **Automatic save** is a separate action, distinct from
  Take/Banish/Reroll/Freeze. With Auto ON, after a completed run Nexus compares
  that run with the Wishlist assigned to the active loadout and may replace the
  **active Saved Build** with it, giving it the Wishlist's name. The slot is
  treated as an evolving working copy, not a protected archive.

Not every run is saved. A run replaces an existing Saved Build only when its
overall Wishlist progress is higher than the Saved Build's, or equal with
cleanup (some extra copies removed, or an even swap of requested copies).
“Better” means overall Wishlist progress. It does not mean keeping every
individual Echo, and Orb investment is not part of the comparison.

The check does not wait for a new run. At level 80 after a finished run,
turning Auto ON or changing the assigned Wishlist makes Nexus check again right
away, so a replacement can follow within seconds. Saving edits to the assigned
Wishlist can also lead to a replacement without a new run.

Example: your Saved Build holds an Echo you value. The next completed run loses
one requested copy but gains three other requested copies. That is +2 overall
Wishlist progress, so Nexus may save the new run over the old build. The save
itself spends no Orbs, but Orbs already spent on the replaced Echo are not
recovered, and Nexus cannot bring that Echo back. The save does not mean the
lost Echo was judged worthless.

Nexus cannot undo a completed server save. There is no separate automatic-save
switch: Auto OFF stops it. Auto starts OFF each session; keep it OFF if you want
Nexus to leave the current Saved Build untouched.

## Auto and rolling

1. Review recommendations with Auto OFF first.
2. Click **Auto OFF** on the Nexus panel to turn Auto ON only after reading the
   automatic-save section above. Auto is a permission for your enabled
   automatic actions. Auto OFF does not turn Nexus off, stop sharing or hide the
   panel.
3. Set actions: `/nexus reroll on|off` and `/nexus freeze on|off`. They do not
   turn Auto on.

Reading the panel: **Needed**, **Target already met**, **Not on Wishlist** and
**Different quality from target** describe the current choice. **EXTRA COPIES**
are rolled copies above exact targets: target 2, current 5 means 3 extras. The
display deletes nothing.

When it is blocked:

- “Waiting for the game to confirm the last Echo action.” — an action was sent
  and has no confirmed result yet. Do not choose again or reload; wait.
- “No Echo choice is showing.” — no choice is on screen now. It does not mean the
  run is finished, and it is not a reason to retry.
- “Auto ON — paused” — Auto stays ON but is not acting; the reason is shown.
- “Waiting for current Echo data” — waiting for ownership data, not Sync status.
- Ordinary rolling stays paused during active or unknown Orb offers.

## Wishlists and locked targets

A plan holds up to **79 rolled copies + 6 locked Echo copies** (85 total).
Counts are copies. Each quality is a different target; a lower-quality copy does
not count for a higher-quality target.

- Currently locked Echoes are what you have. Locked Echo targets are what the
  plan wants.
- If the editor asks, choose the locked targets and click
  **Confirm locked targets & edit** (or **& assign**). Confirming locks nothing.
- A Frozen offer is kept temporarily by the game's Freeze action; it is not a
  locked slot.
- Automatic locked-slot changes need Auto, their separate option, ownership and
  safety checks. Orbs never change locked slots.
- `/nexus currentlocks on|off`: whether future imports without locked markers
  use your matching currently locked Echoes by default.

## Orbs / Lost Memories

Orbs refine rolled Echoes toward the assigned Wishlist, one Orb per replacement.
They cannot create or replace locked slots; a run stops when rolled targets are
complete. Opening the window, **Open Orbs...**, Help and **Max** spend nothing.

1. Open `/nexus orbs`, **Orbs / Lost Memories** in the **...** menu, or
   **Open Orbs...** on the panel. Check the assigned Wishlist, missing copies and
   the confirmed Orb balance. Loading is never a zero balance.
2. Set the maximum. Until you type an amount it follows your confirmed balance,
   up to 1000. Typing stops that; **Max** returns to following the balance. A
   typed amount is a whole number from 1 to 10,000. A maximum saved by an
   earlier version is kept.
3. Click **Start**. Start approves the maximum shown and automatic use of eligible
   surplus copies, including safe recycling. It turns ordinary Auto OFF; it does
   not turn it back ON. The approved maximum does not change during the run.
4. The run continues after each confirmed result and stops at completion, the
   maximum, low balance, no safe source or uncertainty.

Closing the window does not stop an approved run. Use Pause or Stop.

After a finished run, click **Start new run**, review the maximum, then click
**Confirm new run**. If the maximum changes, press Start new run again.

When it is blocked:

- Pause/Stop prevents new submissions; it cannot undo an accepted spend, and a
  pending result may still settle.
- Changing the active loadout, assignment or targets pauses new actions; Resume
  adopts the new target and keeps the same maximum.
- **Recheck** (Advanced) only asks for balance and ownership data. It is not a
  replay or a fix.
- An unresolved Orb result keeps its spending exposure and blocks new Orb runs
  and ordinary rolling. Relogging, reloading, changing builds, returning to the
  old loadout or pressing controls again does not clear it. Nexus never retries,
  refunds or deletes it. Do not clear saved data.
- The one manual case: after a reload, if that action's offer is still open in
  the game's offer window and matches the saved record, choose in that window.
  Nexus confirms it only from the exact matching result, and only for the Echo
  it proposed (the Orb window names it). An action that ended unobserved cannot
  be confirmed; no exit from that block exists yet.

## Shared builds, DPS and Sync

1. Click **Build Library**. The scope button switches between **All Shared** and
   **My Builds**.
2. **Require both DPS records** — checked: only builds with both a Training Dummy
   and a Lich King record this client holds. Unchecked: no such requirement;
   other filters still apply. A record is availability, not build quality,
   outside verification or finished Sync. While a change applies, the list says
   **Updating results...**
3. **Copy into Editor** creates a draft; it does not activate or spend.
   **Share Build** sends a listing; it is separate from saving a Wishlist or a
   Saved Build.

- **Stop Sharing** removes the listing on this client; removal on other clients
  is not confirmed. Stop Sharing, administrator removal and deleting from My
  Builds are different actions; read each confirmation.
- Names show the player and realm a record states; they are not proof of
  identity. A record whose owner is not established says
  “Owner identity not established.” in its details. Two records can show the
  same name.
- Locked targets on shared builds: players on this version receive them when
  both sides support them. Older versions receive the ordinary targets only; your
  Share status counts those answers. A build from an older version shows its
  locked targets as unknown, not as none. A received build is not always ready to
  copy. Sent does not prove that another player stored it.
- Leaderboard tabs: **Training Dummy**, **Lich King**, **Both records** (ranked
  by the highest single result). DPS capture needs Details!.
- **Sync Now** asks for shared data; preparing, sent, receiving and finished are
  different states. Do not flood the sharing network.

## Report a problem

No report/logs or requested details = your support request will be ignored
until provided.

If something goes wrong, do not reload, relog, spend Orbs, reroll or change
builds to recreate it. Do not clear logs or reset saved data.

1. Type `/nexus report` when the problem happens, before any reload. Its
   incidents are kept for this session only.
2. Click **Copy summary**. Press Ctrl+A, then Ctrl+C, and paste it.
3. Add your exact build (`/nexus update` shows it), what happened versus what you
   expected, and Auto ON or OFF. Provide any additional logs requested.

Report file (private): click **Prepare report file** and wait until it says the
report is prepared. WoW writes the file only when you reload, log out or exit.
`/reload` only when no action is active or pending. Then send this file
privately; never post it publicly:

`WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua`

It is not the `NexusSupport.lua` inside the addon folder. Both Nexus and
NexusSupport must be installed and enabled.

If reporting fails: if the window says “Not prepared”, or logs are unavailable,
say so and send what you have. Copy summary works without NexusSupport. You are
not asked for logs that a broken reporting feature cannot create. Do not post
full SavedVariables or account details publicly.

## Commands

- `/nexus help` (also `/nexus guide`, `/nexus tutorial`): this guide, also during loading.
- `/nexus report`: support report.
- `/nexus editor`: Wishlist Editor.
- `/nexus orbs`: Orb window; does not spend.
- `/nexus panel`: show or hide the panel. Hiding does not turn Nexus off; to
  disable Nexus, use the game's AddOns list and reload.
- `/nexus loading`: startup progress (a percentage is for the current step only).
- `/nexus status`, `/nexus update`, `/nexus sync`, `/nexus log errors`,
  `/nexus perf` (timing, not DPS), `/nexus prototype` (build details).

**Prepare full diagnostic report** (in the log viewer) builds a paged report:
**Select this page**, then copy pages in order. Advanced commands (flags,
undemote, anchor, restore, err) are troubleshooting tools, not generic fixes.

Update notices come only from release information shipped in this package. No
notice does not mean your build is the latest. Nexus never downloads or
installs anything.

## Status and limits

This is an experimental prerelease. Offline tests use synthetic game services;
they are not native WoW verification. Native Orb behavior, native timing,
full peer convergence and older data recovery are not established. Stop for
unexpected actions, persistent uncertainty, errors or severe stalls, and
report them as above. Detailed history is in the source archive under `docs`.
