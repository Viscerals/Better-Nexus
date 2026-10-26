-- Issue #163: real Settings routes retain the owners' consent and write seams.
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
dofile('ui/SettingsWindow.lua') -- integration TOC wiring is owned by the coordinator
local settings=assert(Nexus.SettingsWindow,'Settings module exists')
local function check(ok,why) assert(ok,why) end
local baseline=F.Serialize(NexusDB)
local actions=#H.actions
local sends=#H.sent
UIParent:SetSize(420,600) -- compact viewport; native pixels/125% font remain unverified
for _,category in ipairs(settings.Categories()) do
    local rows=settings.Rows(category)
    check(type(rows)=='table' and #rows>0,category..' has real content')
    settings.Show(category)
    settings.Select(category)
end
check(F.Serialize(NexusDB)==baseline,'opening/navigating Settings does not write saved data')
check(#H.actions==actions and #H.sent==sends,'opening Settings does not automate or send')
check(settings.IsShown(),'Settings is an actual visible window')
local window=assert(NexusSettingsWindow)
check(window:GetWidth()<=420 and window:GetHeight()<=600,'window geometry fits compact viewport')
local syncTab
for _,child in ipairs(window.children) do if child:GetText()=='Sync' then syncTab=child end end
check(syncTab and syncTab:GetWidth()==118,'compact Sync category is reachable')
local tabCopy={}
local originalAddLine=GameTooltip.AddLine
GameTooltip.AddLine=function(_,line) tabCopy[#tabCopy+1]=line end
syncTab.scripts.OnEnter(syncTab)
GameTooltip.AddLine=originalAddLine
check(tabCopy[1]=='Share & Sync','short category tab exposes its complete label')
check(settings.ShowSection('sync') and settings.IsShown(),'Manage can open a named section')
check(settings.Select('not-a-section')==false,'unknown section does not invoke a setting')
local sync=settings.Rows('sync')
check(sync[1].text:find('Manual',1,true),'Sync displays the current stored mode')
local automation=settings.Rows('automation')
local foundAuto=false
for _,row in ipairs(automation) do
    if row.text:find('Auto',1,true) then foundAuto=true end
end
check(foundAuto,'Automation uses current owned rows')
local appearance=settings.Rows('appearance')
local selected
for i,row in ipairs(appearance) do
    if row.text:find('Slate',1,true) and row.action then selected=i;break end
end
check(selected,'Appearance includes the owned style choice')
settings.Select('appearance')
check(F.Serialize(NexusDB)==baseline,'mere style selection page is read only')
check(settings.Activate(selected,appearance[selected].text),'only explicit style click invokes owner')
check(Nexus.Theme.Current().style=='slate','owned setter applied selected style')
local helpRows=settings.Rows('support')
check(helpRows[1].text=='Guided setup' and helpRows[2].text=='Welcome information',
    'guided coach and informational Welcome are named as different routes')
local guideOpened=0
local realGuide=Nexus.Help.OpenGuide
Nexus.Help.OpenGuide=function() guideOpened=guideOpened+1 end
settings.Select('support')
check(settings.Activate(1,helpRows[1].text) and guideOpened==1,
    'guided setup action uses the actual Help coach route')
Nexus.Help.OpenGuide=realGuide
local longLabel='Français - '..string.rep('Écho mémorisé ',5)
local longDetail=string.rep('Cette option reste explicite et demande confirmation. ',2)
local previousLanguage=Nexus.Panel.LanguageMenuItems
Nexus.Panel.LanguageMenuItems=function()
    local items={}
    for i=1,4 do items[i]={text=longLabel..i,tooltipText=longDetail,func=function() end} end
    items[5]={text=string.rep('État inconnu / ',10),disabled=true,tooltipText=longDetail}
    return items
end
settings.ShowSection('language')
local shown={}
for _,child in ipairs(window.children) do
    if child._nexusFullLabel then shown[#shown+1]=child end
end
check(#shown==3,'three roomy rows per page rather than four clipped rows')
check(shown[1]._nexusFullLabel:GetText()==longLabel..'1',
    'full localized label is rendered without truncation')
check(shown[1]:GetHeight()>=50 and shown[1]._nexusFullLabel:GetWidth()>=330,
    'action row gives large text two lines')
check(shown[1]._nexusDetail:GetHeight()>=30 and shown[1]._nexusDetail:GetWidth()>=330,
    'wrapped consequence text has reserved vertical room')
local captured={}
local oldAddLine=GameTooltip.AddLine
GameTooltip.AddLine=function(_,line) captured[#captured+1]=line end
shown[1].scripts.OnEnter(shown[1])
GameTooltip.AddLine=oldAddLine
check(captured[1]==longLabel..'1' and captured[2]==longDetail,
    'hover exposes complete label and consequence text')
local next
for _,child in ipairs(window.children) do if child:GetText()=='Next' then next=child end end
check(next and next:IsEnabled(),'long options expose a second page')
next.scripts.OnClick(next)
check(shown[1]._nexusFullLabel:GetText()==longLabel..'4',
    'fourth long option is reachable by paging')
check(shown[2]._nexusInfoHover:IsShown() and not shown[2]:IsEnabled(),
    'long informational row is disabled but has an inspectable hover overlay')
captured={}
GameTooltip.AddLine=function(_,line) captured[#captured+1]=line end
shown[2]._nexusInfoHover.scripts.OnEnter(shown[2]._nexusInfoHover)
GameTooltip.AddLine=oldAddLine
check(captured[1]==shown[2]._nexusFullText and captured[2]==longDetail,
    'disabled long status exposes complete localized text')
Nexus.Panel.LanguageMenuItems=previousLanguage
settings.Hide()
check(not settings.IsShown(),'Settings closes without resetting state')
print('PASS full UI Settings owner routes and passive navigation')
