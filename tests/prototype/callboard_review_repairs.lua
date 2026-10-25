-- Callboard review repairs. Offline module behavior only.
-- Stock trackers stay until the Nexus row is a visible committed replacement,
-- and their previous alpha and mouse state are put back exactly.
-- Passive reward discovery does not drive foreign enter/leave handlers or
-- hide an unrelated tooltip, and it does not attach another quest's progress
-- or rewards to the callboard objective. A throwing quest-log getter stays
-- inside the scanner, summary, and panel refresh. Unchanged quest events do
-- not rebuild the HUD. Objective rows are at least one 17px line, and a
-- shortened title is recoverable from its tooltip.
local checks=0
local function check(v,m) assert(v,m); checks=checks+1 end
local H=dofile('tests/prototype/harness.lua')
H.Boot()
if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide() end

local objective={title='Callboard Quest',questId=77,objectiveText='Bring the tome'}
-- Synthetic difficulty rewards come with each later objective update, so the
-- covered replacement below replaces reward access too. The first objective
-- carries none: the other-objective tooltip check below needs it empty.
local firstObjective=objective
local laterRewards={normalSoulAshes=1200,normalMoney=45000}
ProjectEbonhold.ObjectivesService={
 GetActiveObjective=function()
  if objective==firstObjective then return objective end
  local active={}
  for k,v in pairs(objective) do active[k]=v end
  for k,v in pairs(laterRewards) do active[k]=v end
  return active
 end,
}

local function Track(frame,alpha,mouse)
 frame.alpha=alpha
 frame.mouse=mouse
 function frame:GetAlpha() return self.alpha end
 function frame:SetAlpha(v) self.alpha=v end
 function frame:IsMouseEnabled() return self.mouse end
 function frame:EnableMouse(v) self.mouse=v and true or false end
end

local otf=CreateFrame('Frame','ObjectiveTrackerFrame',UIParent)
Track(otf,0.35,true)
otf:Show()
local tracker=CreateFrame('Frame','EbonholdQuestTracker',UIParent)
Track(tracker,0.8,true)
local collapse=CreateFrame('Button',nil,tracker)
Track(collapse,1,true)
tracker.collapse=collapse
local function Label(parent,text)
 local fs=parent:CreateFontString()
 fs:SetText(text)
 return fs
end
Label(tracker,'Quests')
Label(tracker,'One More Door')
Label(tracker,'0/1 Doors')
local enters,leaves=0,0
local pouch=CreateFrame('Button',nil,tracker)
pouch:SetSize(20,20)
pouch:SetScript('OnEnter',function()
 enters=enters+1
 if GameTooltip:IsShown() then GameTooltip:Hide() end
end)
pouch:SetScript('OnLeave',function() leaves=leaves+1 end)

local tooltipHidden=0
local realHide=GameTooltip.Hide
function GameTooltip:Hide()
 tooltipHidden=tooltipHidden+1
 return realHide(self)
end
GameTooltip:Show()
local shownBefore=GameTooltip:IsShown()
local hiddenBefore=tooltipHidden

local function AdvanceScan()
 H.Fire('QUEST_LOG_UPDATE')
 H.Advance(0.25)
end

Nexus.Panel.Hide()
AdvanceScan()
local summary=Nexus.CallboardStatus.GetSummary()
check(summary and summary.observed==true and summary.title=='Callboard Quest',
 'the callboard objective is the active objective')
local lines=table.concat(summary.lines or {},'|')
check(not lines:find('Doors',1,true),'tracker progress from another quest is not attached')
check(otf.alpha==0.35 and otf.mouse==true,'hidden panel: stock tracker alpha and mouse stay')
check(tracker.alpha==0.8 and tracker.mouse==true and collapse.mouse==true,
 'hidden panel: quest tracker and its collapse control stay')
check(enters==0 and leaves==0,'passive discovery does not call foreign OnEnter or OnLeave')
check(GameTooltip:IsShown()==shownBefore and tooltipHidden==hiddenBefore,
 'passive discovery does not hide an unrelated tooltip')

local other=CreateFrame('Frame',nil,UIParent)
other.objectiveData={title='Other Quest',questId=8}
GameTooltip.NumLines=function() return 2 end
GameTooltip.GetOwner=function() return other end
_G.GameTooltipTextLeft1=CreateFrame('Frame')
GameTooltipTextLeft1:SetText('Rewards by Difficulty')
_G.GameTooltipTextLeft2=CreateFrame('Frame')
GameTooltipTextLeft2:SetText('Normal')
_G.GameTooltipTextRight2=CreateFrame('Frame')
GameTooltipTextRight2:SetText('1000')
GameTooltip:Hide();GameTooltip:Show()
AdvanceScan()
summary=Nexus.CallboardStatus.GetSummary()
check(type(summary.rewards)~='table' or #summary.rewards==0,
 'a tooltip owned by another objective is not stored as this objective\'s rewards')

local refreshes=0
local refresh=Nexus.Panel.Refresh
function Nexus.Panel.Refresh(...)
 refreshes=refreshes+1
 return refresh(...)
end
AdvanceScan()
refreshes=0
for _=1,5 do H.Fire('QUEST_LOG_UPDATE') end
H.Advance(1.2)
check(refreshes==0,'five unchanged quest events do not rebuild the HUD')
objective={title='Callboard Quest',questId=77,objectiveText='Bring both tomes'}
H.Fire('QUEST_LOG_UPDATE')
H.Advance(0.25)
summary=Nexus.CallboardStatus.GetSummary()
check(refreshes>=1,'a changed objective still refreshes the panel')
check(summary.lines and summary.lines[1] and tostring(summary.lines[1]):find('both tomes',1,true),
 'the new objective text is the one that was observed')

local longTitle='Callboard Quest '..string.rep('W',80)
objective={title=longTitle,questId=77,objectiveText='Bring both tomes'}
Nexus.Panel.Show()
Nexus.Panel.Refresh()
H.Advance(0.25)
local panel=_G.NexusPanel
check(panel and panel:IsShown(),'fixture: the panel is shown for the replacement')
local title=panel._callboardTitle
local line=panel._callboardLine
check(title and title:GetHeight()>=17 and line and line:GetHeight()>=17,
 'objective rows are at least one 17px line')
check(otf.alpha==0 and tracker.alpha==0,
 'visible committed replacement suppresses the stock trackers')
check(otf.mouse==false and collapse.mouse==false and tracker.mouse==true,
 'the replacement changes only the mouse controls it takes over')
local hit=panel._callboardTitleHit
local captured
local addLine=GameTooltip.AddLine
function GameTooltip:AddLine(text)
 captured=tostring(text)
 return addLine(self,text)
end
check(hit and hit.GetScript and type(hit:GetScript('OnEnter'))=='function',
 'the shortened title has a complete-text hover')
hit:GetScript('OnEnter')(hit)
check(type(captured)=='string' and captured:find(longTitle,1,true)~=nil,
 'the hover shows the complete title')

Nexus.Panel.Hide()
check(otf.alpha==0.35 and otf.mouse==true,'hiding the panel restores the exact tracker alpha and mouse')
check(tracker.alpha==0.8 and tracker.mouse==true and collapse.mouse==true,
 'hiding the panel restores the exact quest tracker and collapse control')

GetNumQuestLogEntries=function() return 1 end
GetQuestLogTitle=function() error('optional quest log getter') end
local survived=pcall(function()
 H.Fire('QUEST_LOG_UPDATE')
 H.Advance(0.25)
 Nexus.CallboardStatus.GetSummary()
 Nexus.Panel.Show()
 Nexus.Panel.Refresh()
end)
check(survived,'a throwing quest-log getter stays inside scan, summary, and refresh')
summary=Nexus.CallboardStatus.GetSummary()
check(summary and summary.observed==true and summary.title==longTitle,
 'the active objective remains after the quest-log getter fails')

-- Objective detail hover (offline, synthetic): the row shows the first
-- detail line and +N more; its real hover carries every complete line in
-- order, also when that first line fits. A literal snapshot at the public
-- GetSummary boundary drives the real Panel.Show/Refresh render. Native
-- tooltip display is not run here.
local realSummary=Nexus.CallboardStatus.GetSummary
local snapshot={observed=true,title='Callboard Relay',
 lines={'Kill 3 rats','Collect 5 Ember Shards from the Ashen Vale','Return to the Callboard'},rewards={}}
Nexus.CallboardStatus.GetSummary=function() return snapshot end
local tipLines={}
local priorAddLine=GameTooltip.AddLine
function GameTooltip:AddLine(text,...)
 tipLines[#tipLines+1]=tostring(text)
 return priorAddLine(self,text,...)
end
local function RenderDetail()
 Nexus.Panel.Show()
 Nexus.Panel.Refresh()
 H.Advance(0.25)
 local row=panel._callboardLine
 check(panel:IsShown() and row and row:IsShown(),'fixture: the panel shows the objective detail row')
 return row,row:GetText() or ''
end
local function HoverDetail()
 local detailHit=panel._callboardLineHit
 check(detailHit and type(detailHit:GetScript('OnEnter'))=='function','fixture: the detail row has a hover')
 tipLines={}
 detailHit:GetScript('OnEnter')(detailHit)
 local shown=tipLines
 local leave=detailHit:GetScript('OnLeave')
 if leave then leave(detailHit) end
 return shown
end
local function InOrder(seen,expected)
 local at=0
 for _,want in ipairs(expected) do
  local found
  for i=at+1,#seen do if seen[i]==want then found=i;break end end
  if not found then return false end
  at=found
 end
 return true
end
local row,rowText=RenderDetail()
check(rowText:find('Kill 3 rats',1,true)==1 and rowText:find('+2 more',1,true)~=nil
 and not rowText:find('Ember',1,true),'fixture: the row shows the first detail line and +2 more')
check(row:GetStringWidth()<=row:GetWidth(),'fixture: the first visible detail line fits its row')
check(InOrder(HoverDetail(),snapshot.lines),'the detail hover shows every complete objective line in order')
snapshot={observed=true,title='Callboard Relay',lines={'Find 2 keys','Unlock the Sunken Vault door'},rewards={}}
row,rowText=RenderDetail()
check(rowText:find('Find 2 keys',1,true)==1 and rowText:find('+1 more',1,true)~=nil,
 'fixture: the changed objective is the one rendered')
local changedTip=HoverDetail()
local changedText=table.concat(changedTip,'|')
check(InOrder(changedTip,snapshot.lines) and not changedText:find('Kill 3 rats',1,true)
 and not changedText:find('Ember',1,true) and not changedText:find('Return to the Callboard',1,true),
 'a changed objective shows its own complete lines and none of the earlier ones')
GameTooltip.AddLine=priorAddLine
Nexus.CallboardStatus.GetSummary=realSummary

print('PASS callboard_review_repairs '..checks)
