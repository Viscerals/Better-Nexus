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
settings.Hide()
check(not settings.IsShown(),'Settings closes without resetting state')
print('PASS full UI Settings owner routes and passive navigation')
