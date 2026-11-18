-- Callboard review repairs. Offline module behavior only.
-- Stock trackers stay until the Nexus row is a visible committed replacement,
-- and their previous alpha and mouse state are put back exactly.
-- Passive reward discovery does not drive foreign enter/leave handlers or
-- hide an unrelated tooltip, and it does not attach another quest's progress
-- or rewards to the callboard objective. A throwing quest-log getter stays
-- inside the scanner, summary, and panel refresh. Unchanged quest events do
-- not rebuild the HUD. Objective rows hold one whole line of their text (never
-- shorter than the client measures it, nor than the compact design's row); the
-- observed objective's rows are tall enough for the owner to let the stock
-- trackers stand aside, on two rows and on one line alike; and a shortened
-- title is recoverable from its tooltip.
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
-- One whole line each. The 17 this check once stated is the least the
-- Callboard owner accepts of both rows before it lets the stock trackers stand
-- aside (ui/CallboardStatus.lua, ReplacementCovered); the former layout gave
-- it to every row. That decision is asserted as what the owner does, for the
-- objective it observed itself: by the suppression checks right below (two
-- rows) and further down (one line). This check is the fit that holds for
-- every Callboard objective, a summary without a game source included (the
-- later sections of this file). The approved compact Callboard (design draft,
-- Callboard addendum) draws the title on a 20-pixel line and an objective
-- line on an 18-pixel one, and a row is as tall as the client measures its
-- text when that needs more: ui/Panel.lua M.MeasureCallboard reads each
-- text's height at the width it will have (M.WrappedHeight),
-- ui/LayoutMetrics.lua M.Panel lays Block(20, spec.callboardTitleH) and
-- Block(18, spec.callboardDetailH), and PlaceCallboardBox gives each row that
-- height. So a row is never shorter than the height the client reports for its
-- own text, and never under its draft line. One draft pixel is 284 / 420 unit
-- x the layout's font scale, and a draft length is the whole units under or
-- over it where it stands (the layout rounds its cursor, not each length), so
-- the whole units under it are the least it can be (13 and 12 at the
-- reference text size). An objective line that stands on the title's line has
-- the title's row, which is under neither.
local function WholeRow(row,pixels)
 local layout=panel._responsiveLayout
 local unit=284/420*(layout and tonumber(layout.scale) or 1)
 return row~=nil and row:GetHeight()>=row:GetStringHeight() and row:GetHeight()>=math.floor(pixels*unit)
end
check(WholeRow(title,20) and WholeRow(line,18),
 'objective rows are at least their measured text line and the compact design row: title '
 ..tostring(title and title:GetHeight())..'/'..tostring(title and title:GetStringHeight())
 ..' detail '..tostring(line and line:GetHeight())..'/'..tostring(line and line:GetStringHeight()))
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

-- The one-line arrangement is a replacement too. A short observed objective
-- stands with its one progress line on the title's line (the approved compact
-- Callboard), and the owner weighs both rows there as well: the stock trackers
-- stand aside for it as they do for the two-row objective above, and come back
-- exactly when the panel hides. With rows under the owner's minimum the
-- game's tracker and the Nexus line would both show the objective. The
-- two-row objective is observed again afterwards, as the sections below
-- expect it.
do
 local twoRows=objective
 objective={title='Callboard Quest',questId=77,objectiveText='0/2'}
 AdvanceScan()
 Nexus.Panel.Show()
 Nexus.Panel.Refresh()
 AdvanceScan()
 local _,_,_,titleX,titleY=title:GetPoint(1)
 local _,_,_,lineX,lineY=line:GetPoint(1)
 check(panel:IsShown() and title:IsShown() and line:IsShown() and title:GetText()=='Callboard Quest'
  and line:GetText()=='0/2' and lineY==titleY and lineX>titleX,
  'fixture: a short observed objective stands on one line, its progress on the title\'s line')
 check(otf.alpha==0 and tracker.alpha==0 and otf.mouse==false and collapse.mouse==false and tracker.mouse==true,
  'a one-line replacement suppresses the stock trackers as the two-row one does')
 Nexus.Panel.Hide()
 check(otf.alpha==0.35 and otf.mouse==true and tracker.alpha==0.8 and tracker.mouse==true and collapse.mouse==true,
  'hiding the one-line replacement restores the exact tracker alpha and mouse')
 objective=twoRows
 AdvanceScan()
end

-- Review C-01: the same hold and restore under the client convention, in
-- which IsMouseEnabled answers 1 or nil (H.SetClientBooleans,
-- H.ClientBoolean). A numeric 1 is a usable original: the hidden stock
-- tracker and its collapse control lose the mouse while the covered Nexus
-- row shows and answer 1 again after the restore. Offline model; the
-- build-12340 return convention is NOT_RUN.
H.SetClientBooleans('native')
local mouseWrites=0
local function NativeMouse(frame)
 function frame:IsMouseEnabled() return H.ClientBoolean(self.mouse) end
 function frame:EnableMouse(v) mouseWrites=mouseWrites+1;self.mouse=v and true or false end
end
NativeMouse(otf);NativeMouse(tracker);NativeMouse(collapse)
check(otf:IsMouseEnabled()==1 and tracker:IsMouseEnabled()==1 and collapse:IsMouseEnabled()==1,
 'fixture: the stock mouse answers 1 under the client convention')
Nexus.Panel.Show()
Nexus.Panel.Refresh()
H.Advance(0.25)
check(otf.alpha==0 and tracker.alpha==0,'1/nil: the covered replacement suppresses the stock trackers')
check(otf:IsMouseEnabled()==nil and collapse:IsMouseEnabled()==nil and tracker:IsMouseEnabled()==1,
 '1/nil: a numeric 1 mouse original is taken over on the same controls as before')
Nexus.Panel.Hide()
check(otf.alpha==0.35 and otf:IsMouseEnabled()==1 and tracker:IsMouseEnabled()==1
 and collapse:IsMouseEnabled()==1,'1/nil: hiding the panel gives the stock mouse back')
local restoredWrites=mouseWrites
AdvanceScan()
check(mouseWrites==restoredWrites and otf:IsMouseEnabled()==1,'1/nil: a restored mouse is not written again')
H.SetClientBooleans('lua')
Track(otf,otf.alpha,otf.mouse);Track(tracker,tracker.alpha,tracker.mouse);Track(collapse,collapse.alpha,collapse.mouse)

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
-- Approved main panel cleanup ("Wrap and grow ... include ... Callboard. No
-- clipping, ellipsis or arbitrary line cap"): the detail row no longer shows
-- only the first objective line with "+N more". Every line is on the panel,
-- in order, in a box as tall as its text (play_panel_summary S19); the hover
-- keeps listing every complete line as before.
local function RowShows(text,lines)
 local at=1
 for _,want in ipairs(lines) do
  local s,e=text:find(want,at,true)
  if not s then return false end
  at=e+1
 end
 return true
end
local row,rowText=RenderDetail()
check(rowText:find('Kill 3 rats',1,true)==1 and RowShows(rowText,snapshot.lines) and not rowText:find('more',1,true),
 'fixture: the row shows every objective line in order, with no "+N more"')
check(row:GetHeight()+0.5>=row:GetStringHeight(),'fixture: the detail row is as tall as its lines need')
check(InOrder(HoverDetail(),snapshot.lines),'the detail hover shows every complete objective line in order')
snapshot={observed=true,title='Callboard Relay',lines={'Find 2 keys','Unlock the Sunken Vault door'},rewards={}}
row,rowText=RenderDetail()
check(rowText:find('Find 2 keys',1,true)==1 and RowShows(rowText,snapshot.lines) and not rowText:find('more',1,true),
 'fixture: the changed objective is the one rendered')
local changedTip=HoverDetail()
local changedText=table.concat(changedTip,'|')
check(InOrder(changedTip,snapshot.lines) and not changedText:find('Kill 3 rats',1,true)
 and not changedText:find('Ember',1,true) and not changedText:find('Return to the Callboard',1,true),
 'a changed objective shows its own complete lines and none of the earlier ones')
GameTooltip.AddLine=priorAddLine
Nexus.CallboardStatus.GetSummary=realSummary

-- Objective absence and return (offline, synthetic): without an observed
-- objective the title and detail hover areas are hidden with their rows and
-- take no mouse input, a detail hover left open on the vanished objective is
-- closed, and a later objective brings both areas back over its own current
-- rows and text. A literal snapshot at the public GetSummary boundary drives
-- the real Panel.Show/Refresh render and the real hover scripts are used.
-- The harness has no mouse getter or tooltip owner, so the existing Track
-- helper observes the EnableMouse calls of the two hover areas and the
-- tooltip owner is recorded from SetOwner. Native mouse input and tooltip
-- display are not run here.
do
 local titleHit,lineHit=panel._callboardTitleHit,panel._callboardLineHit
 check(titleHit and lineHit,'fixture: the callboard title and detail rows have hover areas')
 Track(titleHit,1,true)
 Track(lineHit,1,true)
 local tipOwner
 local priorSetOwner,priorGetOwner=rawget(GameTooltip,'SetOwner'),rawget(GameTooltip,'GetOwner')
 GameTooltip.SetOwner=function(self,owner,...)
  tipOwner=owner
  if priorSetOwner then return priorSetOwner(self,owner,...) end
 end
 GameTooltip.GetOwner=function() return tipOwner end
 function GameTooltip:AddLine(text,...)
  tipLines[#tipLines+1]=tostring(text)
  return priorAddLine(self,text,...)
 end
 Nexus.CallboardStatus.GetSummary=function() return snapshot end
 -- Issue #168: a hover area starts at its row's left edge, has the row's
 -- height, and is as wide as the text the row shows (plus a small pad),
 -- never wider than the row. A shortened row keeps its whole width.
 local function SamePlace(hitArea,rowText)
  local p1,r1,q1,x1,y1=hitArea:GetPoint(1)
  local ok=hitArea:GetNumPoints()==1 and p1=='TOPLEFT' and r1==rowText and q1=='TOPLEFT' and x1==0 and y1==0
   and hitArea:GetHeight()==rowText:GetHeight()
  local w,box=hitArea:GetWidth(),rowText:GetWidth()
  local textW=rowText:GetStringWidth()
  return ok and w<=box and (textW>=box and w==box or textW<box and w>=textW and w<box)
 end
 local function HoverTitle()
  tipLines={}
  titleHit:GetScript('OnEnter')(titleHit)
  local shown=tipLines
  local leave=titleHit:GetScript('OnLeave')
  if leave then leave(titleHit) end
  return shown
 end
 snapshot={observed=true,title='Callboard Ember Watch',
  lines={'Light 4 braziers','Guard the Ember Gate'},rewards={}}
 RenderDetail()
 check(titleHit:IsShown() and lineHit:IsShown() and titleHit:IsMouseEnabled()==true
  and lineHit:IsMouseEnabled()==true,'fixture: an observed objective has shown, mouse-enabled hover areas')
 tipLines={}
 lineHit:GetScript('OnEnter')(lineHit)
 check(GameTooltip:IsShown() and tipOwner==lineHit and InOrder(tipLines,snapshot.lines),
  'fixture: the detail hover is open on the current objective')
 snapshot={observed=false,lines={},rewards={}}
 Nexus.Panel.Show()
 Nexus.Panel.Refresh()
 H.Advance(0.25)
 check(panel:IsShown(),'fixture: the panel stays shown without an objective')
 check(not panel._callboardLabel:IsShown() and not panel._callboardTitle:IsShown()
  and not panel._callboardLine:IsShown() and not panel._callboardIcon:IsShown(),
  'without an objective the callboard label, title, detail and icon are hidden')
 check(not titleHit:IsShown() and not lineHit:IsShown(),
  'without an objective the title and detail hover areas are hidden with their rows')
 check(titleHit:IsMouseEnabled()==false and lineHit:IsMouseEnabled()==false,
  'without an objective the title and detail hover areas take no mouse input')
 check(not GameTooltip:IsShown(),'the detail hover left open on the vanished objective is closed')
 check(#HoverTitle()==0 and #HoverDetail()==0 and not GameTooltip:IsShown(),
  'without an objective neither hover shows text of the earlier objective')
 local newTitle='Callboard Return '..string.rep('Z',60)
 snapshot={observed=true,title=newTitle,
  lines={'Report to the Warden','Carry the sealed letter'},rewards={}}
 local _,backText=RenderDetail()
 check(titleHit:IsShown() and lineHit:IsShown() and titleHit:IsMouseEnabled()==true
  and lineHit:IsMouseEnabled()==true,'a returning objective shows both hover areas and they take the mouse again')
 check(panel._callboardTitle:IsShown() and panel._callboardTitle:GetText()==newTitle
  and backText:find('Report to the Warden',1,true)==1 and RowShows(backText,snapshot.lines)
  and not backText:find('more',1,true)
  and not backText:find('braziers',1,true),'the returning rows show the current objective text (every line, no "+N more")')
 check(SamePlace(titleHit,panel._callboardTitle) and SamePlace(lineHit,panel._callboardLine)
  and WholeRow(panel._callboardTitle,20) and WholeRow(panel._callboardLine,18),
  'the returning hover areas cover the current title and detail rows, each a whole line of its text')
 local titleTip=table.concat(HoverTitle(),'|')
 check(titleTip:find(newTitle,1,true)~=nil and not titleTip:find('Ember Watch',1,true),
  'the returning title hover shows the complete current title and not the earlier one')
 local backTip=HoverDetail()
 local backTipText=table.concat(backTip,'|')
 check(InOrder(backTip,snapshot.lines) and not backTipText:find('braziers',1,true)
  and not backTipText:find('Ember Gate',1,true) and not backTipText:find('Ember Watch',1,true),
  'the returning detail hover shows only the current complete lines')
 GameTooltip.AddLine=priorAddLine
 GameTooltip.SetOwner,GameTooltip.GetOwner=priorSetOwner,priorGetOwner
 Nexus.CallboardStatus.GetSummary=realSummary
end

-- Disappearing-row tooltip ownership (offline, synthetic): an objective row
-- that vanishes while its own complete-text hover is open closes that
-- tooltip only while the tooltip still reports the row as its owner. Once
-- the tooltip has passed to another owner, a readable other owner, an owner
-- the tooltip does not report and an owner read that raises all leave that
-- other owner's tooltip open, and the vanished row keeps no hover state
-- either way. Literal snapshots at the public GetSummary boundary drive the
-- real Panel.Show/Refresh render and the real row hover scripts open the
-- tooltips. GameTooltip SetOwner and GetOwner are recorded here; its Hide
-- calls are counted by the counter installed at the top of this file.
-- Native tooltip ownership transfer is not run here.
do
 local titleHit,lineHit=panel._callboardTitleHit,panel._callboardLineHit
 check(titleHit and lineHit,'fixture: the callboard title and detail rows still have hover areas')
 local foreign=CreateFrame('Frame',nil,UIParent)
 local tipOwner,ownerMode
 local ownerReads=0
 local priorSetOwner,priorGetOwner=rawget(GameTooltip,'SetOwner'),rawget(GameTooltip,'GetOwner')
 GameTooltip.SetOwner=function(self,owner,...)
  tipOwner=owner
  if priorSetOwner then return priorSetOwner(self,owner,...) end
 end
 GameTooltip.GetOwner=function()
  ownerReads=ownerReads+1
  if ownerMode=='raise' then error('synthetic unreadable tooltip owner') end
  if ownerMode=='unreported' then return nil end
  return tipOwner
 end
 function GameTooltip:AddLine(text,...)
  tipLines[#tipLines+1]=tostring(text)
  return priorAddLine(self,text,...)
 end
 Nexus.CallboardStatus.GetSummary=function() return snapshot end
 -- Render an objective, open one row hover with its real OnEnter, optionally
 -- pass the open tooltip to the other owner, then render the objective away
 -- while owner reads follow the given mode. Returns the Hide calls and the
 -- owner reads of that vanishing render.
 local function VanishWhileHovered(hitArea,snap,transfer,mode)
  ownerMode=nil
  snapshot=snap
  RenderDetail()
  check(hitArea:IsShown() and hitArea:IsMouseEnabled()==true,
   'fixture: the observed row hover area is shown and takes the mouse')
  hitArea:GetScript('OnEnter')(hitArea)
  check(GameTooltip:IsShown() and tipOwner==hitArea,'fixture: the row opened its own complete-text hover')
  if transfer then
   GameTooltip:SetOwner(foreign,'ANCHOR_RIGHT')
   GameTooltip:Show()
   check(GameTooltip:IsShown() and tipOwner==foreign,'fixture: the open tooltip passed to another owner')
  end
  local hides,reads=tooltipHidden,ownerReads
  ownerMode=mode
  snapshot={observed=false,lines={},rewards={}}
  Nexus.Panel.Show()
  Nexus.Panel.Refresh()
  H.Advance(0.25)
  ownerMode=nil
  check(panel:IsShown() and not hitArea:IsShown() and hitArea:IsMouseEnabled()==false,
   'fixture: the vanished row hover area is hidden and takes no mouse input')
  return tooltipHidden-hides,ownerReads-reads
 end
 -- The real scripts of a vanished area reach no earlier hover: OnLeave hides
 -- nothing and OnEnter opens nothing.
 local function NoStaleHover(hitArea)
  local hides,owner=tooltipHidden,tipOwner
  tipLines={}
  hitArea:GetScript('OnLeave')(hitArea)
  hitArea:GetScript('OnEnter')(hitArea)
  return tooltipHidden==hides and tipOwner==owner and #tipLines==0
 end
 local hides,reads=VanishWhileHovered(lineHit,{observed=true,title='Callboard Owner Watch',
  lines={'Ring the north bell','Ring the south bell'},rewards={}},false,nil)
 check(hides==1 and not GameTooltip:IsShown(),
  'a vanishing detail row still closes its own complete-text tooltip, once')
 check(NoStaleHover(lineHit),'the detail row that closed its own tooltip keeps no hover state or lines')
 hides=VanishWhileHovered(titleHit,{observed=true,title='Callboard Owner '..string.rep('Q',60),
  lines={'Hold the bridge'},rewards={}},false,nil)
 check(hides==1 and not GameTooltip:IsShown(),
  'a vanishing shortened title still closes its own complete-text tooltip, once')
 check(NoStaleHover(titleHit),'the title that closed its own tooltip keeps no hover state')
 hides=VanishWhileHovered(lineHit,{observed=true,title='Callboard Owner Watch',
  lines={'Light the east beacon','Light the west beacon'},rewards={}},true,nil)
 check(hides==0 and GameTooltip:IsShown() and GameTooltip:GetOwner()==foreign,
  'a vanishing detail row leaves open a tooltip now held by another readable owner')
 check(NoStaleHover(lineHit) and GameTooltip:IsShown(),
  'the vanished detail row keeps no hover state that could close the tooltip of another owner')
 hides,reads=VanishWhileHovered(lineHit,{observed=true,title='Callboard Owner Watch',
  lines={'Seal the crypt','Report to the Warden'},rewards={}},true,'raise')
 check(reads>=1,'fixture: the vanishing render made an owner read that raised')
 check(hides==0 and GameTooltip:IsShown() and GameTooltip:GetOwner()==foreign,
  'a vanishing detail row does not hide the tooltip of another owner when the owner read raises')
 check(NoStaleHover(lineHit) and GameTooltip:IsShown(),
  'after a raising owner read the vanished detail row keeps no hover state or lines')
 hides,reads=VanishWhileHovered(titleHit,{observed=true,title='Callboard Bridge '..string.rep('Q',60),
  lines={'Hold the bridge'},rewards={}},true,'unreported')
 check(reads>=1,'fixture: the vanishing render made an owner read that reported no owner')
 check(hides==0 and GameTooltip:IsShown() and GameTooltip:GetOwner()==foreign,
  'a vanishing shortened title does not hide the tooltip of another owner when no owner is reported')
 check(NoStaleHover(titleHit) and GameTooltip:IsShown(),
  'after an unreported owner the vanished title keeps no hover state')
 GameTooltip.AddLine=priorAddLine
 GameTooltip.SetOwner,GameTooltip.GetOwner=priorSetOwner,priorGetOwner
 Nexus.CallboardStatus.GetSummary=realSummary
end

-- Updated client (2026-11 capture; second Spec review and Root
-- probe_callboard_transition.lua): with no ObjectivesService, the board the
-- provider publishes (ProjectEbonhold.Callboard.board.quests, state 1
-- accepted / 2 complete, Callboard.enabled) is the objective source. A board
-- that names no single objective is a refusal in the same session: the
-- objective remembered from an earlier board is not revived from the tracker
-- text, and the stock tracker is given back exactly.
do
 local CB=Nexus.CallboardStatus
 local priorService=ProjectEbonhold.ObjectivesService
 ProjectEbonhold.ObjectivesService=nil
 GetNumQuestLogEntries=function() return 0 end
 local function Board(quests,enabled)
  ProjectEbonhold.Callboard={enabled=enabled~=false,board=quests and {quests=quests} or nil}
 end
 local function Q(id,title,state) return {questId=id,title=title,state=state,objectives='Open it',done=0,max=1} end
 Board(nil);AdvanceScan();CB.PublishCoverage()
 local baseAlpha,baseMouse=tracker.alpha,tracker.mouse
 check(CB.GetSummary().observed~=true,'board: no board, no objective')
 Board({Q(601,'One More Door',1)});AdvanceScan()
 local s=CB.GetSummary()
 check(s.observed==true and s.questId==601 and s.title=='One More Door',
  'board: the accepted quest the tracker shows is the objective')
 Board({Q(601,'One More Door',1),Q(602,'Another Errand',2),Q(604,'Old Errand',3)});AdvanceScan()
 s=CB.GetSummary()
 check(s.observed==true and s.questId==601,'board: the tracker title selects among several accepted or complete quests')
 check(#(s.rewards or {})==0,'board: no reward row is invented from the board')
 for _,case in ipairs({
  {'disabled',function() Board({Q(601,'One More Door',1)},false) end},
  {'empty',function() Board({}) end},
  {'no board',function() Board(nil) end},
  {'duplicate title',function() Board({Q(601,'One More Door',1),Q(603,'One More Door',1)}) end},
  {'duplicate id',function() Board({Q(601,'One More Door',1),Q(601,'Another Errand',1)}) end},
  {'malformed row',function() Board({Q(601,'One More Door',1),'bad row'}) end},
  {'another quest only',function() Board({Q(602,'Another Errand',1)}) end},
  {'unreadable',function()
    ProjectEbonhold.Callboard=setmetatable({},{__index=function() error('synthetic board raise') end})
   end},
 }) do
  Board({Q(601,'One More Door',1)});AdvanceScan()
  check(CB.GetSummary().observed==true,'board '..case[1]..': fixture first observes the valid board')
  case[2]()
  check(CB.GetSummary().observed~=true,'board '..case[1]..': the same session does not revive the remembered objective')
  AdvanceScan()
  check(CB.GetSummary().observed~=true,'board '..case[1]..': nor does the next scan')
  CB.PublishCoverage()
  check(tracker.alpha==baseAlpha and tracker.mouse==baseMouse,'board '..case[1]..': the stock tracker keeps its own alpha and mouse')
 end
 -- Third Spec review (Root probe_callboard_bag_precedence): a reward bag the
 -- old tracker still shows, holding the earlier objective, never overrides a
 -- deciding current board.
 local priorBag=otf.rewardBagFrame
 otf:Show()
 otf.rewardBagFrame={objectiveData={questId=601,title='One More Door'}}
 for _,case in ipairs({
  {'disabled',function() Board({Q(601,'One More Door',1)},false) end},
  {'empty',function() Board({}) end},
  {'malformed row',function() Board({Q(601,'One More Door',1),'bad row'}) end},
  {'duplicate title',function() Board({Q(601,'One More Door',1),Q(603,'One More Door',1)}) end},
 }) do
  Board({Q(601,'One More Door',1)});AdvanceScan()
  check(CB.GetSummary().observed==true,'bag '..case[1]..': fixture first observes the valid board')
  case[2]()
  check(CB.GetSummary().observed~=true,'bag '..case[1]..': the retained reward bag does not override the current board')
  AdvanceScan()
  check(CB.GetSummary().observed~=true,'bag '..case[1]..': nor after the next scan')
 end
 -- Legacy control: with no Callboard table at all the reward bag keeps its
 -- earlier place as an objective source.
 ProjectEbonhold.Callboard=nil
 AdvanceScan()
 local legacy=CB.GetSummary()
 check(legacy.observed==true and legacy.questId==601,'bag legacy control: without a board the shown reward bag is still read')
 otf.rewardBagFrame=priorBag
 ProjectEbonhold.Callboard=nil
 ProjectEbonhold.ObjectivesService=priorService
 AdvanceScan()
end
print('PASS callboard_review_repairs '..checks)
