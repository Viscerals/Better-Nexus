-- Action-first Help and player guide (BN-OWNER-HELP-ACTION-FIRST-001).
-- Reads the real Help pages through their real entry points and the packaged
-- guide. Checks meaning, not wording alone: warnings stand before the action
-- they qualify; Max, retries, DPS records, unknown locked roles and the
-- reporting route are described as the product behaves; every quoted control
-- label exists in the UI source; reading changes nothing. Native text fit is
-- not established here (conservative token-width model only).
local H=dofile('tests/prototype/harness.lua');H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function has(text,s) return type(text)=='string' and text:find(s,1,true)~=nil end
local function before(text,a,b,label)
 local i,j=text:find(a,1,true),text:find(b,1,true)
 check(i and j and i<j,label..' ("'..a..'" before "'..b..'")')
end
local actions,sent=#H.actions,#H.sent
local auto=Nexus.RecomputeStats().autoEnabled

-- Pages, ids and order are the existing ones (entry points depend on them).
local ids={}
for _,p in ipairs(Nexus.Help.Pages) do ids[#ids+1]=p.id end
check(table.concat(ids,',')=='start,wishlists,rolling,sharing,orbs,troubleshooting,about','page ids and order unchanged: '..table.concat(ids,','))
local function Page(id) Nexus.Help.Show(id);return NexusHelpWindow.body:GetText() end
local start,wishlists,rolling,sharing,orbs,trouble=Page('start'),Page('wishlists'),Page('rolling'),Page('sharing'),Page('orbs'),Page('troubleshooting')
local file=assert(io.open('README-PROTOTYPE.md','rb'));local guide=file:read('*a');file:close()
guide=guide:gsub('%s+',' ')

-- 1. The active Saved Build warning stands before the step that turns Auto ON.
before(start,'With Auto ON, Nexus may replace that active Saved Build','Click Auto OFF','Help start: warning before the Auto step')
before(start,'With Auto ON, Nexus may replace that active Saved Build','Click Create Wishlist','Help start: warning before Create Wishlist')
check(has(start,'Click Create Wishlist for a new or imported plan. It saves the plan and makes it the target of the loadout shown in the editor.'),'Create Wishlist saves and targets (it is not a blank-plan button)')
check(has(start,'For an existing Wishlist, click Save Wishlist.'),'Save Wishlist is for an existing Wishlist')
before(rolling,'Automatic save is separate from Take, Banish, Reroll and Freeze.','1. Click Auto OFF','Help rolling: warning before the Auto step')
before(guide,'### Automatic save and your Saved Build','Click **Auto OFF**','guide: automatic-save section before the Auto step')
check(has(rolling,'Auto OFF does not turn Nexus off'),'Auto is not addon enablement')
check(has(trouble,'Hide Nexus Panel') and has(trouble,'only hides the panel'),'hiding the panel is not disabling Nexus')
check(has(trouble,'only when no action is active or pending: log out to character selection, click AddOns'),'turning Nexus off: guarded, client path')
check(has(guide,'only when no action is active or pending: log out to character selection'),'guide: turning Nexus off guarded')
check(has(trouble,'UNVERIFIED hint') and has(guide,'UNVERIFIED hint'),'peer update reports are unverified hints')

-- 2. Max and the budget: Max follows the balance and starts nothing; the
-- approved maximum is fixed; the manual limit is its own rule.
check(has(orbs,'Max returns to following the balance') and has(orbs,'Help and Max spend nothing'),'Max follows the balance and spends nothing')
check(has(orbs,'up to 1000') and has(orbs,'Typing an amount stops that'),'the draft follows the balance up to 1000 until typed')
check(has(orbs,'The approved maximum does not change during the run'),'approved maximum fixed')
check(has(orbs,'whole number from 1 to 10,000'),'manual-limit validation stated separately')
check(has(orbs,'A maximum saved by an earlier version is kept'),'legacy saved values kept')
check(has(orbs,'Start new run') and has(orbs,'Confirm new run'),'explicit new-run review')
for _,text in ipairs({orbs,guide}) do
 check(not text:find('Max starts',1,true) and not text:find('Max approves',1,true) and not text:find('Max changes',1,true),'Max never described as starting or approving')
end
check(has(orbs,'Closing the window does not stop an approved run. Use Pause or Stop.'),'closing is not stopping')
check(has(orbs,'Recheck only asks for balance and ownership data; it is not a replay or a fix'),'Recheck is read-only')
check(has(orbs,'do not clear it') or has(orbs,'does not clear it') or has(orbs,'do not clear'),'unresolved receipt is not cleared by relog or controls')
before(orbs,'if that action\'s offer is still open','choose in that window','narrow manual case: prerequisite before the action')

-- 3. No retry advice for an unconfirmed action; the empty state is not completion.
check(has(rolling,'Waiting for the game to confirm the last Echo action.') and has(rolling,'Do not choose again or reload; wait.'),'unconfirmed action: wait, do not choose again')
check(has(rolling,'No Echo choice is showing.') and has(rolling,'It does not mean the run is finished, and it is not a reason to retry.'),'empty state is not completion or a retry reason')
for _,text in ipairs({rolling,orbs,guide}) do
 check(not text:lower():find('choose again if',1,true) and not text:lower():find('try again',1,true),'no retry advice')
end

-- 4. DPS records and locked roles.
check(has(sharing,'Require both DPS records') and has(sharing,'It is not build quality, outside verification, or finished Sync.'),'both-DPS is availability, not verification')
check(has(sharing,'Nexus treats its locked targets as unknown, not as none'),'unknown locked roles are not zero')
check(has(guide,'unknown, not as none'),'guide: unknown locked roles are not zero')
check(has(sharing,'Owner identity not established.') and has(sharing,'It is not proof of identity.'),'readable names are not identity')

-- 5. Reporting: route, session-only evidence, private file, failure exception.
for label,text in pairs({Help=trouble,guide=guide}) do
 check(has(text,'/nexus report'),label..': report command')
 check(has(text,'before any reload'),label..': capture before reloading')
 check(has(text,'Copy summary') and has(text,'click in the text') and has(text,'Ctrl+C'),label..': copy the summary (focus the text first)')
 check(has(text,'Prepare report file') and has(text,'only when no action is active or pending'),label..': report file after no pending action')
 check(has(text,'WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua'),label..': report file path')
 check(has(text,'privately; never post it publicly'),label..': private file, never public')
 check(has(text,'Both Nexus and NexusSupport must be installed and enabled.'),label..': both addons required')
 check(has(text,'If reporting fails') and has(text,'You are not asked for logs that a broken reporting feature cannot create.'),label..': reporting-failure exception kept')
 check(has(text,'Do not clear logs or reset saved data'),label..': no clearing to recreate')
 check(not text:find('post it in a public',1,true) and not text:find('public issue',1,true),label..': no public posting of the file')
end
before(trouble,'Its incidents are kept for this session only.','/reload only when','session-only warning before any reload advice')

-- 6. Every quoted control label is a real label in the UI source.
local sources={}
for _,path in ipairs({'ui/Panel.lua','ui/OrbPanel.lua','ui/SupportReport.lua','ui/CommunityRenderer.lua','ui/Leaderboard.lua',
 'ui/WishlistRenderer.lua','ui/WishlistEditor.lua','ui/JournalTab.lua','ui/LogViewer.lua','core/UserText.lua','logic/OrbGuidance.lua'}) do
 local f=assert(io.open(path,'rb'));sources[#sources+1]=f:read('*a');f:close()
end
local all=table.concat(sources,'\n')
for _,label in ipairs({'Wishlist Editor','Create Wishlist','Import','Save Wishlist','Assign Wishlist','Unassign Wishlist',
 'Confirm locked targets & edit','Build Library','All Shared','Require both DPS records','Updating results...','Copy into Editor',
 'Share Build','Stop Sharing','Sync Now','Training Dummy','Lich King','Both records','Open Orbs...','Orbs / Lost Memories',
 'Max','Start','Pause','Resume','Stop','Start new run','Confirm new run','Advanced','Recheck','Hide Nexus Panel',
 'Copy summary','Prepare report file','Prepare full diagnostic report','Select this page','EXTRA COPIES','Different quality from target',
 'Needed','Target already met','Not on Wishlist','Auto ON','Auto OFF'}) do
 -- A string literal or a colour-coded span in the source, not any substring.
 local esc=label:gsub('%p','%%%0')
 check(all:find('"'..esc) or all:find(esc..'"') or all:find('|c%x%x%x%x%x%x%x%x'..esc) or all:find(esc..'|r'),'real label: '..label)
end

-- Quoted status lines exist as shown (colour codes aside).
for _,line in ipairs({'Waiting for the game to confirm the last Echo action.','No Echo choice is showing.','Auto ON — paused',
 'Owner identity not established.','Not prepared','Updating results...','Status: '}) do
 check(has(all,line),'real status text: '..line)
end

-- 7. Conservative fit: no unbreakable token wider than the Help body
-- (585 px) at 7 px per character.
for _,p in ipairs(Nexus.Help.Pages) do
 for token in p.text:gmatch('%S+') do check(#token*7<=585,'page '..p.id..': token fits the body width: '..token) end
end

-- 8. Reading every page, through every entry point, changes nothing.
-- /nexus help reopens the guide on the page last shown; Start page returns
-- to Getting started (existing behaviour).
SlashCmdList.NEXUS('help');check(NexusHelpWindow:IsShown(),'/nexus help opens the guide')
local startButton
for _,x in ipairs(H.frames) do if x:GetParent()==NexusHelpWindow and x.kind=='Button' and x:GetText()=='Start page' then startButton=x end end
startButton:Click();check(NexusHelpWindow.page:GetText()=='Page 1 / 7','Start page returns to Getting started')
for i=1,7 do check(#NexusHelpWindow.body:GetText()>300,'page '..i..' has its text');Nexus.Help.Show(ids[i]) end
check(#H.actions==actions and #H.sent==sent and Nexus.RecomputeStats().autoEnabled==auto,'reading Help sends, acts and changes nothing')
print('PASS help_action_first checks='..checks)
