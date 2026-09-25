-- Automatic-save warning: player-facing text only. Reads the real Help pages,
-- the real Quick Start window, the real Journal selector/picker tooltip
-- handlers and the packaged guide. Assignment, edit and Unassign behave as
-- before; reading any warning saves nothing, spends nothing and changes no
-- setting. Native text fit is not established here (see the Quick Start model).
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_journal_picker.lua')
dofile=originalDofile
assert(H)
local T=dofile('tests/prototype/startup_support.lua')
local A=Nexus.GameAdapter
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function has(text,s) return type(text)=='string' and text:find(s,1,true)~=nil end

-- Baseline: nothing below may save a build, spend, or change a setting.
local saves,spends,uploads=H.Count('save'),H.Count('orb-spend'),H.Count('upload')
local autoSave=Nexus.Store.Settings().autoSave
local autoOn=Nexus.RecomputeStats().autoEnabled
local slotsBefore=H.Clone(H.perks.serverBuildSlots)
check(autoOn==false,'fixture runs with Auto OFF')
local function unchanged(label)
 check(H.Count('save')==saves,label..': no Saved Build write')
 check(H.Count('orb-spend')==spends,label..': no Orb spend')
 check(H.Count('upload')==uploads,label..': no Wishlist upload')
 check(Nexus.Store.Settings().autoSave==autoSave,label..': autoSave setting unchanged')
 check(Nexus.RecomputeStats().autoEnabled==autoOn,label..': Auto master switch unchanged')
 check(T.Equal(slotsBefore,H.perks.serverBuildSlots),label..': server Saved Build contents unchanged')
end

-- Wording rules shared by every surface.
local function sentences(text)
 local out={}
 text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 for s in text:gmatch('[^%.%?!;:\n]+') do out[#out+1]=s:lower() end
 return out
end
-- Whole-word negation ("cannot" and "nothing" count; "note" does not).
local function negated(s)
 for _,w in ipairs({'not','no','nothing','cannot','separate'}) do
  if s:find('%f[%a]'..w..'%f[%A]') then return true end
 end
 return false
end
local function honest(label,text)
 for _,s in ipairs(sentences(text)) do
  -- Assigning is target selection; the save is a separate action. The act of
  -- assigning (assign/assigns/assigning/assignment) is checked, not "the
  -- Wishlist assigned to"; "Saved Build" is a noun, not a save verb.
  if s:find('%f[%a]assigns?%f[%A]') or s:find('%f[%a]assigning%f[%A]')
   or s:find('%f[%a]assignment%f[%A]') then
   for _,verb in ipairs({'replace','overwrit','update','%f[%a]saves?%f[%A]','saving'}) do
    check(not s:find(verb) or negated(s),
     label..': assignment is not described as saving or replacing: "'..s..'"')
   end
  end
  -- Ordinary automatic save never spends Orbs.
  if s:find('%f[%a]orbs?%f[%A]') and (s:find('spend',1,true) or s:find('spent',1,true)) then
   check(negated(s),label..': Orb spending is only ever denied: "'..s..'"')
  end
  check(not s:find('every run is saved',1,true) or s:find('not every run',1,true),label..': not every run is saved')
  check(not s:find('every individual echo must',1,true),label..': no per-Echo improvement claim')
  check(not s:find('can undo',1,true) and not s:find('restores the saved build',1,true),label..': no undo or restore promise')
 end
end

-- 1. Help: Getting started (assignment step) and Rolling and settings.
check(#Nexus.Help.Pages==7,'still seven Help pages')
Nexus.Help.Show('start');local start=NexusHelpWindow.body:GetText()
check(has(start,'select the intended Saved Build and assign the Wishlist to it'),'Help names the targeted Saved Build')
check(has(start,'Assigning only chooses the target; by itself it does not change the Saved Build.'),'Help: assignment changes no Saved Build')
check(has(start,'With Auto ON, Nexus may replace that active Saved Build with a better finished run'),'Help: Auto can update that active Saved Build')
check(has(start,'right after you turn Auto ON or change the assignment.'),'Help: the check can follow an assignment change at once')
check(has(start,'It can also happen right after you save edits to the assigned Wishlist.'),'Help: the check can follow a saved edit at once')
check(has(start,'working copy, not a protected archive'),'Help: working copy, not archive')
check(has(start,'A Wishlist is a desired plan') and has(start,'Saved Builds are server slots'),'Help distinguishes Wishlist from Saved Build')
local stepAssign=start:find('4. In My Builds',1,true);local stepAuto=start:find('With Auto ON',1,true)
check(stepAssign and stepAuto and stepAuto>stepAssign and stepAuto-stepAssign<400,'warning sits next to the assignment step')
honest('Help start',start)
Nexus.Help.Show('rolling');local rolling=NexusHelpWindow.body:GetText()
check(has(rolling,'Automatic save is separate from Take, Banish, Reroll and Freeze.'),'Help: save distinct from Take/Banish/Reroll/Freeze')
check(has(rolling,'Auto may replace your active Saved Build with that run and give it the Wishlist\'s name.'),'Help: destination is the active Saved Build')
check(has(rolling,'compares the run with the Wishlist assigned to that loadout'),'Help: compared with the assigned Wishlist')
check(has(rolling,'It replaces an existing Saved Build only when overall Wishlist progress is higher than the Saved Build\'s, or equal with cleanup'),'Help: when a save replaces the build')
check(has(rolling,'Not every run is saved.'),'Help: not every run is saved')
check(has(rolling,'Assigning by itself changes nothing, but at level 80 after a finished run, turning Auto ON, changing the assigned Wishlist or saving edits to it makes Nexus check again right away'),'Help: immediate recheck after Auto ON, an assignment change or a saved edit')
check(has(rolling,"There is no separate automatic-save switch: Auto OFF stops it, together with Nexus's other automatic Echo actions."),'Help: Auto OFF is the only way to stop it')
check(has(rolling,'Better means Wishlist progress, not Orb investment or keeping every individual Echo.'),'Help: meaning of better')
check(has(rolling,'loses 1 requested copy but gains 3 other requested copies is +2 overall'),'Help: worked +2 example')
check(has(rolling,'The save itself spends no Orbs'),'Help: automatic save is not an Orb spend')
check(has(rolling,'does not mean that Echo was judged worthless'),'Help: lost Echo not judged worthless')
check(has(rolling,'Nexus cannot undo a completed save or bring back that Echo or the Orbs spent on it; Unassign does not restore a Saved Build.'),'Help: no undo, no restore')
check(has(rolling,'Keep Auto OFF if you want the current Saved Build left untouched.'),'Help: how to leave the Saved Build untouched')
check(has(rolling,'Target 2/current 5 means 3 extras'),'existing Rolling content retained')
honest('Help rolling',rolling)
NexusHelpWindow:Hide()
unchanged('Help')

-- 2. Quick Start: the short warning sits beside the assignment sentence and
-- the window keeps its size and button positions.
Nexus.QuickStart.Show();local qs=assert(NexusQuickStart);local body=assert(qs.body)
local qsText=body:GetText()
local assignAt=qsText:find('Assign the Wishlist you want it to follow.',1,true)
local warnAt=qsText:find('With Auto ON, Nexus may replace the active Saved Build with a better finished run.',1,true)
check(assignAt and warnAt and warnAt>assignAt,'Quick Start warning follows the assignment sentence')
check(has(qsText,'Keep Auto OFF to leave that slot unchanged.'),'Quick Start: how to keep the slot unchanged')
check(has(qsText,'Starting fresh? Import a Wishlist code'),'Quick Start: fresh-start sentence retained')
honest('Quick Start',qsText)
check(qs:GetWidth()==420 and qs:GetHeight()==332,'Quick Start window size unchanged')
-- x/y are the last two SetPoint arguments (the harness keeps them as given).
local function offset(region) local pt={region:GetPoint(1)};return pt[#pt-1],pt[#pt] end
local bx,by=offset(body)
local buttonTop
for _,c in ipairs(qs.children)do if c.kind=='Button' and c:GetText()=='Set up current build' then local _,y=offset(c);buttonTop=y end end
check(buttonTop==-132,'first button row unchanged')
check(bx==24 and body:GetWidth()==372,'Quick Start body keeps its width and left edge')
check(by>=-58 and by-body:GetHeight()>=buttonTop,'Quick Start body ends above the first button row')
-- Simulated fit only (the harness has no font renderer): the 10 px small font
-- at 0.55 em per visible character (the model used for the Auto label) and a
-- 12 px line, word-wrapped into the body width. Native pixel fit is NOT TESTED.
local function wrappedLines(text,width,charWidth)
 text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 local lines=0
 for para in (text..'\n'):gmatch('(.-)\n') do
  lines=lines+1;local used=0
  for word in para:gmatch('%S+') do
   local w=#word*charWidth;local gap=used>0 and charWidth or 0
   if used>0 and used+gap+w>width then lines=lines+1;used=w else used=used+gap+w end
  end
 end
 return lines
end
local modelLines=wrappedLines(qsText,body:GetWidth(),5.5)
print('QUICKSTART_MODEL_LINES',modelLines,'body_height',body:GetHeight())
check(modelLines*12<=body:GetHeight(),'Quick Start text fits its body in the simulated font model')
qs:Hide()
unchanged('Quick Start')

-- 3. Journal assignment UI: the real selector and picker-row tooltips.
local tip={}
function GameTooltip:SetOwner(owner) self.owner=owner;tip={} end
function GameTooltip:ClearLines() tip={} end
function GameTooltip:AddLine(text) tip[#tip+1]=tostring(text) end
local function Hover(frame)
 local enter=assert(frame:GetScript('OnEnter'),'control has a tooltip handler')
 enter(frame)
 local text=table.concat(tip,'\n')
 local leave=frame:GetScript('OnLeave');if leave then leave(frame) end
 return text
end
local function warns(label,text)
 check(has(text,'With Auto ON, Nexus may replace the active Saved Build'),label..': names the active Saved Build as the destination')
 check(has(text,'more overall Wishlist progress, or equal progress after cleanup or an even swap of requested copies'),label..': save is judged on overall Wishlist progress')
 check(has(text,'Auto checks again right away when you change the assignment.'),label..': an assignment change can be followed by a save at once')
 check(has(text,'It also checks again right away when you save edits to the assigned Wishlist.'),label..': a saved edit can be followed by a save at once')
 check(has(text,'even one obtained with Orbs: Orb investment is not compared.'),label..': Orb investment is not compared')
 check(has(text,'Keep Auto OFF to leave the Saved Build unchanged.'),label..': how to leave it unchanged')
 check(has(text,'Assigning by itself does not change any Saved Build.'),label..': assigning changes no Saved Build')
 honest(label,text)
end
ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
local assignedBefore=H.Clone(A.AssignedWishlist())
local selectorTip=Hover(NexusActiveWishlistSelector)
check(has(selectorTip,'Automation Wishlist'),'selector tooltip title retained')
warns('selector tooltip',selectorTip)
check(T.Equal(assignedBefore,A.AssignedWishlist()),'hovering the selector assigns nothing')

local function open()
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
 if NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 NexusActiveWishlistSelector:Click()
 check(NexusWishlistOnlyPicker:IsShown(),'actual selector opens its picker')
 return NexusWishlistOnlyPicker
end
local function row(p,name)
 for _,r in ipairs(p.children)do
  if r.nameButton and r:IsVisible() and r.nameButton.text:GetText():find(name,1,true) then return r end
 end
 error('picker row missing: '..name)
end
local activeName=A.Slots().bySlot[A.Slots().activeSlot].name
local p=open();local planA=row(p,'Plan A')
local rowTip=Hover(planA.nameButton)
check(has(rowTip,'Assign Wishlist'),'picker row tooltip names the action')
check(has(rowTip,'Target: '..activeName),'picker row tooltip names the targeted Saved Build')
check(has(rowTip,'Sets this Wishlist as the target for this loadout.'),'picker row: target selection')
warns('picker row tooltip',rowTip)
check(T.Equal(assignedBefore,A.AssignedWishlist()) and p:IsShown(),'hovering a row assigns nothing and keeps the picker open')
check(Hover(planA.gear)=='Edit wishlist','gear tooltip unchanged')
local unassignTip=Hover(assert(p.clearRow,'Unassign row'))
check(has(unassignTip,'Keeps the Wishlist; stops using it for this loadout.'),'Unassign tooltip retained')
check(has(unassignTip,'Does not change or restore the Saved Build.'),'Unassign tooltip: no restore promise')
unchanged('hover')

-- Unchanged behaviour: name click assigns, gear edits, Unassign clears.
check(A.AssignedWishlist().name=='Plan B','fixture starts with Plan B assigned')
planA.nameButton:Click()
check(A.AssignedWishlist().name=='Plan A' and not NexusWishlistOnlyPicker:IsShown(),'clicking the name still assigns and closes the picker')
unchanged('assign Plan A')
p=open();local gear=row(p,'Plan B').gear
if NexusEditorFrame then NexusEditorFrame:Hide() end
gear:Click()
check(NexusEditorFrame and NexusEditorFrame:IsShown() and not NexusWishlistOnlyPicker:IsShown(),'gear still opens the editor, not an assignment')
check(A.AssignedWishlist().name=='Plan A','gear does not change the assignment')
NexusEditorFrame:Hide()
p=open();p.clearRow:Click()
check(A.AssignedWishlist().state=='unassigned','Unassign still clears the active association')
unchanged('assign, edit and Unassign')

-- First-run context: the row tooltip names that there is no active Saved Build.
H.perks.serverActiveSlot=0;H.Notify();A.Poll();slotsBefore=H.Clone(H.perks.serverBuildSlots)
p=open();local firstRunTip=Hover(row(p,'Plan B').nameButton)
check(has(firstRunTip,'Target: No Saved Build selected'),'first-run tooltip names the missing Saved Build')
warns('first-run row tooltip',firstRunTip)
if NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
unchanged('first-run hover')

-- 4. Packaged player guide agrees with Help.
local file=assert(io.open('README-PROTOTYPE.md','rb'));local guide=file:read('*a');file:close()
local section=guide:match('### Automatic save and your Saved Build(.-)\n## ')
check(section,'guide has the automatic-save section')
-- Compare prose independent of the guide's line wrapping.
section=section:gsub('%s+',' ');guide=guide:gsub('%s+',' ')
check(has(section,'**Wishlist assignment** chooses the target'),'guide: assignment is target selection')
check(has(section,'By itself, it does not change the Saved Build.'),'guide: assignment changes no Saved Build')
check(has(section,'**Automatic save** is a separate action'),'guide: automatic save is separate')
check(has(section,'may replace the **active Saved Build**'),'guide: destination is the active Saved Build')
check(has(section,'Not every run is saved.'),'guide: not every run is saved')
check(has(section,'A run replaces an existing Saved Build only when'),'guide: when a save replaces the build')
check(has(section,'turning Auto ON, changing the assigned Wishlist or saving edits to it makes Nexus check again right away'),'guide: immediate recheck, including a saved edit')
check(has(section,'There is no separate automatic-save switch'),'guide: Auto OFF is the only way to stop it')
check(has(section,'Orb investment is not part of the comparison'),'guide: Orb investment not compared')
check(has(section,'+2 overall Wishlist progress'),'guide: worked example')
check(has(section,'The save itself spends no Orbs, but Orbs already spent on the replaced Echo are not recovered'),'guide: no Orb spend, no Orb recovery')
check(has(section,'Nexus cannot undo a completed server save.'),'guide: no undo')
check(has(section,'does not change or restore the Saved Build'),'guide: Unassign restores nothing')
check(has(guide,'Assigning only chooses the target; by itself it does not change the Saved Build.'),'guide setup step matches Help')
honest('guide',section)
print('PASS automatic-save warning in Help, Quick Start, Journal assignment tooltips and guide; behaviour unchanged='..checks)
