-- Reopenable read-only guide. Available before saved data or shared data is ready.
Nexus=Nexus or {}
local H={};Nexus.Help=H
local frame,index= nil,1
-- Keep the complete Help window above the Orb dialog's 30-33 layer band.
local HELP_LEVEL=40
local pages={
 {id="start",title="Getting started",text=[[This is an experimental build. Back up your Nexus folder and WTF with WoW closed before testing. Reading this guide never spends, assigns, activates, or sends a Sync request.

Before you turn Auto ON: With Auto ON, Nexus may replace that active Saved Build with a better finished run; at level 80 after a finished run, that can happen right after you turn Auto ON or change the assignment. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. It treats the slot as a working copy, not a protected archive. Keep Auto OFF if you want it left unchanged. Auto starts OFF each session.

1. Open the Wishlist Editor: click ... on the Nexus panel, then Wishlist Editor, or type /nexus editor. To use a Wishlist code, click Import and paste it. Import opens a draft.
2. Check exact qualities, copy counts and the planned locked Echo targets.
3. Click Create Wishlist for a new or imported plan. It saves the plan and makes it the target of the loadout shown in the editor. For an existing Wishlist, click Save Wishlist.
4. To target another Saved Build: in My Builds, select the intended Saved Build and assign the Wishlist to it (click the Wishlist selector and choose the Wishlist). Assigning only chooses the target; by itself it does not change the Saved Build.
5. Review the recommendations with Auto OFF first. Click Auto OFF only when you accept the warning above; it then shows Auto ON.

What Nexus is for: you choose the Echoes you want (a Wishlist). Nexus counts the exact copies still missing and recommends, or with Auto ON performs, Take, Banish, Reroll and Freeze on each Echo choice to work toward them.

Saving and loading Saved Builds: in the game's own build window, loading a Saved Build makes it your current loadout. Saving writes your current Echoes into the slot you selected and REPLACES what that slot held. Check the selected slot before you save; Nexus cannot undo a save or bring back the old contents. Nexus never loads a Saved Build for you. Its only save is the automatic save with Auto ON, described above. Creating or importing a Wishlist saves only a plan. Assigning a Wishlist by itself changes no Saved Build.

Words: A Wishlist is a desired plan, not proof that you own its Echoes. Saved Builds are server slots. Active Loadout is the selected server loadout. Nexus treats no future random Echo roll as guaranteed.]]},
 {id="wishlists",title="Wishlists and locked targets",text=[[Before you edit: a plan holds up to 79 rolled copies and 6 locked Echo copies (85 total). Counts are copies, not names or rows. Each quality is a different target; a lower-quality copy does not count for a higher-quality target.

1. Open the Wishlist Editor (/nexus editor). Import opens a draft; nothing is kept until you click Create Wishlist (new plan) or Save Wishlist (existing Wishlist).
2. If the editor asks for locked targets, choose them, then click Confirm locked targets & edit (or & assign). You do not need to own the plan already.
3. Create Wishlist saves a new plan and makes it the target of the loadout shown in the editor; Save Wishlist saves an existing one. In My Builds, the Wishlist selector chooses which Wishlist a Saved Build uses; Unassign Wishlist keeps the Wishlist.

Locked Echoes and targets: Currently locked Echoes are what you actually have. Locked Echo targets are what the plan wants. A Frozen offer is a temporary offered card kept by the game's Freeze action; it is not a locked Echo slot. Opening or confirming targets does not lock/unlock anything. Automatic locked-Echo slot changes require both Automation and their separate option, plus ownership and safety checks.

Imports without locked markers use your matching currently locked Echoes by default if that makes a valid 79+6 split. Existing confirmed plans are unchanged.
/nexus currentlocks off: choose future untagged plans manually.
/nexus currentlocks on: use matching locked targets by default.
Nexus-only locked-role markers should be imported in Nexus, not assumed compatible with every native importer.]]},
 {id="rolling",title="Auto, rolling and saving",text=[[Before you turn Auto ON, read this. Automatic save is separate from Take, Banish, Reroll and Freeze. After a completed run, Auto may replace your active Saved Build with that run and give it the Wishlist's name. Nexus compares the run with the Wishlist assigned to that loadout. It replaces an existing Saved Build only when overall Wishlist progress is higher than the Saved Build's, or equal with cleanup (some extra copies removed, or an even swap of requested copies). Not every run is saved. Assigning by itself changes nothing, but at level 80 after a finished run, turning Auto ON or changing the assigned Wishlist makes Nexus check again right away, so a replacement can follow within seconds. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. There is no separate automatic-save switch: Auto OFF stops it.

Better means Wishlist progress, not Orb investment or keeping every individual Echo. Example: a run that loses 1 requested copy but gains 3 other requested copies is +2 overall. It can replace the Saved Build even when the lost Echo is one you value or obtained with Orbs. The save itself spends no Orbs, and it does not mean that Echo was judged worthless. Nexus cannot undo a completed save or bring back that Echo or the Orbs spent on it; Unassign does not restore a Saved Build. Keep Auto OFF if you want the current Saved Build left untouched. Auto starts OFF each session.

1. Click Auto OFF on the Nexus panel to turn Auto ON. Auto is a permission for your enabled automatic actions. Auto OFF does not turn Nexus off, stop build sharing, or hide the panel.
2. Choose actions: /nexus reroll on|off and /nexus freeze on|off. They change those permissions, not the Auto button. Each one only allows or forbids that action; it does not choose another strategy. When an action is off, Nexus skips that step and uses the next rule below.
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

When it is blocked: "Waiting for the game to confirm the last Echo action." means an action was sent and has no confirmed result yet. Do not choose again or reload; wait. "No Echo choice is showing." means only that no choice is on screen now. It does not mean the run is finished, and it is not a reason to retry. "Auto ON — paused" means Auto stays ON but is not acting; point at the ... button to see the reason in its Status line. Waiting for current Echo data means automatic choices wait for ownership confirmation; it is not Sync status. Ordinary rolling stays paused during active or unknown Orb offers.]]},
 {id="sharing",title="Shared builds and DPS",text=[[1. Click Build Library on the Nexus panel. Use the scope button to switch between All Shared and My Builds.
2. Require both DPS records: when checked, only builds with both a Training Dummy and a Lich King record that this client holds are listed. When unchecked, that requirement is off; other filters still apply. A record shows what this client holds. It is not build quality, outside verification, or finished Sync. While a filter change is applied, the list says Updating results...
3. Copy into Editor creates a draft; it does not activate or spend. Share Build sends a listing to other users; it is separate from saving a Wishlist or a server Saved Build.

Removing: Stop Sharing, an administrator removing a shared record, and deleting from My Builds are different actions. Read each confirmation. Stop Sharing removes the listing here; removal on other clients is not confirmed. Removing a shared listing does not delete your server build or Wishlist.

Names: a name shows the player and realm the record states. It is not proof of identity. When a record's owner is not established, its details say "Owner identity not established." Two different records can show the same name.

Locked targets on shared builds: players on this version receive a build's locked targets when both sides support them. Older versions receive the ordinary targets only; your Share status counts those answers. For a build from an older version, Nexus treats its locked targets as unknown, not as none; no locked row is shown. A received build is not always ready to copy. Sent does not prove that another player stored it.

Leaderboard: Training Dummy, Lich King and Both records tabs. Both records ranks by the highest single result; an average is display-only. DPS capture needs Details! and its supported events.

Sync Now asks for shared builds and records. Preparing, request sent, receiving updates, and finished are distinct. Do not flood the sharing network or send test traffic.]]},
 {id="orbs",title="Orbs / Lost Memories",text=[[Before you start: Orb mode refines existing rolled Echoes toward the assigned Wishlist. It uses one Orb per replacement, then waits for the actual offer and the confirmed result. It cannot create, reorder, or replace locked Echo slots, and it stops when rolled targets are complete. Opening the window, Open Orbs..., Help and Max spend nothing.

1. Open /nexus orbs, Orbs / Lost Memories in the ... menu, or Open Orbs... on the Nexus panel (shown with Orb guidance). Check the assigned Wishlist, missing rolled copies and the confirmed Orb balance. Loading or unavailable data is not a zero balance.
2. Set the maximum. Until you type an amount, it follows your confirmed Orb balance, up to 1000. Typing an amount stops that; Max returns to following the balance. A typed amount must be a whole number from 1 to 10,000. A maximum saved by an earlier version is kept.
3. Click Start. Start approves the maximum shown and automatic use of eligible surplus copies, including safe recycling. Starting disables ordinary Automation; it does not automatically re-enable it. Locked and required copies stay protected. The approved maximum does not change during the run.
4. Watch the run. It continues after each confirmed result and stops at target completion, the maximum, insufficient balance, no safe source, or uncertainty.

The game's auto-accept and other addons' pickers must be off. If the game has no Orb service, only Orb mode is unavailable and ordinary rolling still works. If the Orb service exists but Nexus cannot read its state, ordinary rolling waits too. Login, reconnect, new resources or reload never restart spending.

Closing the window does not stop an approved run. Use Pause or Stop. The main Nexus panel keeps compact progress and Pause/Resume/Stop.

After a finished run: click Start new run, review the maximum, then click Confirm new run. If the maximum changes, review it and press Start new run again.

When it is blocked: Pause/Stop prevents new submissions, not a spend already accepted; a pending result may still settle. Changing the active loadout, assignment or targets pauses new actions; Resume adopts the new target and keeps the same maximum. Advanced has optional exclusions and Recheck. Recheck only asks for balance and ownership data; it is not a replay or a fix.

Unresolved result: an Orb action without a confirmed result keeps its spending exposure and blocks new Orb runs and ordinary rolling. Relogging, reloading, changing builds, returning to the old loadout, Resume or pressing controls again do not clear it. Recheck can request the confirming data; pressing it does not clear the record. Nexus never retries, refunds, or deletes it. Do not clear saved data.

Only one manual case can confirm it: after a reload, if that action's offer is still open in the game's offer window and matches the saved record, choose in that window. Nexus confirms the action only from the exact matching result. If Nexus had proposed an Echo, only that same Echo can be confirmed; the Orb window names it. If the action ended while Nexus could not observe it, it cannot be confirmed. No exit from that block exists yet.]]},
 {id="troubleshooting",title="Problems and bug reports",text=[[If something goes wrong: do not reload, relog, spend Orbs, reroll or change builds to recreate it. Do not clear logs or reset saved data.

Report a problem. No report/logs or requested details = your support request will be ignored until provided.
1. Type /nexus report when the problem happens, before any reload. Its incidents are kept for this session only.
2. Click Copy summary, click in the text, press Ctrl+A, then Ctrl+C, and paste it into your report.
3. Add your exact build (/nexus update shows it), what happened versus what you expected, and Auto ON or OFF. Provide any additional logs requested.

Report file (private): click Prepare report file and wait until it says the report is prepared. WoW writes the file only when you reload, log out or exit. /reload only when no action is active or pending. Then send this file privately; never post it publicly:
WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua
It is not the NexusSupport.lua inside your AddOns folder. Both Nexus and NexusSupport must be installed and enabled.

If reporting fails: if the window says "Not prepared", or logs are unavailable, say so and send what you have. Copy summary works without NexusSupport. You are not asked for logs that a broken reporting feature cannot create.

Loading: the loading panel shows the current step and elapsed time; a percentage is for that step only. /nexus loading reopens it. Gray Build Library/Leaderboard tabs mean shared views are not ready yet.

Turning things off: Hide Nexus Panel (... menu) or /nexus panel only hides the panel. Auto OFF only stops automatic actions. Neither turns Nexus off. To turn Nexus off, only when no action is active or pending: log out to character selection, click AddOns, untick Nexus, and log in again.

Commands:
/nexus help - this guide, also during loading
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

Updates: update notices come from release information shipped inside this package; the ... button then shows !. Another player's client can report a newer test build; Nexus shows that only as an UNVERIFIED hint. No notice does not mean your build is the latest. Nexus never downloads or installs.]]},
 {id="about",title="About and advanced details",text=[[Ordinary rolling and Orb decisions come from EchoWeaver, the rolling engine that Nexus maintains itself. Orb decisions use EchoWeaver's source, target and fallback rules with Nexus's exact-quality, locked-role, approval, budget and confirmation safeguards.

EchoWeaver has no runtime dependency on another addon. Source and reuse notices are in THIRD_PARTY.md. Neither algorithm is claimed mathematically optimal or universally safe without matching client evidence.

This prototype uses a compatible global ChatThrottleLib where available, otherwise its disclosed private compatibility scheduler. That is not complete official-library/native acceptance.

Advanced commands are troubleshooting tools, not generic fixes. Do not experiment with them to clear a loading message. flags reads active safety assumptions; undemote clears recorded temporary assumption disablements; anchor changes the existing Adaptive Power preference; restore restores the prior host auto-accept setting; err displays the latest recorded error. Advanced diagnostics keep raw reason codes and identifiers so support can tell failures apart.

/nexus prototype prints build/reference details. The installed README contains the current player guide.

Known legacy compatibility and incomplete native validation remain disclosed. Offline tests are not native verification. Back up saved data and test voluntarily.]]},
}
H.Pages=pages
local function refresh()
    local p=pages[index];frame.title:SetText("Nexus Help - "..p.title);frame.body:SetText(p.text)
    frame.page:SetText("Page "..index.." / "..#pages)
    if frame.content then
        frame.body:SetHeight(0)
        local measured=frame.body:GetStringHeight()
        local height=math.max(414,tonumber(measured) or 0)
        frame.body:SetHeight(height);frame.content:SetHeight(height+24)
    end
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
    scroll:SetPoint("TOPLEFT",20,-56);scroll:SetSize(595,414)
    scroll:SetFrameLevel(HELP_LEVEL+1)
    local child=CreateFrame("Frame",nil,scroll);child:SetSize(590,650);scroll:SetScrollChild(child);frame.content=child
    child:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,0);child:SetFrameLevel(HELP_LEVEL+2)
    frame.body=child:CreateFontString(nil,"OVERLAY","GameFontHighlight");frame.body:SetPoint("TOPLEFT",0,0)
    frame.body:SetWidth(585);frame.body:SetJustifyH("LEFT");frame.body:SetJustifyV("TOP");frame.body:SetWordWrap(true)
    local function b(x,w,label,fn)
        local f=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate");f:SetPoint("BOTTOMLEFT",x,20);f:SetSize(w,25);f:SetText(label)
        f:SetFrameLevel(HELP_LEVEL+2)
        f:SetScript("OnClick",function()fn();scroll:SetVerticalScroll(0)end);return f
    end
    b(20,90,"Previous",function()index=math.max(1,index-1);refresh()end)
    b(118,90,"Next",function()index=math.min(#pages,index+1);refresh()end)
    b(430,95,"Start page",function()index=1;refresh()end)
    b(533,100,"Close",function()frame:Hide()end)
    frame.page=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall");frame.page:SetPoint("BOTTOM",0,26)
    frame:Hide();UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusHelpWindow"
end
function H.Show(id)
    ensure();if id then for i,p in ipairs(pages) do if p.id==id then index=i end end end
    frame:Show();refresh();return frame
end
function H.Hide()if frame then frame:Hide()end end
