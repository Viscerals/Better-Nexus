-- Reopenable read-only reference pages: the optional full manual (/nexus
-- reference, the coach's Reference topics and each window's Reference
-- button). /nexus help, /nexus tutorial and each window's Help button open
-- the guided setup coach instead (design/current "Nexus Setup Alternative";
-- H.OpenHelp). Available before saved data or shared data is ready.
Nexus=Nexus or {}
local H={};Nexus.Help=H
local frame,index= nil,1
-- Called once when Help closes (Close, Escape or a hide), for a window that
-- stepped aside for Help (H.Show's onReturn). A route that opens another
-- window drops it (Leave), so nothing is brought back over that window.
local returnTo=nil
-- Keep the complete Help window above the Orb dialog's 30-33 layer band.
local HELP_LEVEL=40
-- Full visible-UI localization (guide family, help.* keys). Every visible
-- English text of this window is a reviewed catalog meaning looked up through
-- Nexus.Localization when it is shown (never cached here). Without the seam,
-- or for a key it cannot show, the exact English kept beside it is shown:
-- the page's own text (H.Pages[i].text stays the complete English reference)
-- or the English argument. Page ids, topic ids and routes are identities.
local function T(key, english)
    local seam = Nexus.Localization
    if type(seam) ~= "table" or type(seam.Text) ~= "function" then return english end
    local text, source = seam.Text(key)
    if source == "unavailable" then return english end
    return text
end
-- args(seam) builds the template's arguments (seam.Count for counts).
local function TF(key, args, english)
    local seam = Nexus.Localization
    if type(seam) ~= "table" or type(seam.Format) ~= "function" or type(seam.Count) ~= "function" then
        return english
    end
    local text, source = seam.Format(key, args(seam))
    if source == "unavailable" then return english end
    return text
end
local pages={
 {id="start",title="Getting started",titleKey="help.title.page_start",text=[[Start here: Setup / Welcome opens Guided setup at the step you left. Click it above to begin; that is the first task, and opening it never turns Auto ON. It is also in the Options menu on the Nexus panel (Options > Setup / Welcome), and Help in each Nexus window, /nexus guide, /nexus help and /nexus tutorial open it too. You do not need the rest of this page to start.

Guided setup goes one step at a time: choose or create a Wishlist, choose the Saved Build that should follow it, assign it in the Echo Journal chooser, try a SIMULATED recommendation and decide about Auto. A step is done only after Nexus reads the result back; a skipped, pending or unknown step is not done. Opening, navigating or closing the guide assigns, shares, spends and turns on nothing. It saves only its own place for this character and, when you first close the first-launch guide (Close or Escape), that it was seen, and only when saved data can be written; its steps stay as they are.

Other setup routes, when you want them:
Assign Wishlist... opens the Echo Journal with its Wishlist chooser for the Saved Build the Journal shows; nothing is assigned until you choose a Wishlist there. It is also under Plan on the Nexus panel.
Setup information (read only), in the Options menu, under More help and windows, is the older information-only overview of these routes; it saves nothing and never turns Auto ON.
Setup checklist (also in the Options menu) is listed there as Setup checklist and status, under More help and windows. It shows what Nexus can read now: start-up, the Saved Build Nexus would act on, its assigned Wishlist, Auto, Sync and any Orb run. A step is done only when that is true now; unknown or still loading is never shown as done, and closing the Welcome is not a setup step. Its buttons only open the same windows as here.

Reference for later: the page buttons above open any page directly; Reference in a Nexus window opens its own page here.

This is an experimental build. Back up your Nexus folder and WTF with WoW closed before testing. Reading this guide never spends, assigns, activates, or sends a Sync request.

Before you turn Auto ON: With Auto ON, Nexus may replace that active Saved Build with a better finished run; at level 80 after a finished run, that can happen right after you turn Auto ON or change the assignment. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. It treats the slot as a working copy, not a protected archive. Keep Auto OFF if you want it left unchanged. Auto starts OFF each session.

1. Open the Wishlist Editor: click Plan on the Nexus panel, then Wishlist Editor (also in the Options menu under More help and windows), or type /nexus editor. To use a Wishlist code, click Import and paste it. Import opens a draft.
2. Check exact qualities, copy counts and the planned locked Echo targets.
3. Click Create & assign for a new or imported plan. It saves the plan and makes it the target of the loadout shown in the editor. Create unassigned saves the plan without a target. For an existing Wishlist, click Save changes. It keeps the Wishlist's current target.
4. To target another Saved Build: in My Builds, select the intended Saved Build and assign the Wishlist to it (click the Wishlist selector and choose the Wishlist). Assigning only chooses the target; by itself it does not change the Saved Build.
5. Review the recommendations with Auto OFF first. Click Auto OFF only when you accept the warning above; it then shows Auto ON.

What Nexus is for: you choose the Echoes you want (a Wishlist). Nexus counts the exact copies still missing and recommends, or with Auto ON performs, Take, Banish, Reroll and Freeze on each Echo choice to work toward them.

More detail, when you need it:

Saving and loading Saved Builds: in the game's own build window, loading a Saved Build makes it your current loadout. Saving writes your current Echoes into the slot you selected and REPLACES what that slot held. Check the selected slot before you save; Nexus cannot undo a save or bring back the old contents. Nexus never loads a Saved Build for you. Its only save is the automatic save with Auto ON, described above. Creating or importing a Wishlist saves only a plan. Assigning a Wishlist by itself changes no Saved Build.

Words: A Wishlist is a desired plan, not proof that you own its Echoes. Saved Builds are server slots. Active Loadout is the selected server loadout. Nexus treats no future random Echo roll as guaranteed.

Counts: planned copies (the plan), rolled copies this run, the Wishlist's copies in a Saved Build and locked targets are different counts, and Echo families represented counts a family once. Unavailable is not 0, and a plan is not a finished build. Best known: the best shared DPS record this client holds for the exact same Echoes; it is not a complete or server-wide ranking. My Builds is the game's page of your Saved Builds; in Build Library, the Mine scope lists your Saved Builds and shared listings. Options: the Options button on the Nexus panel header opens a short menu: Questions (FAQ), Setup / Welcome, Auto explained, Appearance, settings, notices, the session pause and panel actions. Its More help and windows list opens Reference (the full manual), the setup information and checklist, the support report, the log viewer, Orbs and the Wishlist Editor. Point at Options for the current status.]]},
 {id="wishlists",title="Wishlists and locked targets",titleKey="help.title.page_wishlists",text=[[Before you edit: a plan holds up to 79 rolled copies and 6 locked Echo copies (85 total). Counts are copies, not names or rows. Each quality is a different target; a lower-quality copy does not count for a higher-quality target.

1. Open the Wishlist Editor (/nexus editor). Import opens a draft; nothing is kept until you click Create & assign or Create unassigned (new plan) or Save changes (existing Wishlist).
2. If the editor asks for locked targets, choose them, then click Confirm locked targets & edit (or & assign). You do not need to own the plan already.
3. Create & assign saves a new plan and makes it the target of the loadout shown in the editor; Create unassigned saves it without a target; Save changes saves an existing one and keeps its target. A Wishlist opened for a Saved Build that does not use it also offers Save & assign, which saves it and makes it that Saved Build's Wishlist. In My Builds, the Wishlist selector chooses which Wishlist a Saved Build uses; Unassign Wishlist keeps the Wishlist.

Locked Echoes and targets: Currently locked Echoes are what you actually have. Locked Echo targets are what the plan wants. A Frozen offer is a temporary offered card kept by the game's Freeze action; it is not a locked Echo slot. Opening or confirming targets does not lock/unlock anything. Automatic locked-Echo slot changes require both Automation and their separate option, plus ownership and safety checks.

Imports without locked markers use your matching currently locked Echoes by default if that makes a valid 79+6 split. Existing confirmed plans are unchanged.
/nexus currentlocks off: choose future untagged plans manually.
/nexus currentlocks on: use matching locked targets by default.
Nexus-only locked-role markers should be imported in Nexus, not assumed compatible with every native importer.]]},
 {id="rolling",title="Auto, rolling and saving",titleKey="help.title.page_rolling",text=[[Before you turn Auto ON, read this. Automatic save is separate from Take, Banish, Reroll and Freeze. After a completed run, Auto may replace your active Saved Build with that run and give it the Wishlist's name. Nexus compares the run with the Wishlist assigned to that loadout. It replaces an existing Saved Build only when overall Wishlist progress is higher than the Saved Build's, or equal with cleanup (some extra copies removed, or an even swap of requested copies). Not every run is saved. Assigning by itself changes nothing, but at level 80 after a finished run, turning Auto ON or changing the assigned Wishlist makes Nexus check a finished run it has not saved yet against that Wishlist, so a replacement can follow without a new run; how soon is not promised. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. There is no separate automatic-save switch: Auto OFF stops it.

Better means Wishlist progress, not Orb investment or keeping every individual Echo. Example: a run that loses 1 requested copy but gains 3 other requested copies is +2 overall. It can replace the Saved Build even when the lost Echo is one you value or obtained with Orbs. The save itself spends no Orbs, and it does not mean that Echo was judged worthless. Nexus cannot undo a completed save or bring back that Echo or the Orbs spent on it; Unassign does not restore a Saved Build. Keep Auto OFF if you want the current Saved Build left untouched. Auto starts OFF each session.

What Auto may do: with Auto ON, Nexus acts only within these permissions. Take needed Echoes (autoPick), Banish (autoBanish), Reroll (autoReroll), Freeze (autoFreeze), turning tomes off and on (autoDisable) and the automatic save over the active Saved Build (autoSave) are on by default. Locking Wishlist Echoes into locked slots (autoLockEchoes) is off by default; it is its own option in the Wishlist Editor. Nexus never activates or loads a Saved Build (the saved autoActivate value is not used by any action), and Auto never starts an Orb run. To see each current value, click Options on the Nexus panel, then Automation settings; Reroll and Freeze can be changed there or with the commands below. The Auto warning lists the same permissions.

Tomes: with Auto ON and the tome permission (autoDisable) on, once the game's tome data is ready Nexus turns off Echo tomes your Wishlist does not use and turns back on tomes it needs, one change about every half second. It never turns off a tome you opted out of. Nexus does not turn tomes back on when you turn Auto OFF, log out or change the Wishlist: it turns back on only tomes a Wishlist needs (or that you opted out of), and only while Auto is ON. The tome list in the Echo Journal shows their state.

1. Click Auto OFF on the Nexus panel to turn Auto ON. Auto is a permission for your enabled automatic actions. Auto OFF does not turn Nexus off, stop build sharing, or hide the panel.
2. Choose actions: Options > Automation settings, or /nexus reroll on|off and /nexus freeze on|off. They change those permissions, not the Auto button. Each one only allows or forbids that action; it does not choose another strategy. When an action is off, Nexus skips that step and uses the next rule below.
3. Watch the panel. It shows what Nexus recommends now; with Auto ON, Nexus performs it.

EXPERIMENTAL STRATEGY (the default in this build). The released strategy stays available as a rollback. On an ordinary Echo choice the experimental strategy keeps every permission, charge, pending-action and Orb rule and changes these steps:
- Two needed offers shown, none held: it can Freeze one so the second is kept. It does not Freeze the extra copy of an Echo when one more copy is all you need.
- Several needed offers: it takes the offer with the most missing copies. A tie goes to the first offer shown.
- No offer needed: when a Reroll is also available, it Banishes before it Rerolls, if Banish is allowed and charged. It Banishes only an offer that is not needed, not frozen, not guaranteed, and whose quality group holds no needed Echo. If none qualifies, it Rerolls as before.
- Only held offers are needed: it takes the held offer instead of searching.
It comes from an offline simulation that assumes equal draw odds for every Echo you can still roll. That assumption is not measured in the game. In the study's 57,600 held-out runs (14,400 per strategy, averaged over 12 model profiles, several of which the live version does not model) it completed 19.3% of Wishlists, against 16.8% for the released strategy; its lead over a simpler protected-Banish strategy was not significant. No gain in your game is promised: it can be better, equal or worse. The live version has no draw-pool data, so among equally safe offers it Banishes the first one shown.
/nexus policy adaptive or /nexus policy released chooses. A change applies at the next safe action boundary and never clears or repeats an action that waits for confirmation. /nexus status shows the strategy in force. When Nexus cannot use the experimental rules for one choice (for example an Echo's quality group is unknown), it uses the released rules for that choice and /nexus status says why.

How the released strategy chooses on an ordinary Echo choice (in this order). Needed means an offer of the exact Echo and quality that still has missing copies: the Wishlist's copies minus the copies you have, rolled and locked (with locked targets, locked copies count only up to those targets). Picks are very few when 6 or fewer remain, or no more than the missing copies. Picks are few when 18 or fewer remain, or the missing copies are at least a third of them.
- All targets complete: Nexus takes an available offer. It can be outside the Wishlist.
- No offer is still needed: Reroll comes first, when Reroll is allowed, you have one and fewer than two offers are frozen.
- A needed offer is shown: Nexus takes it. Freeze is used only in some cases: picks are very few, at least two copies are still missing, Freeze is allowed and charged, and a Banish is available to search further. After a Freeze, Nexus takes another needed offer if one is shown. While picks stay very few and a Banish is left, it banishes an offer that is not needed. Otherwise it takes the frozen offer.
- No offer is needed and Reroll is not possible: when picks are few, Nexus banishes an offer that is not needed and not frozen. Otherwise, or with no Banish left, it takes an available offer, which can be outside the Wishlist.
Nexus does not keep rerolls back for later in a run. These rules are not a guarantee of any future offer or of a complete build.

Reading the panel: Needed, Target already met, Not on Wishlist and Different quality from target describe the current choice. Frozen offer is a card kept by Freeze. Priority numbers in advanced diagnostics are not DPS or percentages. EXTRA COPIES are rolled copies above exact Wishlist targets. Target 2/current 5 means 3 extras. This display deletes nothing. [Guaranteed offer] means the server marks this offer guaranteed. Overlay: [X] meets the requested copy count; [~] some; [ ] none. These symbols are not network or loading states.

When it is blocked: "Waiting for the game to confirm the last Echo action." means an action was sent and has no confirmed result yet. Do not choose again or reload; wait. "Auto waiting" means Auto stays ON and holds its actions for such a result, or for an action the game still shows pending. "Auto rechecking" means it also asks the game again for your granted Echoes, at a slow pace and only while that could settle the wait; a request is not an answer and nothing is resent. The game gives Nexus no receipt for an Echo selection. If the matching grant never appears, or another selection of the same Echo makes it impossible to tell which one was granted, Nexus keeps waiting until a new run. Turning Auto off and on does not end that wait. A reload ends Nexus's tracking of it without learning or cancelling the result. Point at the Auto button to see what Auto is doing now and why. "No Echo choice is showing." means only that no choice is on screen now. It does not mean the run is finished, and it is not a reason to retry. "Auto ON — paused" means Auto stays ON but is not acting; the line below it says why and what helps (the Status line of the Options button's hover has it too). When an Auto click leaves Auto OFF, the same place says why. Waiting for current Echo data means automatic choices wait for ownership confirmation; it is not Sync status. Ordinary rolling stays paused during active or unknown Orb offers.]]},
 {id="sharing",title="Shared builds and DPS",titleKey="help.title.page_sharing",text=[[1. Click Explore on the Nexus panel, then Build Library. Use the scope buttons to switch between All Shared and Mine (your Saved Builds and shared listings; not the game's My Builds page). If the Build Library is taller than your screen (for example with large text), its content scrolls: use the bar at its right edge, or the mouse wheel over the window outside the build list and the build details, which scroll on their own.
2. Require both DPS records: when checked, only builds with both a Training Dummy and a Lich King record that this client holds are listed. When unchecked, that requirement is off; other filters still apply. A record shows what this client holds. It is not build quality, outside verification, or finished Sync. While a filter change is applied, the list says Updating results...
3. Copy into Editor creates a draft; it does not activate, spend or share. Your own Share actions need your click: on your own Saved Build, Share Build... at the right asks you to confirm first, and the Share Build form shares when you press its Share Build button. With Sync set to Automatic, an eligible new character best for Training Dummy or Lich King may send without a click: a DPS record with your ordinary and any locked Echoes and player info, plus a separate automatic "Record Loadout" summary without the Echo list. That DPS record carries its Echo list. The DPS record does not need a request or that summary: receivers may create a viewable, copyable page from the record alone. An oversized summary is refused separately; it does not stop an otherwise admitted DPS record. Manual and Off refuse both automatic sends. Sending is not delivery: Nexus cannot confirm that anyone receives or keeps what it sent. A shared build cannot be recalled: players who receive it keep their copy. Sharing is separate from saving a Wishlist or a server Saved Build.

Removing: Stop Sharing, an administrator removing a shared record, and deleting one of your builds under Mine are different actions. Read each confirmation. Stop Sharing removes the listing here; removal on other clients is not confirmed. Removing a shared listing does not delete your server build or Wishlist.

Names: a name shows the player and realm the record states. It is not proof of identity. When a record's owner is not established, its details say "Owner identity not established." Two different records can show the same name.

Locked targets on shared builds: players on this version receive a build's locked targets when both sides support them. Older versions receive the ordinary targets only; your Share status counts those answers. For a build from an older version, Nexus treats its locked targets as unknown, not as none; no locked row is shown. A received build is not always ready to copy. Sent does not prove that another player stored it.

Leaderboard: Training Dummy, Lich King and Both records tabs. Both records ranks by the highest single result; an average is display-only. DPS capture needs Details! and its supported events.

Sync Now asks for shared builds and records. Preparing, request sent, receiving updates, and finished are distinct. Do not flood the sharing network or send test traffic.

What Sync sends: your saved Sync mode decides. To choose it, click Sync mode... beside Sync Now in the Build Library, pick Automatic, Manual or Off, and click Apply. Opening it, Cancel, X, Escape and closing the Build Library change nothing. Apply saves only your choice for this account and sends nothing by itself. After Apply Automatic, normal background Sync can start later, including a pending login request. Without a choice of yours, Sync is Automatic, except where accepted saved settings from another Nexus version (formats 3 to 5) chose Off or Manual; your own choice replaces that. A saved file this version keeps read-only cannot take a choice. The Build Library status and the Sync Now tooltips show your current mode.
- Sync is Automatic: Nexus may send without a click. After login it asks other Nexus users for shared builds and DPS records, and it answers their requests with the shared builds and records this client holds. A Training Dummy result lasting at least 30 seconds, or a Lich King result lasting at least 20 seconds, may send a DPS record when it becomes this character's best for that encounter and passes the existing checks. A personal best for another Echo set below that encounter best stays local. The record includes your character name, realm, class, level, ordinary Echoes, any locked Echoes, encounter, DPS, duration and time and, when verified, the linked build ID. It can leave without a request, independently of its separate Record Loadout summary, and receivers may create a viewable, copyable page from the record alone. Each of these leaves only if this client admits it: a record or summary that is too large, fails its checks or finds the send queue full stays here. Refusing the summary does not refuse the separate DPS record. What leaves may still reach no one.
- Sync is Manual: Nexus sends only what you start (Sync Now or Share).
- Sync is Off: Nexus sends nothing. Local records are kept.
In every mode Nexus joins its hidden Sync chat channel and can receive what others send. Changing the mode cannot recall anything already sent; work that was waiting follows the new mode when it would be sent.
When a newer best replaces an automatic Record Loadout page, Nexus removes the old page on this client only. It sends no removal, so players who already received the page keep it.

Sync words: queued means waiting to send. Sent means it left this client; receipt is not confirmed. Received means it arrived here. Stored means this client kept it after its checks. A listed build or record is one this client stored; it does not show which other players have it.]]},
 {id="orbs",title="Orbs / Lost Memories",titleKey="help.title.page_orbs",text=[[Before you start: Orb mode refines existing rolled Echoes toward the assigned Wishlist. It uses one Orb per replacement, then waits for the actual offer and the confirmed result. It cannot create, reorder, or replace locked Echo slots, and it stops when rolled targets are complete. Opening the window, Open Orbs..., Help and Max spend nothing.

1. Open /nexus orbs, Orbs on the Nexus panel, Orbs / Lost Memories in the Options menu under More help and windows, or Open Orbs... (shown with Orb guidance). Check the assigned Wishlist, missing rolled copies and the confirmed Orb balance. Loading or unavailable data is not a zero balance.
2. Set the maximum. Until you type an amount, it follows your confirmed Orb balance, up to 1000. Typing an amount stops that; Max returns to following the balance. A typed amount must be a whole number from 1 to 10,000. A maximum saved by an earlier version is kept.
3. Click Start. Start approves the maximum shown and automatic use of eligible surplus copies, including safe recycling. Starting disables ordinary Automation; it does not automatically re-enable it. Locked and required copies stay protected. The approved maximum does not change during the run. If unconfirmed history exists, the same Start area shows its count and late-result risk; Start accepts current Echoes as this run's baseline without settling old actions. Reload requires a new deliberate review.
4. Watch the run. It continues after each confirmed result; actual owned Echoes decide completion. Start permits at most two recovery checks within the same maximum; a check that is admitted and then refused still uses one. Unknown spend exposure stays counted. A classified loading screen holds actions, restarts the pending timer on entry and allows a three-second settling opportunity. Stop and Pause stay authoritative. No safe source still ends the run. Orbs used counts spent Orbs against the approved maximum; pending means an Orb was requested and its spend is not confirmed yet. If a record saved by an earlier version has no approved maximum, the Orb windows say the maximum was not recorded instead of naming one.

The game's auto-accept and other addons' pickers must be off. If the game has no Orb service, only Orb mode is unavailable and ordinary rolling still works. If the Orb service exists but Nexus cannot read its state, ordinary rolling waits too. Login, reconnect, new resources or reload never restart spending. If another addon changes how Orb requests are sent after Nexus starts watching them, recovery checks may be unavailable during that interface session: Nexus then pauses and keeps the pending record and its spending exposure. Continue is offered only when its checks pass.

Closing the window does not stop an approved run. Use Pause or Stop. During a run, Pause and Resume are separate buttons in fixed places, so pressing Pause twice never resumes. The main Nexus panel keeps compact progress with the same Pause, Resume and Stop.

After a finished run: click Start new run, review the maximum, then click Confirm new run. If the maximum changes, review it and press Start new run again.

When it is blocked: Pause/Stop prevents new submissions, not a spend already accepted; a pending result may still settle. Changing the active loadout, assignment or targets pauses new actions. While paused, the Orb window, the main panel and the mini panel name the Wishlist that Resume would use when that target is ready; no target is named for a Wishlist that is not ready, while an earlier submitted action must settle first, or when the run can no longer resume. After a change, an operation already submitted settles first. Then click Review target in the Orb window and Resume there: Resume adopts the new target and keeps the same maximum. Review target spends nothing. It acts only on the target shown when you click it; if the target changed just before, nothing is reviewed and the window shows the new one. If the assignment changed and came back to the run's own Wishlist, the window says the target is back, and Review target is still needed. During a loading screen, until the world is ready again and briefly after you enter, Nexus submits no new Orb spend or choice to the game and Resume stays off; a kept approval never permits spending or choosing during that window. After a classified loading screen, a running run keeps only its existing approval and waits for the game (Waiting for the game after loading) before any new action; if the run is paused instead, Resume needs its current checks. Pause and Stop still apply. If the approval or the original character, run or service context is missing, a paused run may no longer own its action: then Resume is not offered; Stop, then approve a new run. Advanced has optional exclusions and Recheck. Recheck only asks for balance and ownership data; it is not a replay or a fix.

Unresolved result: an Orb action without a confirmed result keeps its spending exposure and blocks new Orb runs and ordinary rolling. The Orb window shows what is blocked, then what you can do now, then the details. A result restored after a reload that keeps the run paused reads the same way, labelled Paused. Where Continue... is offered, the window says the result blocks until it settles or you continue past it. Relogging, reloading, changing builds, returning to the old loadout, Resume or pressing controls again do not clear it. Recheck can request the confirming data; pressing it does not clear the record. Nexus never retries or refunds it, and never deletes the record. Do not clear saved data.

Only one manual case can confirm it: after a reload, if that action's offer is still open in the game's offer window and matches the saved record, choose in that window. Nexus confirms the action only from the exact matching result. If Nexus had proposed an Echo, only that same Echo can be confirmed; the Orb window names it. If the action ended while Nexus could not observe it, it cannot be confirmed.

Reloading: a reload never clears the record, refunds or repeats an Orb, or settles the action by itself. For Orbs, Nexus suggests a reload only in these cases, and its message says which: the game still holds an earlier Orb choice (the Orb window names the Echo to choose after the reload); a submitted action that cannot be confirmed, which Continue may then handle; a game packet Nexus could not accept; or local saved data that could not be read. Otherwise do not reload; follow the Orb window. To report a problem, type /nexus report before any reload. Run history clears on reload or logout; after a reload the Continue window says the earlier steps are not listed, and the saved record is kept. The history of the current run shows its usage as it is now; when the run has changed since its last recorded step (Pause records none), the header says the current state and the last recorded one.

Continue: a restored observed spend with no recorded choice and no open offer can use this explicit exit. Stop first if an attribution-ambiguous run is still running. A stopped attribution-ambiguous choice can also use it when fresh ownership shows its distinct chosen gain; unrelated changes and the ambiguity flag alone are insufficient. This remains available after actual completion, exhausted live checks and reload, when its current checks pass. Nexus asks twice, read-only, for the Orb count and Echoes, checks quiet unchanged state, then waits for your confirmation. It archives the original receipt UNCONFIRMED with no confidence, ends the old run and releases ordinary rolling only after saving. Observed spend stays counted once; unknown charge exposure stays unknown without a refund. No spend, choice or automatic Resume is sent. The finite archive holds at most eight entries and can fill. Every new spend reserves room for its possible exit before Auto is disabled or authority acquired. A full restored pending record stays preserved and blocked; Continue cannot make room by deleting history. A new Orb run needs new approval of its maximum and any disclosed history baseline. Two uncorrelated answers do not prove that the server is finished or that no older answer is still on its way. Nexus never continues by itself. Older readers may retain a versioned record with an unsupported-owner message; that message does not establish another character acted. Return to this build to review eligibility; this does not restart spending.]]},
 {id="troubleshooting",title="Problems and bug reports",titleKey="help.title.page_troubleshooting",text=[[If something goes wrong: do not reload, relog, spend Orbs, reroll or change builds to recreate it. Do not clear logs or reset saved data.

Report a problem. No report/logs or requested details = your support request will be ignored until provided.
1. Type /nexus report when the problem happens, before any reload. Its incidents are kept for this session only.
2. Click Copy summary, click in the text, press Ctrl+A, then Ctrl+C, and paste it into your report.
3. Add your exact build (/nexus update shows it), what happened versus what you expected, and Auto ON or OFF. Provide any additional logs requested.

Report file (private): click Prepare report file and wait until it says the report is prepared. WoW writes the file only when you reload, log out or exit. /reload only when no action is active or pending. Then send this file privately; never post it publicly:
WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua
It is not the NexusSupport.lua inside your AddOns folder. Both Nexus and NexusSupport must be installed and enabled.

If reporting fails: if the window says "Not prepared", or logs are unavailable, say so and send what you have. Copy summary works without NexusSupport. You are not asked for logs that a broken reporting feature cannot create.

Loading: the loading panel shows the current step and elapsed time; a percentage is for that step only. /nexus loading reopens it. A gray Explore control means shared views are loading or unavailable; check its tooltip or /nexus loading for the current status.

Turning things off: Hide Nexus Panel (Options) or /nexus panel only hides the panel. Auto OFF only stops automatic actions. Pause Nexus for this session (Options) holds Auto, Orb actions, sharing and DPS recording until Resume Nexus, a reload or a logout; it is kept in memory only, windows, status and the checks on an action already sent stay available, an action already sent may still finish, and it cancels nothing that was sent. None of these turns Nexus off: it stays loaded. To turn Nexus off, only when no action is active or pending: log out to character selection, click AddOns, untick Nexus, and log in again.

Commands:
/nexus help or /nexus tutorial - Guided setup at your current step, also during loading
/nexus guide - Guided setup, one step at a time; opening it changes nothing
/nexus reference - these reference pages, also during loading
/nexus report - support report
/nexus editor - edit Wishlists
/nexus orbs - open Orb mode without spending
/nexus panel - show/hide the main panel
/nexus status - concise status
/nexus update - installed build and Releases page
/nexus sync - request shared-build Sync
/nexus log errors - recorded errors
/nexus perf - timing diagnostics (not DPS)
/nexus policy adaptive|released - rolling strategy
/nexus trace - local roll record (copy and send privately)

Local roll record: Nexus records its rolling decisions automatically, on this computer only. It keeps Echo ids, the offers, charges, the action chosen and sent, and the result seen. Owned and locked counts are kept for your Wishlist targets only, not for all your Echoes. It keeps no account, character, realm or Wishlist name, no chat and no credential, and it sends nothing anywhere. At most 256 records are kept in your saved data and the oldest are replaced first; a record says when a part is incomplete or cut short. Recording changes no action; offline it added about 0.1 ms per board. It is not proof of the game's draw odds. To send it, use /nexus report and Prepare report file (the file then also carries the record), or /nexus trace, which opens the Roll trace tab: copy each page in order. Send either privately, never in public. /nexus trace off or on switches recording; /nexus trace clear deletes the record.

More diagnostics: /nexus log opens the log viewer. Prepare full diagnostic report builds a paged report. Select this page and copy pages in order; it does not put every page on the clipboard.

Updates: update notices come from release information shipped inside this package; the Options button then reads ! Options. Another player's client can report a newer test build; Nexus shows that only as an UNVERIFIED hint. No notice does not mean your build is the latest. Nexus never downloads or installs.]]},
 {id="about",title="About and advanced details",titleKey="help.title.page_about",text=[[Ordinary rolling and Orb decisions come from EchoWeaver, the rolling engine that Nexus maintains itself. Orb decisions use EchoWeaver's source, target and fallback rules with Nexus's exact-quality, locked-role, approval, budget and confirmation safeguards.

EchoWeaver has no runtime dependency on another addon. Source and reuse notices are in THIRD_PARTY.md. Neither algorithm is claimed mathematically optimal or universally safe without matching client evidence.

This prototype uses a compatible global ChatThrottleLib where available, otherwise its disclosed private compatibility scheduler. That is not complete official-library/native acceptance.

Advanced commands are troubleshooting tools, not generic fixes. Do not experiment with them to clear a loading message. flags reads active safety assumptions; undemote clears recorded temporary assumption disablements; anchor changes the existing Adaptive Power preference; restore restores the prior host auto-accept setting; err displays the latest recorded error. Advanced diagnostics keep raw reason codes and identifiers so support can tell failures apart.

/nexus prototype prints build/reference details. The installed README contains the current player guide.

Known legacy compatibility and incomplete native validation remain disclosed. Offline tests are not native verification. Back up saved data and test voluntarily.]]},
 {id="faq",title="Questions (FAQ)",titleKey="help.title.page_faq",text=[[What do I do next?
Follow the step the panel shows, or Setup / Welcome (button above): it opens the guide at the step you left. Opening it changes nothing.

Which Wishlist is Nexus using?
The Wishlist line on the panel is the assigned Wishlist of your active Saved Build. A Wishlist you only selected, an example, or a Community build marked Preview is not used for rolling until you assign it in the Echo Journal chooser (Assign Wishlist... above).

What does Auto do?
Auto OFF: Nexus only recommends and you choose. Auto ON: your enabled actions may Take, Banish, Reroll and Freeze for you, and may save a better finished run over your Saved Build. Every permission and its current value: Options > Auto explained, or the Auto tab above.

Does Auto OFF stop Sync?
No. Sync has its own mode (Automatic, Manual or Off) in Sync settings; see the Sharing tab.

Pause, hide or Auto OFF?
Auto OFF stops automatic actions only. Hide Nexus Panel only hides the panel. Pause Nexus for this session (Options) holds Auto, Orb actions, sharing and DPS recording until you choose Resume Nexus, reload or log out. It is kept in memory only. Your windows, status and the checks on an action already sent stay available. An action already sent may still finish: pausing cancels nothing that was sent, Nexus stays loaded, and it does not stop all of its work on your computer. A reload does not decide a result that is still unknown. After Resume Nexus, Auto can continue if it was already on; Orb runs stay paused until you continue them in the Orb window.

Can I make the panel smaller or move it?
Options > Main panel size makes the main panel 50% to 150%; Reset to 100% puts it back. A screen too small for that size shows it smaller until it fits. Other Nexus windows, the Wishlist overlay, the game's own difficulty HUD and your UI scale keep their own size. Hold Shift and drag any part of the panel that is not a button to move it. Release Shift to stop. Options > Reset Panel Position puts it back.

How do I get back to what I was doing?
Close this window (Close or Escape). Reading these pages changed no setting, assignment or Auto.]]},
}
H.Pages=pages
-- Each page's text as catalog blocks, in order: {key, separator after it
-- (code-owned line breaks or the space between two parts of one long
-- paragraph), text-slot arguments}. Joined with the English base these
-- blocks give exactly the page's text above (tests/prototype/l10n_ui_guide.lua
-- checks every page). A block holding a "|" command is a template whose
-- slot inserts that command unchanged. Questions (FAQ) keeps its question
-- and answer apart, so the code-owned gold colour stays on the question.
local PAGE_BLOCKS = {
 start = {
  {"help.body.start_first_task", "\n\n"},
  {"help.body.start_guided_steps_1", " "},
  {"help.body.start_guided_steps_2", "\n\n"},
  {"help.body.start_other_routes_1", "\n"},
  {"help.body.start_other_routes_2", "\n\n"},
  {"help.body.start_reference_later", "\n\n"},
  {"help.body.start_experimental_backup", "\n\n"},
  {"help.body.start_before_auto_on", "\n\n"},
  {"help.body.start_setup_steps_1", "\n"},
  {"help.body.start_setup_steps_2", "\n"},
  {"help.body.start_setup_steps_3", "\n\n"},
  {"help.body.start_purpose", "\n\n"},
  {"help.body.start_more_detail", "\n\n"},
  {"help.body.start_saved_builds_1", " "},
  {"help.body.start_saved_builds_2", "\n\n"},
  {"help.body.start_words", "\n\n"},
  {"help.body.start_counts_1", " "},
  {"help.body.start_counts_2", " "},
  {"help.body.start_counts_3", nil},
 },
 wishlists = {
  {"help.body.wishlists_limits", "\n\n"},
  {"help.body.wishlists_editor_steps_1", "\n"},
  {"help.body.wishlists_editor_steps_2", " "},
  {"help.body.wishlists_editor_steps_3", "\n\n"},
  {"help.body.wishlists_locked_targets", "\n\n"},
  {"help.body.wishlists_import_locked", nil},
 },
 rolling = {
  {"help.body.rolling_auto_save_1", " "},
  {"help.body.rolling_auto_save_2", " "},
  {"help.body.rolling_auto_save_3", "\n\n"},
  {"help.body.rolling_better_means_1", " "},
  {"help.body.rolling_better_means_2", "\n\n"},
  {"help.body.rolling_permissions_1", " "},
  {"help.body.rolling_permissions_2", "\n\n"},
  {"help.body.rolling_tomes_1", " "},
  {"help.body.rolling_tomes_2", "\n\n"},
  {"help.body.rolling_turn_on_steps_1", "\n"},
  {"help.body.rolling_turn_on_steps_2", "\n\n", {reroll_command = "/nexus reroll on|off", freeze_command = "/nexus freeze on|off"}},
  {"help.body.rolling_experimental_strategy_1", "\n"},
  {"help.body.rolling_experimental_strategy_2", "\n"},
  {"help.body.rolling_experimental_strategy_3", "\n"},
  {"help.body.rolling_experimental_strategy_4", " "},
  {"help.body.rolling_experimental_strategy_5", "\n"},
  {"help.body.rolling_experimental_strategy_6", "\n\n"},
  {"help.body.rolling_released_strategy_1", " "},
  {"help.body.rolling_released_strategy_2", "\n"},
  {"help.body.rolling_released_strategy_3", "\n"},
  {"help.body.rolling_released_strategy_4", "\n\n"},
  {"help.body.rolling_reading_panel_1", " "},
  {"help.body.rolling_reading_panel_2", "\n\n"},
  {"help.body.rolling_blocked_1", " "},
  {"help.body.rolling_blocked_2", " "},
  {"help.body.rolling_blocked_3", " "},
  {"help.body.rolling_blocked_4", nil},
 },
 sharing = {
  {"help.body.sharing_library_steps_1", "\n"},
  {"help.body.sharing_library_steps_2", "\n"},
  {"help.body.sharing_library_steps_3", " "},
  {"help.body.sharing_library_steps_4", " "},
  {"help.body.sharing_library_steps_5", "\n\n"},
  {"help.body.sharing_removing", "\n\n"},
  {"help.body.sharing_names", "\n\n"},
  {"help.body.sharing_locked_targets", "\n\n"},
  {"help.body.sharing_leaderboard", "\n\n"},
  {"help.body.sharing_sync_now", "\n\n"},
  {"help.body.sharing_sync_sends_1", " "},
  {"help.body.sharing_sync_sends_2", "\n"},
  {"help.body.sharing_sync_sends_3", " "},
  {"help.body.sharing_sync_sends_4", " "},
  {"help.body.sharing_sync_sends_5", "\n"},
  {"help.body.sharing_sync_sends_6", "\n\n"},
  {"help.body.sharing_sync_words", nil},
 },
 orbs = {
  {"help.body.orbs_before_start", "\n\n"},
  {"help.body.orbs_run_steps_1", "\n"},
  {"help.body.orbs_run_steps_2", "\n"},
  {"help.body.orbs_run_steps_3", " "},
  {"help.body.orbs_run_steps_4", "\n"},
  {"help.body.orbs_run_steps_5", " "},
  {"help.body.orbs_run_steps_6", "\n\n"},
  {"help.body.orbs_requirements", "\n\n"},
  {"help.body.orbs_closing", "\n\n"},
  {"help.body.orbs_after_run", "\n\n"},
  {"help.body.orbs_blocked_1", " "},
  {"help.body.orbs_blocked_2", " "},
  {"help.body.orbs_blocked_3", " "},
  {"help.body.orbs_blocked_4", " "},
  {"help.body.orbs_blocked_5", " "},
  {"help.body.orbs_blocked_6", "\n\n"},
  {"help.body.orbs_unresolved_1", " "},
  {"help.body.orbs_unresolved_2", "\n\n"},
  {"help.body.orbs_manual_confirm", "\n\n"},
  {"help.body.orbs_reloading_1", " "},
  {"help.body.orbs_reloading_2", "\n\n"},
  {"help.body.orbs_continue_exit_1", " "},
  {"help.body.orbs_continue_exit_2", " "},
  {"help.body.orbs_continue_exit_3", " "},
  {"help.body.orbs_continue_exit_4", nil},
 },
 troubleshooting = {
  {"help.body.troubleshooting_first", "\n\n"},
  {"help.body.troubleshooting_report_steps_1", "\n"},
  {"help.body.troubleshooting_report_steps_2", "\n\n"},
  {"help.body.troubleshooting_report_file", "\n\n"},
  {"help.body.troubleshooting_reporting_fails", "\n\n"},
  {"help.body.troubleshooting_loading", "\n\n"},
  {"help.body.troubleshooting_turning_off_1", " "},
  {"help.body.troubleshooting_turning_off_2", "\n\n"},
  {"help.body.troubleshooting_commands_1", "\n"},
  {"help.body.troubleshooting_commands_2", "\n\n", {policy_command = "/nexus policy adaptive|released"}},
  {"help.body.troubleshooting_roll_record_1", " "},
  {"help.body.troubleshooting_roll_record_2", " "},
  {"help.body.troubleshooting_roll_record_3", "\n\n"},
  {"help.body.troubleshooting_diagnostics", "\n\n"},
  {"help.body.troubleshooting_updates", nil},
 },
 about = {
  {"help.body.about_engine", "\n\n"},
  {"help.body.about_dependency", "\n\n"},
  {"help.body.about_throttle", "\n\n"},
  {"help.body.about_advanced_commands_1", " "},
  {"help.body.about_advanced_commands_2", "\n\n"},
  {"help.body.about_prototype_command", "\n\n"},
  {"help.body.about_compatibility", nil},
 },
 faq = {
  {"help.label.faq_next_question", "\n"},
  {"help.body.faq_next_answer", "\n\n"},
  {"help.label.faq_which_wishlist_question", "\n"},
  {"help.body.faq_which_wishlist_answer", "\n\n"},
  {"help.label.faq_auto_question", "\n"},
  {"help.body.faq_auto_answer", "\n\n"},
  {"help.label.faq_auto_off_sync_question", "\n"},
  {"help.body.faq_auto_off_sync_answer", "\n\n"},
  {"help.label.faq_pause_hide_question", "\n"},
  {"help.body.faq_pause_hide_answer_1", " "},
  {"help.body.faq_pause_hide_answer_2", "\n\n"},
  {"help.label.faq_panel_size_question", "\n"},
  {"help.body.faq_panel_size_answer", "\n\n"},
  {"help.label.faq_get_back_question", "\n"},
  {"help.body.faq_get_back_answer", nil},
 },
}
H.PageBlocks=PAGE_BLOCKS
-- The shown text of a page: its blocks in the active language, or its whole
-- English text when the seam is absent or a block cannot be shown.
local function PageText(p)
    local blocks=PAGE_BLOCKS[p.id]
    local seam=Nexus.Localization
    if not blocks or type(seam)~="table" or type(seam.Text)~="function" or type(seam.Format)~="function" then
        return p.text
    end
    local out={}
    for _,b in ipairs(blocks) do
        local text,source
        if b[3] then text,source=seam.Format(b[1],b[3]) else text,source=seam.Text(b[1]) end
        if source=="unavailable" then return p.text end
        out[#out+1]=text
        if b[2] then out[#out+1]=b[2] end
    end
    return table.concat(out)
end
H.PageText=PageText
local function PageTitle(p) return T(p.titleKey,p.title) end
-- A question/answer page's text (groups apart by a blank line, the first
-- line of each the question) with every question in the heading gold
-- (|cffffd100, the panel's heading colour) and one more blank line between
-- groups. Answers keep the body's own colour. Display only.
function H.FormatQuestions(text)
    local out={}
    for block in (tostring(text or "").."\n\n"):gmatch("(.-)\n\n") do
        if block~="" then
            local q,a=block:match("^([^\n]*)\n(.*)$")
            if q then out[#out+1]="|cffffd100"..q.."|r\n"..a
            else out[#out+1]="|cffffd100"..block.."|r" end
        end
    end
    return table.concat(out,"\n\n\n")
end
-- A reference page's text as shown (v23, owner-approved readability like
-- Questions): the page's own localized title as a heading in the heading gold
-- (|cffffd100), a blank line, then the page's complete text in the body's own
-- white font. A catalog block can hold no "|", so every "|" in a page comes
-- from a code-owned command argument (as "/nexus policy adaptive|released");
-- it is written "||" here so the client shows it as typed instead of reading
-- "|r" as a colour reset. Display only: H.PageText stays the raw text.
function H.FormatReference(title, text)
    local body=(tostring(text or ""):gsub("|","||"))
    local head=(tostring(title or ""):gsub("|","||"))
    if head=="" then return body end
    return "|cffffd100"..head.."|r\n\n"..body
end
-- v28 r3 (native test.163033, one English session: H.PageText gave the Orbs
-- page as 8452 bytes and its formatted text as 8486 before SetText, but the
-- one body FontString stored 8189, so the tail and its final sentence were
-- lost at or after FontString:SetText; no general client byte limit is
-- claimed). The shown document is placed, unchanged, in a fixed pool of
-- FontStrings under the one scroll child (frame.parts; frame.body is part 1),
-- stacked in reading order. A page is split at its own line breaks (r4: a
-- line longer than PART_BUDGET also after a space or a whole token), so no
-- UTF-8 sequence, escaped pipe or colour code is cut (a colour still open at
-- a split is closed and reopened, display only), and
-- the parts joined with line breaks are the document. Nothing is shortened,
-- dropped or reworded, and no catalog or validation bound changes.
-- PART_BUDGET: the most bytes a part takes, 2 x the Localization template
-- result limit (MAX_TEMPLATE_RESULT_BYTES 2048), so the largest single block
-- result fits one part even with every '|' escaped; below the storage observed
-- natively (no general limit is claimed). r4: a single line longer than the
-- budget is cut into pieces within it (SplitLine), never stored whole.
local PART_BUDGET=4096
-- r4: the Auto page's "Auto right now" addition (refresh below): Help's heading
-- (one Localization text, at most MAX_TEXT_BYTES) and Panel.AutoDetailLines,
-- which returns at most 21 lines: its own 5 (ui/Panel.lua 9794-9800), the 14
-- of Readout.AutomationScopeLines at most (ui/Readout.lua 663-722: Auto,
-- paused-because, intro, ten permissions, read-only), then at most 2 (session
-- pause, unknown pause, or AutoNowLine, 9817-9833). Each line is one
-- Localization text or template result (at most MAX_TEMPLATE_RESULT_BYTES)
-- with at most a two-byte "- " prefix. Without the seam the addition fails
-- inside its pcall and is not shown.
local AUTO_NOW_MAX_LINES=21
local function AutoNowBound()
    local L=Nexus.Localization
    local resultMax=type(L)=="table" and tonumber(L.MAX_TEMPLATE_RESULT_BYTES) or nil
    local textMax=type(L)=="table" and tonumber(L.MAX_TEXT_BYTES) or nil
    if not (resultMax and textMax) then return 0 end
    return textMax+3+AUTO_NOW_MAX_LINES*(resultMax+3)
end
-- An upper bound of a page's shown bytes from the existing contracts
-- (core/Localization.lua): a plain block at most MAX_BLOCK_BYTES, a template
-- block at most MAX_TEMPLATE_RESULT_BYTES (x2 for escaped pipes), 16 bytes a
-- block for separators and FAQ/heading markup, and the title (at most
-- MAX_TEXT_BYTES, escaped) with its heading markup; or the English page text
-- with every '|' escaped, whichever is larger; plus the Auto page's addition.
local function DocumentBound(p)
    local L=Nexus.Localization
    local blockMax=type(L)=="table" and tonumber(L.MAX_BLOCK_BYTES) or nil
    local resultMax=type(L)=="table" and tonumber(L.MAX_TEMPLATE_RESULT_BYTES) or nil
    local textMax=type(L)=="table" and tonumber(L.MAX_TEXT_BYTES) or 0
    local bound=2*#p.text
    local blocks=PAGE_BLOCKS[p.id]
    if blocks and blockMax and resultMax then
        local sum=0
        for _,b in ipairs(blocks) do sum=sum+(b[3] and 2*resultMax or blockMax)+16 end
        if sum>bound then bound=sum end
    end
    bound=bound+2*math.max(#p.title,textMax)+14
    if p.id=="rolling" then bound=bound+AutoNowBound() end
    return bound
end
-- Parts the pool needs for the largest page: packing keeps any two
-- neighbouring parts above PART_BUDGET together, so at most
-- 2 x ceil(bound / PART_BUDGET) + 1. Made once, when the window is made.
local function DocumentPoolSize()
    local most=0
    for _,p in ipairs(pages) do most=math.max(most,DocumentBound(p)) end
    return 2*math.ceil(most/PART_BUDGET)+1
end
-- The colour code still open at the end of a part's text, or nil ('||' is a
-- shown pipe, never a code).
local function OpenColour(s)
    local open,i=nil,1
    while true do
        local a=s:find("|",i,true)
        if not a then return open end
        local c=s:sub(a+1,a+1)
        if c=="|" then i=a+2
        elseif c=="c" and s:sub(a+2,a+9):match("^%x%x%x%x%x%x%x%x$") then open=s:sub(a,a+9);i=a+10
        elseif c=="r" then open=nil;i=a+2
        else i=a+1 end
    end
end
-- r4: a line longer than the budget as pieces of at most budget bytes, cut
-- after the last space within it, else after the last whole token: never
-- inside a UTF-8 sequence, an escaped '||', a '|r' or a '|c' colour code.
-- The pieces concatenated are the line. (No current contract line comes
-- near: the longest paragraph bound is six blocks, 6149 bytes, and the
-- current English paragraphs are about 2,000 bytes or less.)
local function SplitLine(line,budget)
    local pieces={}
    while #line>budget do
        local i,lastSafe,lastSpace=1,0,0
        while i<=#line do
            local c=line:byte(i)
            local step=1
            if c==124 then
                local n=line:sub(i+1,i+1)
                if n=="|" or n=="r" then step=2
                elseif n=="c" and line:sub(i+2,i+9):match("^%x%x%x%x%x%x%x%x$") then step=10 end
            elseif c>=240 then step=4
            elseif c>=224 then step=3
            elseif c>=192 then step=2 end
            if i+step-1>budget then break end
            i=i+step;lastSafe=i-1
            if c==32 then lastSpace=lastSafe end
        end
        local cut=lastSpace>0 and lastSpace or lastSafe
        if cut<1 then cut=budget end
        pieces[#pieces+1]=line:sub(1,cut);line=line:sub(cut+1)
    end
    pieces[#pieces+1]=line
    return pieces
end
-- The document as parts, in order, each at most budget bytes (plus a colour
-- close/reopen at a split). Whole lines are packed; an over-budget line's
-- pieces each start a part. table.concat(parts,"\n") is the text, except that
-- a line cut into pieces has a part boundary instead of no break. r4: there is
-- no part limit here, so nothing is ever merged into an over-long last part.
local function SplitDocument(text,budget)
    local parts,cur,len={},{},0
    local function flush() parts[#parts+1]=table.concat(cur,"\n");cur,len={},0 end
    local function add(line)
        local more=(#cur>0 and 1 or 0)+#line
        if #cur>0 and len+more>budget then flush();more=#line end
        cur[#cur+1]=line;len=len+more
    end
    for line in (tostring(text or "").."\n"):gmatch("(.-)\n") do
        if #line<=budget then add(line)
        else
            for k,piece in ipairs(SplitLine(line,budget)) do
                if k>1 then flush() end
                add(piece)
            end
        end
    end
    flush()
    for i=1,#parts-1 do
        local open=OpenColour(parts[i])
        if open then parts[i]=parts[i].."|r";parts[i+1]=open..parts[i+1] end
    end
    return parts
end
-- One document part: like the body, under the content frame, standing under
-- the part before it, hidden until used.
local function NewPart(i)
    local fs=frame.content:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    fs:SetPoint("TOPLEFT",frame.parts[i-1],"BOTTOMLEFT",0,0)
    fs:SetWidth(585);fs:SetJustifyH("LEFT");fs:SetJustifyV("TOP");fs:SetWordWrap(true)
    fs:Hide()
    frame.parts[i]=fs
    return fs
end
-- Short task topics (the full-UI design's Help: Getting started, Wishlists vs
-- Saved Builds, Auto, Sync, Orbs, Support), one per page: a few lines and one
-- Open action to the real screen (H.OpenTopic). Each page's text stays below
-- its topic as the complete reference, with every warning, permission and
-- recovery step. Opening a screen assigns, spends, sends and turns on nothing.
local topics={
 start={title="Getting started",titleKey="help.heading.topic_start",open="Open Setup guide",openKey="help.button.topic_start",
  lineKeys={"help.body.topic_start_1","help.body.topic_start_2"},route=function() return H.OpenGuide() end,lines={
  "Setup guide takes you one step at a time: choose a Wishlist, pick the Saved Build that follows it, assign it, then read a recommendation.",
  "Opening, moving through or closing the guide assigns, spends, sends and turns on nothing. Skipped, unknown and unconfirmed steps are never counted as done."}},
 wishlists={title="Wishlists vs Saved Builds",titleKey="help.heading.topic_wishlists",open="Open Wishlist Editor",openKey="help.button.topic_wishlists",
  lineKeys={"help.body.topic_wishlists_1","help.body.topic_wishlists_2"},route=function() return H.OpenEditor() end,lines={
  "A Wishlist is the plan: the Echoes you want. A Saved Build is a server slot the game loads; each one follows one Wishlist.",
  "Create or import a Wishlist in the editor. A draft is kept only when you save it there, and assigning by itself changes no Saved Build."}},
 rolling={title="Auto",titleKey="help.heading.topic_rolling",open="Open Automation settings",openKey="help.button.topic_rolling",
  lineKeys={"help.body.topic_rolling_1","help.body.topic_rolling_2"},route=function() return H.OpenSettings("automation") end,lines={
  "Auto OFF: Nexus only recommends. Auto ON: it may Take, Banish, Reroll and Freeze for you, and may replace your active Saved Build with a better finished run.",
  "Auto starts OFF each session. Turn it ON only with the Auto button on the Nexus panel, after its warning. Automation settings shows each permission."}},
 sharing={title="Sync",titleKey="help.heading.topic_sharing",open="Open Sync settings",openKey="help.button.topic_sharing",
  lineKeys={"help.body.topic_sharing_1","help.body.topic_sharing_2"},route=function() return H.OpenSettings("sync") end,lines={
  "Your Sync mode decides what Nexus may send: Automatic may send without a click, Manual sends only what you start, Off sends nothing.",
  "Sharing a build is always its own confirmed action. Sent is not delivered, and a shared build cannot be recalled."}},
 orbs={title="Orbs",titleKey="help.heading.topic_orbs",open="Open Orbs / Lost Memories",openKey="help.button.topic_orbs",
  lineKeys={"help.body.topic_orbs_1","help.body.topic_orbs_2"},route=function() return H.OpenOrbs() end,lines={
  "Orb mode refines rolled Echoes toward the assigned Wishlist, one Orb per replacement, within the maximum you approve with Start.",
  "Opening the window, Help and Max spend nothing. Closing the window does not stop a run: use Pause or Stop."}},
 troubleshooting={title="Support",titleKey="help.heading.topic_troubleshooting",open="Open Support report",openKey="help.button.topic_troubleshooting",
  lineKeys={"help.body.topic_troubleshooting_1","help.body.topic_troubleshooting_2"},route=function() return H.OpenSupport() end,lines={
  "Something wrong? Type /nexus report before any reload, then Copy summary. Do not reload, reset or clear data to recreate it.",
  "Prepare report file keeps the report on this computer; send that file privately, never in public. Nothing is uploaded."}},
 faq={title="Questions",titleKey="help.heading.topic_faq",open="Open Setup guide",openKey="help.button.topic_faq",
  lineKeys={"help.body.topic_faq_1","help.body.topic_faq_2"},route=function() return H.OpenGuide() end,lines={
  "Short answers to common questions: what to do next, which Wishlist is used, Auto, Sync, pausing or hiding.",
  "Reading this page changes nothing. Close or Escape takes you back."}},
 about={title="About Nexus",titleKey="help.heading.topic_about",open="Open Log viewer",openKey="help.button.topic_about",
  lineKeys={"help.body.topic_about_1","help.body.topic_about_2"},route=function() return H.OpenLogs() end,lines={
  "Where the rolling engine comes from, compatibility notes and the advanced commands.",
  "Advanced commands are troubleshooting tools, not generic fixes. Opening the Log viewer shows what Nexus recorded and changes nothing by itself."}},
}
H.Topics=topics
local REFERENCE="Reference: every detail, warning and recovery step for this topic (scroll)."
local REFERENCE_KEY="help.label.reference_note"
-- Short labels of the direct page buttons, by page id.
local TAB_LABELS={start="Start",wishlists="Wishlists",rolling="Auto",sharing="Sharing",orbs="Orbs",
 troubleshooting="Problems",about="About",faq="FAQ"}
local TAB_KEYS={start="help.tab.start",wishlists="help.tab.wishlists",rolling="help.tab.rolling",
 sharing="help.tab.sharing",orbs="help.tab.orbs",troubleshooting="help.tab.troubleshooting",
 about="help.tab.about",faq="help.tab.faq"}
-- The topic card above the reference: its title and Open action on one row,
-- its lines under them (wrapped to the text they need at the current font),
-- then the Reference label and the scrolling page text below the card.
-- Owner-approved usability item 11 (2026-10-30): the page tabs are a strip
-- (a line under them; the current page's tab carries the Theme's selected
-- mark and stays the disabled one), and the buttons that open another window
-- stand apart below it under their own heading. Labels, routes and deep links
-- are unchanged. The card starts 20 px lower to make that room.
local TABS_TOP,TAB_RULE,WINDOWS_LABEL,WINDOWS_TOP,NOTE_TOP=-44,-67,-71,-89,-114
local TOPIC_TOP,REFERENCE_BOTTOM,REFERENCE_MIN=-130,-485,120
-- The lines may grow until the reference keeps its minimum scroll height
-- above the bottom buttons; beyond that the card keeps its whole text on hover.
local TOPIC_TEXT_MAX=(TOPIC_TOP-60)-REFERENCE_BOTTOM-REFERENCE_MIN
-- The client's wrapped height, never below the conservative text model at the
-- current font scale (as the guided setup coach measures its rows): one
-- reading of GetStringHeight is not trusted to have wrapped yet.
local function topicHeight(fs,text,width)
    local metrics=Nexus.LayoutMetrics
    if not (metrics and metrics.WrapHeight) then fs:SetSize(width,56);return 56 end
    local h=metrics.WrapHeight(fs,width,28)
    if metrics.TextRows and metrics.ConservativeText then
        local scale=metrics.RuntimeMetrics and metrics.RuntimeMetrics() or 1
        local _,line=metrics.ConservativeText(scale)
        h=math.max(h,metrics.TextRows(text,width,scale)*line)
    end
    h=math.min(math.ceil(h),TOPIC_TEXT_MAX)
    fs:SetHeight(h)
    return h
end
local function layoutTopic(p)
    local t=topics[p.id] or {}
    local metrics=Nexus.LayoutMetrics
    frame.topicOpen:SetText(t.open and T(t.openKey,t.open) or "")
    local bw=200
    if metrics and metrics.FitButtonWidth then bw=metrics.FitButtonWidth(frame.topicOpen,150,300) or bw
    else frame.topicOpen:SetWidth(bw) end
    -- One action for every topic, always shown (no hidden Help control).
    if t.route then frame.topicOpen:Enable() else frame.topicOpen:Disable() end
    frame.topicOpen:ClearAllPoints();frame.topicOpen:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-25,TOPIC_TOP-4)
    frame.topicTitle:SetText(t.title and T(t.titleKey,t.title) or PageTitle(p))
    frame.topicTitle:ClearAllPoints();frame.topicTitle:SetPoint("TOPLEFT",frame,"TOPLEFT",28,TOPIC_TOP-8)
    frame.topicTitle:SetSize(math.max(120,600-bw-12),16)
    local shown={}
    for i,line in ipairs(t.lines or {}) do shown[i]=T(t.lineKeys and t.lineKeys[i],line) end
    local lines=table.concat(shown,"\n")
    frame.topicText:SetText(lines)
    frame.topicText:ClearAllPoints();frame.topicText:SetPoint("TOPLEFT",frame,"TOPLEFT",28,TOPIC_TOP-32)
    local th=topicHeight(frame.topicText,lines,600)
    local bottom=TOPIC_TOP-32-th-6
    frame.topicFill:ClearAllPoints();frame.topicFill:SetPoint("TOPLEFT",frame,"TOPLEFT",20,TOPIC_TOP)
    frame.topicFill:SetSize(615,TOPIC_TOP-bottom)
    frame.reference:ClearAllPoints();frame.reference:SetPoint("TOPLEFT",frame,"TOPLEFT",20,bottom-5)
    frame.reference:SetSize(615,13)
    local top=bottom-22
    frame.scroll:ClearAllPoints();frame.scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",20,top)
    frame.scroll:SetSize(595,math.max(REFERENCE_MIN,top-REFERENCE_BOTTOM))
end
local function refresh()
    -- The manual is named Reference everywhere (Help is the guided coach).
    local p=pages[index]
    frame.title:SetText(TF("help.title.window",function() return {page=PageTitle(p)} end,"Nexus Reference - "..p.title))
    -- Issue #169: the Auto page adds what Auto may do now (Panel
    -- .AutoDetailLines, from the last committed model and saved settings),
    -- below the complete reference. Reading it changes nothing.
    local text=PageText(p)
    -- Questions (FAQ), owner-approved readability (issue #169): each group's
    -- first line is its question, drawn in the Nexus heading gold; the answer
    -- keeps the white body font, and the groups are one more blank line
    -- apart. The wording is unchanged and the height is measured below.
    -- Every other page opens with its own title in the same gold (v23,
    -- H.FormatReference); its complete text and every command are unchanged.
    if p.id=="faq" then text=H.FormatQuestions(text)
    else text=H.FormatReference(PageTitle(p),text) end
    local panel=Nexus.Panel
    if p.id=="rolling" and panel and type(panel.AutoDetailLines)=="function" then
        local ok,lines=pcall(panel.AutoDetailLines)
        if ok and type(lines)=="table" and #lines>0 then
            text=text.."\n\n"..T("help.heading.auto_now","Auto right now (read when this page opened):").."\n"
                ..table.concat(lines,"\n")
        end
    end
    -- v28 r3: the document goes into the part pool (see SplitDocument);
    -- unused parts are emptied and hidden, so a shorter page leaves no text.
    -- r4: a document within the contracts never needs more parts than the
    -- pool made in ensure(). One that does (outside the known contracts)
    -- still reaches whole FontStrings: the pool grows to what it needs, once,
    -- and is reused (bounded by that document; recorded in
    -- frame.documentBeyondContract), instead of anything being cut or merged.
    local docParts=SplitDocument(text,PART_BUDGET)
    if #docParts>#frame.parts then
        frame.documentBeyondContract=#docParts
        for i=#frame.parts+1,#docParts do NewPart(i) end
    end
    local shownParts=0
    for i,fs in ipairs(frame.parts) do
        local s=docParts[i]
        if s then fs:SetText(s);fs:Show();shownParts=i else fs:SetText("");fs:Hide() end
    end
    frame.page:SetText(TF("help.label.page_position",function(seam)
        return {page=seam.Count(index),total=seam.Count(#pages)} end,"Page "..index.." / "..#pages))
    layoutTopic(p)
    -- The current page's button is the disabled one and carries the selected
    -- mark (item 11; Theme repaints it with the palette); a page change
    -- clears an earlier route note.
    local theme=Nexus.Theme
    for i,t in ipairs(frame.tabs or {}) do
        if i==index then t:Disable() else t:Enable() end
        if theme and theme.SetSelected then theme.SetSelected(t,i==index) end
    end
    if frame.note and frame.noteIndex~=index then frame.note:SetText("");frame.noteIndex=nil end
    if frame.content then
        -- v28: a design caution kept from the topic card (topicHeight), not
        -- the remedy for the stored-text loss above: one reading of
        -- GetStringHeight is not trusted to have wrapped yet, so each shown
        -- part is never below the conservative text model of the text it
        -- stores, at its width. The text is unchanged; a larger model only
        -- adds space below it. The parts stack; the document is at least 414.
        local metrics=Nexus.LayoutMetrics
        local scale,rowLine=1,nil
        if metrics and metrics.TextRows and metrics.ConservativeText then
            scale=metrics.RuntimeMetrics and metrics.RuntimeMetrics() or 1
            local _,l=metrics.ConservativeText(scale)
            rowLine=l
        end
        local total,last=0,nil
        for i=1,shownParts do
            local fs=frame.parts[i]
            fs:SetHeight(0)
            local ok,measured=pcall(fs.GetStringHeight,fs)
            measured=ok and tonumber(measured) or 0
            if measured~=measured or measured<0 or measured==math.huge then measured=0 end
            if rowLine then
                local width=tonumber(fs:GetWidth()) or 585
                measured=math.max(measured,metrics.TextRows(fs:GetText() or "",width,scale)*rowLine)
            end
            local h=math.ceil(measured)
            fs:SetHeight(h);total=total+h;last=fs
        end
        if last and total<414 then last:SetHeight(last:GetHeight()+414-total);total=414 end
        frame.content:SetHeight(math.max(414,total)+24)
    end
    -- v26 (native X1): while the game's "Select an Echo" control is shown in
    -- this strata above the Reference, its own frames are laid out over it
    -- (LayoutMetrics.LiftOwned; levels only, read again on each page).
    local metrics=Nexus.LayoutMetrics
    if frame:IsShown() and metrics and type(metrics.LiftOwned)=="function" then pcall(metrics.LiftOwned,frame) end
end
local function ensure()
    if frame then return end
    frame=CreateFrame("Frame","NexusHelpWindow",UIParent);frame:SetSize(660,540);frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    -- The earlier high-level Help layout rendered its parent at 129 above
    -- children at 128. Keep this band low and every child above its backdrop.
    frame:SetFrameStrata("DIALOG");frame:SetFrameLevel(HELP_LEVEL);frame:EnableMouse(true);frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton");frame:SetScript("OnDragStart",function(self)self:StartMoving()end)
    frame:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(.035,.04,.05,1)
    frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");frame.title:SetPoint("TOPLEFT",20,-20)
    local scroll=CreateFrame("ScrollFrame","NexusHelpScroll",frame,"UIPanelScrollFrameTemplate")
    -- Below the page buttons, the setup row, its one-line route note and the
    -- page's topic card (layoutTopic places it under the card).
    scroll:SetPoint("TOPLEFT",20,TOPIC_TOP-108);scroll:SetSize(595,267)
    scroll:SetFrameLevel(HELP_LEVEL+1);frame.scroll=scroll
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(590,650);scroll:SetScrollChild(child);frame.content=child
    child:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,0);child:SetFrameLevel(HELP_LEVEL+2)
    frame.body=child:CreateFontString(nil,"OVERLAY","GameFontHighlight");frame.body:SetPoint("TOPLEFT",0,0)
    frame.body:SetWidth(585);frame.body:SetJustifyH("LEFT");frame.body:SetJustifyV("TOP");frame.body:SetWordWrap(true)
    -- v28 r3: the document part pool, made once (frame.body is part 1); each
    -- further part is like the body and stands under the one before it.
    frame.parts={frame.body}
    for i=2,DocumentPoolSize() do NewPart(i) end
    local function b(x,w,label,fn)
        local f=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");f:SetPoint("BOTTOMLEFT",x,20);f:SetSize(w,25);f:SetText(label)
        f:SetFrameLevel(HELP_LEVEL+2)
        f:SetScript("OnClick",function()fn();scroll:SetVerticalScroll(0)end);return f
    end
    b(20,90,T("help.button.previous","Previous"),function()index=math.max(1,index-1);refresh()end)
    b(118,90,T("help.button.next","Next"),function()index=math.min(#pages,index+1);refresh()end)
    b(430,95,T("help.button.start_page","Start page"),function()index=1;refresh()end)
    b(533,100,T("help.button.close","Close"),function()frame:Hide()end)
    frame.page=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall");frame.page:SetPoint("BOTTOM",0,26)
    -- Direct page buttons: any page in one click (deep links use H.Show(id)).
    frame.tabs={}
    -- 83 px apart while every page fits (seven pages); narrower for more.
    local step=83
    if 20+(#pages-1)*step+79>640 then step=math.floor(620/#pages) end
    for i,p in ipairs(pages) do
        local t=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
        t:SetPoint("TOPLEFT",20+(i-1)*step,TABS_TOP);t:SetSize(step-4,20);t:SetText(TAB_LABELS[p.id] and T(TAB_KEYS[p.id],TAB_LABELS[p.id]) or PageTitle(p))
        t:SetFrameLevel(HELP_LEVEL+2)
        t:SetScript("OnClick",function()index=i;refresh();scroll:SetVerticalScroll(0)end)
        frame.tabs[i]=t
    end
    -- The tab strip's line, just under the page tabs (item 11).
    frame.tabRule=frame:CreateTexture(nil,"ARTWORK");frame.tabRule:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.tabRule:SetVertexColor(.82,.62,.24,.7)
    frame.tabRule:SetPoint("TOPLEFT",frame,"TOPLEFT",20,TAB_RULE);frame.tabRule:SetSize(615,1)
    -- The window buttons' own heading, in the gold small heading font: these
    -- open another window, unlike the page tabs above.
    frame.windowsLabel=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    frame.windowsLabel:SetPoint("TOPLEFT",frame,"TOPLEFT",20,WINDOWS_LABEL);frame.windowsLabel:SetSize(615,16)
    frame.windowsLabel:SetJustifyH("LEFT");frame.windowsLabel:SetText(T("help.heading.open_window","Open another window:"))
    -- The primary setup path. Each button only navigates (H.OpenGuide: Setup /
    -- Welcome opens or resumes Guided setup; H.OpenAssignment, H.OpenEditor,
    -- H.OpenChecklist); none assigns, spends, sends or turns Auto ON, and a
    -- route that cannot open says why in the note below.
    local function action(x,w,label,fn)
        local f=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");f:SetPoint("TOPLEFT",x,WINDOWS_TOP);f:SetSize(w,22)
        f:SetText(label);f:SetFrameLevel(HELP_LEVEL+2);f:SetScript("OnClick",fn);return f
    end
    action(20,150,T("help.button.setup_welcome","Setup / Welcome"),function()H.OpenGuide()end)
    action(176,160,T("help.button.assign_wishlist","Assign Wishlist..."),function()H.OpenAssignment()end)
    action(342,140,T("help.button.wishlist_editor","Wishlist Editor"),function()H.OpenEditor()end)
    frame.checklist=action(488,140,T("help.button.setup_checklist","Setup checklist"),function()H.OpenChecklist()end)
    frame.note=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");frame.note:SetPoint("TOPLEFT",20,NOTE_TOP)
    frame.note:SetSize(615,13);frame.note:SetJustifyH("LEFT");frame.note:SetText("")
    -- The page's topic card (topics above): its title, lines and one Open
    -- action (H.OpenTopic), made once; layoutTopic fills and places it. The
    -- one action serves every page, so no Help control is ever left hidden.
    frame.topicFill=frame:CreateTexture(nil,"BORDER");frame.topicFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.topicFill:SetVertexColor(.09,.1,.14,.85)
    frame.topicTitle=frame:CreateFontString(nil,"OVERLAY","GameFontNormal");frame.topicTitle:SetJustifyH("LEFT")
    frame.topicText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.topicText:SetJustifyH("LEFT");frame.topicText:SetJustifyV("TOP");frame.topicText:SetWordWrap(true)
    -- At the largest text a capped card keeps its whole lines on hover.
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.FullTextTooltip then
        frame.topicHit=Nexus.LayoutMetrics.FullTextTooltip(frame.topicText,frame)
    end
    frame.topicOpen=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");frame.topicOpen:SetSize(200,22)
    frame.topicOpen:SetFrameLevel(HELP_LEVEL+2)
    frame.topicOpen:SetScript("OnClick",function() H.OpenTopic(pages[index].id) end)
    frame.reference=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    frame.reference:SetJustifyH("LEFT");frame.reference:SetText(T(REFERENCE_KEY,REFERENCE))
    -- Register the completed window once, including its owned navigation
    -- controls. Palette changes then repaint the same frame through Theme.
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame,0.94) end
    if Nexus.Theme and Nexus.Theme.StyleTree then Nexus.Theme.StyleTree(frame) end
    frame:HookScript("OnHide",function()
        -- v26: a lifted Reference takes its own default levels back first.
        local metrics=Nexus.LayoutMetrics
        if metrics and type(metrics.RestoreOwned)=="function" then pcall(metrics.RestoreOwned,frame) end
        local back=returnTo;returnTo=nil
        if back then pcall(back) end
    end)
    frame:Hide();UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusHelpWindow"
end
-- onReturn (optional): see returnTo above. Without it a pending return stays.
function H.Show(id,onReturn)
    ensure();if id then for i,p in ipairs(pages) do if p.id==id then index=i end end end
    if type(onReturn)=="function" then returnTo=onReturn end
    frame:Show();refresh();return frame
end
function H.Hide()if frame then frame:Hide()end end

-- Setup routes of the Help window. While local start-up is not ready, the
-- routes that need it say so and open nothing; Help itself stays available
-- during loading. No route assigns, spends, sends or turns Auto ON.
local function LocalToolsReady()
    if type(Nexus.StartupStatus)~="function" then return false end
    local ok,s=pcall(Nexus.StartupStatus)
    return ok and type(s)=="table" and s.coreReady==true
end
-- The reason is also returned, so a caller window can show it itself.
local function Refuse(text)
    if frame and frame.note then frame.note:SetText("|cffffd200"..text.."|r");frame.noteIndex=index end
    print("|cffffd200Nexus:|r "..text)
    return false, text
end
-- A route that opened its window takes Help's place (see returnTo).
local function Leave()
    returnTo=nil
    if frame then frame:Hide() end
end
-- The informational replay (QuickStart.ShowSetup): a secondary route kept for
-- its existing callers. Help's own Setup / Welcome button opens Guided setup
-- (H.OpenGuide).
function H.OpenSetup()
    local quick=Nexus.QuickStart
    if not (quick and type(quick.ShowSetup)=="function") then
        return Refuse(T("help.error.setup_unavailable_yet","Setup / Welcome is not available yet."))
    end
    local shown,why=quick.ShowSetup()
    if not shown then
        return Refuse(why=="warning-open"
            and T("help.error.setup_warning_open","Setup / Welcome did not open. Answer the open warning (Yes or No), then open it again.")
            or T("help.error.setup_unavailable_now","Setup / Welcome is not available right now."))
    end
    Leave()
    return true
end
-- Assign Wishlist...: the Echo Journal with its Wishlist chooser
-- (JournalTab.OpenBuilds(true)). Help closes first; the Wishlist editor too,
-- since the Journal is kept hidden while it is shown.
function H.OpenAssignment()
    if not LocalToolsReady() then
        return Refuse(T("help.error.assign_after_startup","Assign Wishlist opens after start-up finishes (see the loading panel). Nothing was opened or assigned."))
    end
    local journal=Nexus.JournalTab
    if not (journal and type(journal.OpenBuilds)=="function") then
        return Refuse(T("help.error.journal_route_unavailable","The Echo Journal route is not available. Nothing was assigned."))
    end
    if type(journal.CanOpenBuilds)=="function" and not journal.CanOpenBuilds() then
        return Refuse(T("help.error.progression_button_missing","The game's Character Progression button was not found. Nothing was opened or assigned."))
    end
    -- Use the same guarded route as the panel. A visible Plan may hold an
    -- unsaved draft or an open Save confirmation; Help must not hide it and
    -- bypass the workspace suspension check before opening the game page.
    local panel=Nexus.Panel
    if not (panel and type(panel.OpenAssignment)=="function") then
        return Refuse(T("help.error.assignment_route_unavailable","The guarded assignment route is not available. Nothing was opened or assigned."))
    end
    if panel.OpenAssignment()==false then return false end
    Leave()
    return true
end
-- Setup checklist: the read-only checklist and status (QuickStart). It reads
-- current facts only and is available during loading, where it says what is
-- not known yet.
function H.OpenChecklist()
    local quick=Nexus.QuickStart
    if not (quick and type(quick.ShowChecklist)=="function") then
        return Refuse(T("help.error.checklist_unavailable","The setup checklist is not available."))
    end
    Leave()
    quick.ShowChecklist()
    return true
end
-- Guided setup: the step-by-step coach (ui/GuidedSetup.lua), Help's primary
-- Setup / Welcome. It does not open over a warning that waits for its answer
-- and says so; nothing is queued, so it opens only when asked again. Opening
-- it changes nothing.
function H.OpenGuide()
    local ui=Nexus.GuidedSetupUI
    if not (ui and type(ui.Show)=="function") then
        return Refuse(T("help.error.guide_unavailable","Guided setup is not available."))
    end
    local shown,why=ui.Show()
    if not shown then
        return Refuse(why=="warning-open"
            and T("help.error.guide_warning_open","Guided setup did not open. Answer the open warning, then open Guided setup again.")
            or T("help.error.guide_unavailable_now","Guided setup is not available right now."))
    end
    Leave()
    return true
end
-- A Nexus window's own Help button (native QA test.163008; design/current
-- "Nexus Setup Alternative": Help opens the coach, the manual is Reference on
-- request). Help is the guided setup coach at its current step (H.OpenGuide).
-- When the coach cannot open (an Auto warning waits for its answer) it has
-- said why in chat, and nothing else opens: the manual is Reference, the
-- player's own separate choice, never a substitute for Help. The calling
-- window then stays as it is (its draft, popup or confirmation included), so
-- the player can answer the warning and press Help again. `leave` (optional)
-- hides the calling window, for a window whose layer is above the coach; it
-- runs only once the coach opened (and is told so). Opening the coach
-- assigns, saves, sends, spends and changes Auto nothing. Returns true when
-- the coach opened, else false and the reason.
function H.OpenHelp(page,leave)
    local opened,why=H.OpenGuide()
    if opened~=true then return false,why end
    if type(leave)=="function" then leave(true) end
    return true
end
-- A window's Reference button: the manual at that window's own page. `leave`
-- as for H.OpenHelp, run first, as the earlier contextual Help did.
function H.OpenReference(page,leave)
    if type(leave)=="function" then leave() end
    return H.Show(page)
end
-- Wishlist Editor: the editor as /nexus editor opens it.
function H.OpenEditor()
    if not LocalToolsReady() then
        return Refuse(T("help.error.editor_after_startup","The Wishlist Editor opens after start-up finishes (see the loading panel). Nothing was opened."))
    end
    local editor=Nexus.WishlistEditor
    if not (editor and type(editor.Show)=="function") then
        return Refuse(T("help.error.editor_unavailable","The Wishlist Editor is not available."))
    end
    -- Help can sit on top of an already-open Plan. Re-running Show() there
    -- starts a fresh editor session and discards unsaved Echo edits; simply
    -- reveal the existing frame instead.
    local plan=_G.NexusEditorFrame
    if plan and plan.IsShown and plan:IsShown() then
        Leave()
        return true
    end
    local opened=editor.Show()
    local editorFrame=_G.NexusEditorFrame
    if opened==false or not (editorFrame and editorFrame.IsShown and editorFrame:IsShown()) then
        return Refuse(T("help.error.editor_did_not_open","The Wishlist Editor did not open. Help remains here; try again after start-up finishes."))
    end
    Leave()
    return true
end
-- A topic's one Open action (topics above): the real screen for that topic,
-- through the same guarded route as elsewhere.
function H.OpenTopic(id)
    local t=topics[id]
    if not (t and type(t.route)=="function") then
        return Refuse(T("help.error.topic_no_screen","This topic has no screen to open. Nothing was opened."))
    end
    return t.route()
end
-- Automation or Sync settings (ui/SettingsWindow.lua): opening it changes no
-- preference; each change there is its own existing, guarded control.
function H.OpenSettings(section)
    -- One whole sentence per section and outcome (the section name is part
    -- of each translated sentence, never joined to it here).
    local sync=section=="sync"
    local label=sync and "Sync settings" or "Automation settings"
    if not LocalToolsReady() then
        return Refuse(T(sync and "help.error.sync_settings_after_startup" or "help.error.automation_settings_after_startup",
            label.." open after start-up finishes (see the loading panel). Nothing was opened or changed."))
    end
    local settings=Nexus.SettingsWindow
    if not (settings and type(settings.Show)=="function") then
        return Refuse(T(sync and "help.error.sync_settings_unavailable" or "help.error.automation_settings_unavailable",
            label.." are not available. Nothing was opened or changed."))
    end
    if settings.Show(section)==false then
        return Refuse(T(sync and "help.error.sync_settings_did_not_open" or "help.error.automation_settings_did_not_open",
            label.." did not open. Nothing was changed."))
    end
    Leave()
    return true
end
-- The Orb window, as /nexus orbs opens it (also during loading). Opening it
-- spends nothing and starts no run.
function H.OpenOrbs()
    local orb=Nexus.OrbPanel
    if not (orb and type(orb.Show)=="function") then
        return Refuse(T("help.error.orbs_unavailable","The Orb window is not available. Nothing was spent."))
    end
    if orb.Show()==false then return Refuse(T("help.error.orbs_did_not_open","The Orb window did not open. Nothing was spent.")) end
    Leave()
    return true
end
-- The support page, as /nexus report opens it (also during loading). It only
-- reads until you choose Copy summary or Prepare report file there.
function H.OpenSupport()
    local ui=Nexus.SupportReportUI
    if not (ui and type(ui.Show)=="function") then
        return Refuse(T("help.error.support_unavailable","The support report is not available. Type /nexus report."))
    end
    if ui.Show()==false then return Refuse(T("help.error.support_did_not_open","The support report did not open. Type /nexus report.")) end
    Leave()
    return true
end
-- The Log viewer, as /nexus log opens it after start-up.
function H.OpenLogs()
    if not LocalToolsReady() then
        return Refuse(T("help.error.logs_after_startup","The Log viewer opens after start-up finishes (see the loading panel). Nothing was opened."))
    end
    local logs=Nexus.LogViewer
    if not (logs and type(logs.Show)=="function") then return Refuse(T("help.error.logs_unavailable","The Log viewer is not available.")) end
    if logs.Show()==false then return Refuse(T("help.error.logs_did_not_open","The Log viewer did not open.")) end
    Leave()
    return true
end
