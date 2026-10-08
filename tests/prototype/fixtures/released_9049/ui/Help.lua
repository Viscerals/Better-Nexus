-- Reopenable read-only guide. Available before saved data or shared data is ready.
Nexus=Nexus or {}
local H={};Nexus.Help=H
local frame,index= nil,1
-- Keep the complete Help window above the Orb dialog's 30-33 layer band.
local HELP_LEVEL=40
local pages={
 {id="start",title="Getting started",text=[[Nexus helps you work toward an Echo build. Create or import a Wishlist, choose its planned locked Echo targets, and assign it to a Saved Build. Follow the recommendations, or explicitly enable the actions you want automated. Shared builds and Leaderboards show records known to this client.

1. Back up your Nexus folder and WTF with WoW closed before testing.
2. Open Wishlists, or use /nexus editor. Create a plan or import a Wishlist code.
3. Check exact qualities/copies and the planned locked targets. Save it.
4. In My Builds, select the intended Saved Build and assign the Wishlist to it. Assigning only chooses the target; by itself it does not change the Saved Build.
5. Review recommendations with Auto OFF first. With Auto ON, Nexus may replace that active Saved Build with a better finished run; at level 80 after a finished run, that can happen right after you turn Auto ON or change the assignment. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. It treats the slot as a working copy, not a protected archive. Keep Auto OFF if you want it left unchanged.

A Wishlist is a desired plan, not proof that you own its Echoes. Saved Builds are server slots. Active Loadout is the selected server loadout. Snapshot is the saved-run mode. A valid Saved Build proves its identity, contents and owner. Nexus treats no future random Echo roll as guaranteed, for a Snapshot or for a Designed Wishlist.

This is an experimental build. Reading this guide never spends, assigns, activates, or sends a Sync request.]]},
 {id="wishlists",title="Wishlists and locked targets",text=[[A complete plan can contain up to 79 rolled copies and 6 locked Echo copies (85 total). Counts are copies, not unique names or list rows. Different qualities remain different targets.

Currently locked Echoes are what you actually have. Locked Echo targets are what the plan wants. A Frozen offer is a temporary offered card kept by the game's Freeze action; it is not a locked Echo slot.

Untagged imports use your matching currently locked Echoes by default if that makes a valid 79+6 split. Existing confirmed plans are unchanged. When matching is insufficient, choose and confirm the intended locked targets in the editor. You do not need to already own a desired plan.

Import opens a draft. Save writes the plan; assignment selects which Wishlist a loadout uses. Unassign keeps the Wishlist. Nexus-only locked-role markers should be imported in Nexus, not assumed compatible with every native importer.

/nexus currentlocks off: choose future untagged plans manually.
/nexus currentlocks on: use matching locked targets by default.

Opening or confirming targets does not lock/unlock anything. Automatic locked-Echo slot changes require both Automation and their separate option, plus ownership and safety checks.]]},
 {id="rolling",title="Rolling and settings",text=[[Automation (the Auto ON/OFF button) is a master permission, separate from per-action settings. OFF leaves recommendations available; it does not disable build sharing. Enabling automation can use permitted Banish/Reroll/Freeze charges and configured activation, save, or locked-Echo slot actions.

Take chooses a needed offer. Banish removes an eligible offer. Reroll asks for new choices when enabled. Freeze preserves an eligible offered card. The planner considers remaining needs and choices; it does not always Freeze whenever two wanted cards appear.

/nexus reroll on|off and /nexus freeze on|off change those permissions, not the master switch.

Automatic save is separate from Take, Banish, Reroll and Freeze. After a completed run, Auto may replace your active Saved Build with that run and give it the Wishlist's name. Nexus compares the run with the Wishlist assigned to that loadout. It replaces an existing Saved Build only when overall Wishlist progress is higher than the Saved Build's, or equal with cleanup (some extra copies removed, or an even swap of requested copies). Not every run is saved. Assigning by itself changes nothing, but at level 80 after a finished run, turning Auto ON or changing the assigned Wishlist makes Nexus check again right away, so a replacement can follow within seconds. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. There is no separate automatic-save switch: Auto OFF stops it.

Better means Wishlist progress, not Orb investment or keeping every individual Echo. Example: a run that loses 1 requested copy but gains 3 other requested copies is +2 overall. It can replace the Saved Build even when the lost Echo is one you value or obtained with Orbs. The save itself spends no Orbs, and it does not mean that Echo was judged worthless. Nexus cannot undo a completed save or bring back that Echo or the Orbs spent on it; Unassign does not restore a Saved Build. Keep Auto OFF if you want the current Saved Build left untouched. Auto starts OFF each session.

EXTRA COPIES are rolled copies above exact Wishlist targets, including unrequested or different-quality copies. Target 2/current 5 means 3 extras. This display deletes nothing. A later run may reduce extras; replacement is not guaranteed.

Needed, Target already met, and Not on Wishlist describe the current choice. Priority numbers in advanced diagnostics are not DPS or percentages. [G] means the server marks this current offer guaranteed. A card the game shows as held or frozen is observed state. Nexus does not assume any future random Echo roll. Wishlist overlay: [X] meets the requested copy count; [~] has some but not all requested copies; [ ] has none. Those symbols are not network/loading states.

Waiting for current Echo data means automatic choices are paused for ownership confirmation. It is not the Community Sync channel status. Ordinary rolling stays paused during active or unknown Orb offers.]]},
 {id="sharing",title="Shared builds and DPS",text=[[Build Library browses records known locally and shared by Nexus users. Copy into Editor creates a draft; it does not activate or spend. Share Build sends a listing to other users; it is separate from saving a Wishlist or a server Saved Build.

Stop Sharing, an administrator removing a shared record, and deleting from My Builds are different actions. Read each confirmation. Do not infer that removing a shared listing deletes your server build.

Both DPS records means the required Training Dummy and Lich King records are present, not that the build is proven optimal. The combined view is ranked by its highest single result; an average can be display-only. A missing record is not a verdict on build quality.

DPS capture depends on Details! and its supported events. A read-only Echo list has attached DPS evidence; share a new build for a different Echo list.

Sync Now checks for shared builds and records. Preparing, request sent, receiving updates, and finished are distinct. Sent does not prove peer convergence. Removing expired requests is bounded queue housekeeping.

The addon uses its normal live sharing network. Do not flood it or test malformed traffic. Older PR #68 peers cannot fully converge on locked-bearing builds; new-peer success must be tested separately.]]},
 {id="orbs",title="Orbs / Lost Memories",text=[[Orb mode refines existing rolled Echoes toward the assigned Wishlist. It uses one Orb per replacement, then waits for the actual offer and the confirmed result. It cannot create, reorder, or replace locked Echo slots. Once rolled targets are complete it stops, even if the plan still has unmet locked targets.

1. Open /nexus orbs. Its Wishlist is the same assignment shown in the main panel. Use My Builds or the Wishlist Editor if none is assigned.
2. Check missing rolled copies, locked-target limits, and the confirmed Orb balance. Loading or unavailable data is not a zero balance.
3. Enter the maximum Orbs. Start explicitly approves that maximum and automatic use of eligible surplus copies, including safe recycling. Opening the window approves nothing.
4. One Start continues after each confirmed result. It stops at target completion, the maximum, insufficient balance, no safe source, or uncertainty. Locked and required copies stay protected. Advanced provides optional exclusions and read-only Recheck.
5. Changing the active loadout, assignment or targets pauses new actions. An already-submitted operation remains bound to its original target. After it settles, explicit Resume adopts the new target and retains all usage against the same maximum.

Starting disables ordinary Automation; it does not automatically re-enable it. The game and other addons' competing pickers must be off. Unknown capabilities disable only Orb mode.

Pause/Stop prevents new submissions, not a spend already accepted. The native offer remains accessible. Recheck only requests balance/ownership data. A missing response retains spending exposure; no automatic repeat is sent.

Closing the window does not stop an approved run. Use Pause or Stop.

Compact progress and Pause/Resume/Stop remain in the main Nexus panel when this window is closed.

Real-resource Orb testing remains unavailable pending a separate user decision and native capability confirmation. A same-ID, same-quality result cannot be distinguished from stale ownership by the supported API. It stays paused with pending exposure. Recheck cannot prove it by returning an unchanged table.

If the active loadout changes during a pending operation, ownership responses cannot identify the original loadout. That action stays unresolved even after returning to the old loadout. Recheck, Resume and reload cannot remove this uncertainty or restore its allowance.

Resume retains confirmed usage and unresolved exposure. Login, reconnect, new resources, or reload never automatically restart spending. An unresolved earlier action must settle before a new run. Missing confirmation can prevent further Orb use indefinitely; Resume, Recheck and reload are not guaranteed fixes.

After a reload with an unresolved Orb action, Nexus only reads. If the offer of that action is still open and matches the saved record, choose in the game's offer window: Nexus records that choice and confirms the action only from the exact matching result. If the action ended while Nexus could not observe it, the game gives no record of which choice belonged to it. Nexus then cannot confirm it, and Recheck cannot settle it. The record, its spending exposure, and the block on new Orb runs and ordinary rolling stay. Nexus never retries, refunds, or deletes such a record. No exit from that block exists yet: a settlement path is only a proposal and is not built. If Nexus had proposed an Echo before the reload, only a choice of that same Echo can be confirmed; the Orb window names it.]]},
 {id="troubleshooting",title="Loading and troubleshooting",text=[[The loading panel shows the current step and elapsed time. When that step already knows its size, it shows done / total and a percentage for that step only, never for the whole startup. Otherwise it shows the step as in progress, with no bar. /nexus loading reopens it.

Wishlist tools and ordinary rolling can be available after local validation while shared builds still prepare. Rolling also needs its own fresh ownership/board/resource state. Gray Build Library/Leaderboard tabs mean those shared views are not ready.

Useful commands:
/nexus panel - show/hide the main panel
/nexus editor - edit Wishlists
/nexus status - concise status/build identity
/nexus update - installed build, update status, Releases page
/nexus sync - explicitly request shared-build Sync
/nexus log errors - recorded errors
/nexus perf - runtime timing diagnostics (not DPS)
/nexus help - this guide, available during loading
/nexus orbs - open Orb mode without spending

Prepare full diagnostic report builds a paged report. Select this page and copy pages in order; it does not put every page on the clipboard. Large reports may take a moment. Report build label, exact action, expected/actual outcome, and a small error screenshot first.

Update notices: Nexus shows an update notice only from release information shipped inside this package. It does not check GitHub. Versions that other players' clients state during Sync are not release information and never produce a notice. /nexus update and the menu always open the Releases page. No notice does not mean your build is the latest. Nexus never downloads or installs.

Do not delete saved data or run advanced reset commands on guesswork. Keep a matching addon/WTF backup for rollback with WoW closed. Native timing and recovery are not established by offline tests.]]},
 {id="about",title="About and advanced details",text=[[Ordinary rolling and Orb decisions come from EchoWeaver, the rolling engine that Nexus maintains itself. Orb decisions use EchoWeaver's source, target and fallback rules with Nexus's exact-quality, locked-role, approval, budget and confirmation safeguards.

EchoWeaver has no runtime dependency on another addon. Source and reuse notices are in THIRD_PARTY.md. Neither algorithm is claimed mathematically optimal or universally safe without matching client evidence.

This prototype uses a compatible global ChatThrottleLib where available, otherwise its disclosed private compatibility scheduler. That is not complete official-library/native acceptance.

Advanced diagnostics retain raw reason codes and identifiers so support can distinguish failures. flags reads active safety assumptions; undemote clears recorded temporary assumption disablements; anchor changes the existing Adaptive Power preference; restore restores the prior host auto-accept setting; err displays the latest recorded error. These are troubleshooting tools, not generic fixes. Do not experiment with them to clear a loading message.

/nexus prototype prints build/reference details. The installed README contains current user instructions; detailed historical tests belong to the source bundle.

Known legacy compatibility and incomplete native validation remain disclosed. Back up saved data and test voluntarily.]]},
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
