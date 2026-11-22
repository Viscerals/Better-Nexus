-- The Orb history is a page of the Orb window (NexusOrbRunLog under
-- NexusOrbPanel), not a second window. Moving between "Run controls" and
-- "Run history" only shows and hides frames: it spends, starts, confirms and
-- cancels nothing (Start/Stop rework 2026-11-19: Start is one fixed control
-- with no armed new-run review). Closing the
-- window (Close or Escape) still cancels that review, as before. The history
-- bands do not overlap, the window stays on the visible UI at common screen
-- sizes and UI scales, and a long recorded value is cut on a character
-- boundary, with pipes escaped after the cut, while the tooltips and details
-- keep the complete value. Real runtime, real panel
-- handlers, fake game services, synthetic data. Offline geometry under stated
-- font models only: native font rendering and pixel fit are NOT proven here.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function button(label,parent)
 for _,b in ipairs(H.frames)do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent)then return b end
 end
 error('button not found: '..label)
end
local function frozen()
 local s=M.Status()
 return table.concat({tostring(s.state),tostring(s.spent),tostring(s.limit),tostring(s.reserved),
  tostring(s.running),tostring(s.pending),tostring(H.Count('orb-spend')),
  tostring(Nexus.RecomputeStats().autoEnabled)},'|')
end
local tip={}
GameTooltip.SetText=function(_,t)tip[#tip+1]=tostring(t)end
GameTooltip.AddLine=function(_,t)tip[#tip+1]=tostring(t)end
local function hover(hit)tip={};hit:GetScript('OnEnter')(hit);return table.concat(tip,'\n')end

-- 1. A finished run, so the primary control can be armed for a new run.
H.OrbPlan({{spellId=410002,quality=2,stacks=14}})
H.granted={['Disposable A']={},['Disposable B']={}}
for _=1,4 do
 table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
 table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
end
O.charges=20;H.Notify();A.Poll()
H.Approve(2,false,false)
for step=1,2 do
 for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
 check(M.Status().state=='WAIT_OFFER','step '..step..': the run requested its own Orb')
 H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.Result(410002,2)
end
check(M.Status().state=='FINISHED','the settled run finished: '..tostring(M.Status().state))

SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);Nexus.OrbPanel.Refresh()
local runTab,historyTab=button('Run controls',f),button('Run history',f)
check(Nexus.OrbPanel.Page()=='run','the window opens on its run page')
check(runTab._nexusSelectedBar and runTab._nexusSelectedBar:IsShown(),'the open page is marked by a bar, not by colour alone')
check(f.start:GetText()=='Start','Start keeps its fixed words')
local armed=frozen()

-- 2. Page changes are only page changes.
historyTab:Click()
local log=assert(NexusOrbRunLog,'the history page keeps its compatible name')
check(log:GetParent()==f,'the history is a page of the Orb window, not its own window')
check(Nexus.OrbPanel.Page()=='history' and log:IsShown(),'Run history shows the history page')
check(not f.start:IsShown() and not f.stop:IsShown() and not f.limit:IsShown(),'the run controls are hidden there')
check(historyTab._nexusSelectedBar:IsShown() and not runTab._nexusSelectedBar:IsShown(),'the bar moves with the page')
check(log.page:GetText()=='Operations 1-2 of 2','the history shows the finished run: '..log.page:GetText())
check(frozen()==armed,'opening the history changes nothing in the run')
runTab:Click();Nexus.OrbPanel.Refresh()
check(Nexus.OrbPanel.Page()=='run' and not log:IsShown() and f.start:IsShown(),'Run controls returns to the run page')
check(f.start:GetText()=='Start' and frozen()==armed,'page changes start or confirm nothing')
Nexus.OrbPanel.ShowLog();Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
check(f.start:GetText()=='Start' and frozen()==armed,'ShowLog and Show are page changes too')

-- 3. Close on the history page closes the window; reopening is disarmed.
Nexus.OrbPanel.ShowLog()
button('Close',log):Click()
check(not f:IsShown() and not log:IsShown(),'Close on the history page closes the whole window')
Nexus.OrbPanel.Show()
check(f.start:GetText()=='Start','reopening shows the same fixed Start')
check(frozen()==armed,'and starts, confirms or spends nothing')

-- 4. Escape (UISpecialFrames) does the same.
Nexus.OrbPanel.ShowLog()
local listed=false
for _,name in ipairs(UISpecialFrames)do
 if name=='NexusOrbPanel' then listed=true end
 if _G[name] and _G[name].IsShown and _G[name]:IsShown() then _G[name]:Hide() end
end
check(listed and not f:IsShown() and not log:IsShown(),'Escape closes the window and its history page')
Nexus.OrbPanel.ShowLog()
check(f:IsShown() and log:IsShown(),'the history reopens directly')
Nexus.OrbPanel.Show()
check(f.start:GetText()=='Start' and frozen()==armed,'Escape changed nothing')

-- 5. Bands of the history page, at their current offsets, do not overlap.
local real=M.RunLog
local entries={}
local function serve(which,from,count)
 local page={}
 local first=math.max(1,math.floor(tonumber(from) or 1))
 local last=count and math.min(#entries,first+count-1) or #entries
 for i=first,last do page[#page+1]=entries[i] end
 return {sessionOnly=true,which=which or 'current',runId=9,startedAt=100,build='test',character='Tester-Realm',
  wishlist='Raid plan',limit=40,
  state='PAUSED',reason='Paused',spent=#entries,reserved=1,revision=#entries,total=#entries,
  entries=page,hasCurrent=true,hasPrevious=false,truncated=#entries>=30}
end
local function fill(n,long)
 entries={}
 for i=1,n do
  entries[i]={serial=i,ordinal=i,at=100+i,state='confirmed',sourceKey='410001:1',
   sourceName=long and string.rep('Ünusually Lóng Echo Name ',6) or 'Disposable A',sourceQuality=1,sourceCopies=2,
   offered={{spellId=410002,quality=2,name='Desired A'}},selectedKey='410002:2',selectionKind='TARGET',
   selectionReason='needed target',obtained='410002:2',confirmedAt=101+i}
 end
end
M.RunLog=serve
fill(0);log=Nexus.OrbPanel.ShowLog()
check(log.page:GetText()=='No operations recorded','an empty history says so: '..log.page:GetText())
check(not log.prev:IsEnabled() and not log.next:IsEnabled(),'and offers no paging')
fill(400,true);log:Hide();log=Nexus.OrbPanel.ShowLog()
check(log.page:GetText():find('Operations 1-8 of 400',1,true)==1,'a large history pages eight at a time: '..log.page:GetText())
check(log.rows[1].source:GetText():find('...',1,true)~=nil,'a long name is shortened in its cell')
log.rows[1]:Click()
local rect=function(region)return G.Rect(region,log)end
local root=rect(log)
local copy,close=button('Copy report',log),button('Close',log)
local groups={
 {name='selector and header',items={log.current,log.previous,log.header}},
 {name='warning',items={log.warning}},
 {name='headings',items={log.columns}},
 {name='rows',items=log.rows},
 {name='details',items={log.detailScroll}},
 {name='footer',items={log.page,log.prev,log.next,copy,close}},
 {name='note',items={log.note}},
}
local previousBottom=0
for _,group in ipairs(groups)do
 local top,bottom=math.huge,-math.huge
 for _,item in ipairs(group.items)do
  local r=rect(item)
  check(G.Inside(r,root),group.name..' stays inside the page: '..G.Text(r))
  top=math.min(top,r[2]);bottom=math.max(bottom,r[4])
 end
 check(top>=previousBottom,group.name..' starts below the band above it: '..top..' after '..previousBottom)
 previousBottom=bottom
end
check(G.Apart(rect(log.header),rect(log.previous)),'the header sits beside the run selector')
for i,a in ipairs(groups[6].items)do for j,b in ipairs(groups[6].items)do
 if i<j then check(G.Apart(rect(a),rect(b)),'footer controls do not overlap: '..i..'/'..j) end
end end
check(log.next:IsEnabled(),'Next is offered while pages remain')
button('Next',log):Click()
check(log.page:GetText():find('Operations 9-16 of 400',1,true)==1,'paging moves one page: '..log.page:GetText())

-- 6. New results do not move the reader; long header and warning text stays
-- reachable at a larger font (the 16 px face model).
button('Previous',log):Click()
fill(408,true);log:GetScript('OnUpdate')(log,1)
check(log.page:GetText():find('Operations 1-8 of 408',1,true)==1,'new operations do not move the page: '..log.page:GetText())
check(log.note:GetText():find('new operation',1,true)~=nil,'they are announced instead: '..log.note:GetText())
G.UseFont(G.MODELS.px16)
-- Either the text fits its box under the model, or hovering shows all of it.
local function reachable(fs,hit)
 local value=fs:GetText()
 local fits=G.Rows(value,fs:GetWidth(),G.model.char)*G.model.line<=fs:GetHeight()
 return fits or hover(hit):find(value,1,true)~=nil
end
check(log.warning:GetText():find('unresolved operation',1,true)~=nil,'the warning states the unresolved operation')
check(reachable(log.warning,log.warningHit),'the warning is complete on screen or on hover')
check(reachable(log.header,log.headerHit),'the header is complete on screen or on hover')
M.RunLog=real
log:Hide()

-- 7. A long recorded name is cut on a character boundary; the tooltip has it all.
local function utf8(s)
 local i=1
 while i<=#s do
  local c=s:byte(i);local n=c<128 and 1 or c>=240 and 4 or c>=224 and 3 or c>=192 and 2 or 0
  if n==0 then return false end
  for k=1,n-1 do local b=s:byte(i+k);if not b or b<128 or b>191 then return false end end
  i=i+n
 end
 return true
end
local longName='Plan '..string.rep('€',120)..' end'
local status=M.Status
M.Status=function(...)
 local s=status(...);local out={}
 for k,v in pairs(s)do out[k]=v end
 out.assignment={};for k,v in pairs(s.assignment or {})do out.assignment[k]=v end
 out.assignment.name=longName;out.assignment.state='ready'
 return out
end
Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
local plan=f.plan:GetText()
M.Status=status
check(utf8(plan),'the shortened name is still valid text')
check(plan:find('...',1,true)~=nil and #plan<#('Assigned Wishlist: '..longName),'and says it was shortened')
check(hover(f.planHit):find(longName,1,true)~=nil,'the complete name is in the tooltip')
f.status:SetText(string.rep('A long refusal that explains what happened. ',12))
check(hover(f.statusHit):find('A long refusal',1,true)~=nil,'a long status is complete on hover')

-- 7b. History values. Each sample cuts inside a letter or an escaped pipe with
-- the inherited projection (escape, then cut bytes). Now a bounded value is
-- cut on a character boundary, escaped after the cut and marked "...", and a
-- cell is cut from the recorded text; the row tooltip, the details and the
-- header tooltip keep the complete recorded value.
local V=Nexus.OrbHistory
local function byteCut(value,limit)return((tostring(value):gsub('|','||'):gsub('%c',' ')):sub(1,limit))end
local function oddPipe(s)return(s:gsub('||','')):find('|',1,true)~=nil end
local CYR='a'..string.rep('Ж',40)
check(not utf8(byteCut(CYR,60)),'sample: a 60-byte cut lands inside a letter')
local shown,cut=V.Display(CYR,60)
check(cut and utf8(shown) and #shown<=60 and shown:sub(-3)=='...','Display cuts on a letter boundary, within its bound, and says so: '..shown)
check(V.Display(CYR)==CYR,'without a bound Display keeps the whole value')
local PIPES='b'..string.rep('a|',40)
check(oddPipe(byteCut(PIPES,60)),'sample: a 60-byte cut splits an escaped pipe')
shown=V.Display(PIPES,60)
check(not oddPipe(shown) and #shown<=60 and shown:sub(-3)=='...','pipes are doubled after the cut, so no pair is split: '..shown)
check(V.Display(PIPES)==(PIPES:gsub('|','||')),'the whole value keeps every pipe doubled')
local EURO=string.rep('€',40)
check(not utf8(EURO:sub(1,29)),'sample: the inherited 29-byte cell cut lands inside a letter')
local cell,short=V.Ellipsis(EURO,32)
check(short and cell==string.rep('€',29)..'...','Ellipsis counts letters and never splits one: '..cell)
local NAME='x'..string.rep('Ж',25)..'|'..string.rep('Ж',20)..' tail'
check(not utf8(byteCut(NAME,60)) and oddPipe(Nexus.LayoutMetrics.Truncate(byteCut(NAME,60),30)),
 'sample: the inherited label cuts a letter, and its cell cut splits the escaped pipe')
local REASON='Причина '..string.rep('ж',40)
check(not utf8(byteCut(REASON,40)),'sample: the inherited 40-byte reason cut lands inside a letter')
local NOTE=string.rep('Заметка | ',30)
local WISH='План '..string.rep('Ж',40)
local NAME2='Предложенное Эхо с очень длинным именем | конец'
local custom={
 {serial=1,ordinal=1,at=101,state='confirmed',sourceKey='410001:1',sourceName=NAME,sourceQuality=1,sourceCopies=2,
  offered={{spellId=410002,quality=2,name='Desired A'}},selectedKey='410002:2',selectionKind='CUSTOM',
  selectionReason=REASON,obtained='410002:2',confirmedAt=102,reason=NOTE},
 {serial=2,ordinal=2,at=103,state='selected',sourceKey='410003:0',sourceName='Disposable B',sourceQuality=0,sourceCopies=2,
  offered={{spellId=410004,quality=3,name=NAME2}},selectedKey='410004:3',selectionKind='TARGET',selectionReason='needed target'},
}
M.RunLog=function(which,from,count)
 local page={}
 local first=math.max(1,math.floor(tonumber(from) or 1))
 local last=count and math.min(#custom,first+count-1) or #custom
 for i=first,last do page[#page+1]=custom[i] end
 return {sessionOnly=true,which=which or 'current',runId=11,startedAt=100,build='test',character='Tester-Realm',
  wishlist=WISH,limit=5,state='PAUSED',reason='Paused',spent=1,reserved=1,revision=2,total=#custom,
  entries=page,hasCurrent=true,hasPrevious=false}
end
log=Nexus.OrbPanel.ShowLog()
local sourceCell=log.rows[1].source:GetText()
check(utf8(sourceCell) and not oddPipe(sourceCell),'the source cell is valid text with its pipe still escaped: '..sourceCell)
check(sourceCell:match('^[^\n]*'):sub(-5)=='||...' and sourceCell:find('\nUncommon',1,true),
 'it is cut from the recorded name, says so, and keeps its rarity line')
local reasonCell=log.rows[1].reason:GetText()
check(utf8(reasonCell) and #reasonCell<=40 and reasonCell:sub(-3)=='...','a long recorded reason is cut on a letter boundary in its cell')
local proposedCell=log.rows[2].replacement:GetText()
check(utf8(proposedCell) and proposedCell:find('...\nEpic - proposed',1,true),'a shortened proposed name keeps its marker: '..proposedCell)
local rowTip=hover(log.rows[1])
check(rowTip:find('Replaced Echo: '..V.Display(NAME)..' (Uncommon)',1,true) and rowTip:find('Why selected: '..REASON,1,true)
 and rowTip:find('Recorded note: '..V.Display(NOTE),1,true) and utf8(rowTip) and not oddPipe(rowTip),
 'the row tooltip keeps the complete recorded name, reason and note: '..rowTip)
check(hover(log.rows[2]):find('Replacement: '..V.Display(NAME2)..' (proposed) (Epic) - selected, not received',1,true),
 'a proposed replacement is complete in its tooltip and still marked proposed')
log.rows[1]:Click()
local detailText=log.details:GetText()
check(detailText:find('Consumed source: '..V.Display(NAME)..' (Uncommon)',1,true) and detailText:find('Why: '..REASON,1,true)
 and detailText:find('Recorded note: '..V.Display(NOTE),1,true),'the details keep the complete recorded values')
log.rows[2]:Click()
check(log.details:GetText():find('Offered: '..V.Display(NAME2)..' (Epic) [selected]',1,true),'the details name the complete proposed offer')
log.rows[2]:Click()
local headerText=log.header:GetText()
check(utf8(headerText) and headerText:find('...',1,true) and not headerText:find(WISH,1,true),'the header bounds a long Wishlist name on a letter boundary')
check(hover(log.headerHit):find(WISH,1,true),'and its tooltip has the complete name')
M.RunLog=real;log:Hide()

-- 8. The window stays on the visible UI. UIParent is 768 units high at UI
-- scale 1 (wider on wide screens), larger at a smaller UI scale, smaller when
-- an addon scales UIParent above 1. The model resolves the window's anchor.
local function corner(fr)
 local p=fr.points[#fr.points]
 if p and p[1]=='TOPLEFT' and p[3]=='BOTTOMLEFT' then return p[4],p[5] end
 local s=fr:GetScale()
 return (UIParent:GetWidth()/s-fr:GetWidth())/2,(UIParent:GetHeight()/s+fr:GetHeight())/2
end
f.GetLeft=function(self)return (corner(self))end
f.GetTop=function(self)local _,t=corner(self);return t end
local function visible(label,minimum)
 local l,t=corner(f);local s=f:GetScale()
 local box={l*s,(UIParent:GetHeight()-t*s),(l+f:GetWidth())*s,UIParent:GetHeight()-(t-f:GetHeight())*s}
 check(G.Inside(box,{0,0,UIParent:GetWidth(),UIParent:GetHeight()},0.5),label..': the whole window is on the UI '..G.Text(box))
 check(s>=minimum,label..': the scale stays readable: '..s)
end
local advancedButton=button('Advanced',f)
for _,case in ipairs({
 {'1280x720 at UI scale 1',1365.33,768,1},{'1366x768 at UI scale 1',1366,768,1},
 {'1920x1080 at UI scale 1',1365.33,768,1},{'1920x1080 at UI scale 0.64',2133.33,1200,1},
 {'1024x768 (4:3)',1024,768,1},{'1280x1024 (5:4)',960,768,1},
 {'1366x768, UIParent scaled 1.15',1187.83,667.83,0.85},{'1280x720, UIParent scaled 1.25',1092.27,614.4,0.85},
})do
 UIParent:SetSize(case[2],case[3])
 Nexus.OrbPanel.Show();f:ClearAllPoints();f:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',math.min(700,case[2]-640),500)
 Nexus.OrbPanel.Refresh();visible(case[1]..', run page',case[4])
 -- Start/Stop rework (2026-11-19): no Advanced exclusions on the run page.
 check(not f.advanced:IsShown() and not f.advancedToggle:IsShown(),'no Advanced box or toggle')
 Nexus.OrbPanel.ShowLog();visible(case[1]..', history page',case[4])
 f:Hide()
end
-- The UI scale changes while the window is open: the next refresh refits it.
UIParent:SetSize(1366,768);Nexus.OrbPanel.Show()
UIParent:SetSize(1092.27,614.4);f:GetScript('OnUpdate')(f,1)
visible('UI scale changed while open',0.85)
f:Hide()
check(frozen()==armed,'fitting, paging and reading changed nothing in the run')
print('PASS orb_history_embedded: one window with a history page; page changes act on nothing; bands apart; character-safe values complete in tooltips; window on screen checks='..checks)
