-- Issue #163: real Settings routes retain the owners' consent and write seams.
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local settings=assert(Nexus.SettingsWindow,'Settings module exists')
local function check(ok,why) assert(ok,why) end
local toc=assert(io.open('Nexus.toc','rb')):read('*a')
check(toc:find('ui\\SettingsWindow.lua',1,true)~=nil,
    'the runtime TOC loads Settings')
local settingsMenu
-- Native QA test.163008: Settings is a direct choice in the Options menu.
for _,item in ipairs(Nexus.Panel.MoreMenuItems()) do
    if item.text=='Open Settings...' then settingsMenu=item end
end
check(settingsMenu and type(settingsMenu.func)=='function',
    'the panel Options menu reaches Settings directly')
settingsMenu.func()
check(settings.IsShown(),'the panel opens the actual Settings window')
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
-- Optional leveling pick: a discoverable plain-English row; reading it acts
-- and writes nothing; only its explicit click runs the /nexus leveling setter,
-- and that never turns Auto ON.
local levelingRow
for i,row in ipairs(automation) do
    if row.text:find('Random Roll',1,true) then levelingRow=i end
end
-- R5: the user-facing name is Random Roll; it explains highest rarity first,
-- the first current offer on a tie, no Wishlist, levels 2-79, Auto ON and
-- autoPick, optional and off by default, no new pick at 80, no reroll/spend.
check(levelingRow and automation[levelingRow].text:find('highest-rarity',1,true)
    and automation[levelingRow].text:find('first current offer on a tie',1,true)
    and automation[levelingRow].text:find('no Wishlist',1,true)
    and automation[levelingRow].text:find('2-79',1,true) and automation[levelingRow].text:find('Auto ON',1,true)
    and automation[levelingRow].text:find('autoPick',1,true) and automation[levelingRow].text:find('off by default',1,true)
    and automation[levelingRow].text:find('no new pick at 80',1,true)
    and automation[levelingRow].text:find('not set (acts as off)',1,true),'the Random Roll row explains itself and reads OFF when absent')
check(not automation[levelingRow].text:find('Auto-pick while leveling',1,true),'the old label is gone from the row')
do
    local scope=table.concat(Nexus.Readout.AutomationScopeLines({selected=false,settings=Nexus.Store.Settings()}),'\n')
    check(scope:find('Random Roll',1,true) and scope:find('not a random one',1,true),
        'the Auto reference scope names Random Roll and says it is not random')
    check(F.Serialize(NexusDB)==baseline and #H.actions==actions,'reading the scope lines writes and does nothing')
end
check(F.Serialize(NexusDB)==baseline and #H.actions==actions,'reading the leveling row writes and does nothing')
settings.Select('automation')
check(settings.Activate(levelingRow,automation[levelingRow].text),'the explicit row click runs its setter')
check(Nexus.Store.Settings().autoPickLeveling==true and not Nexus.RecomputeStats().autoEnabled and #H.actions==actions,
    'the leveling row turns only that option on; Auto stays OFF and nothing is performed')
SlashCmdList.NEXUS('leveling off')
check(Nexus.Store.Settings().autoPickLeveling==false,'the command turns it off again')
baseline=F.Serialize(NexusDB)
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
-- R5 (A24): the Random Roll key in future, unverified and malformed (read-only)
-- roots: only an exact saved true is adopted; the command changes the session
-- only; the whole saved root stays byte-identical; another root drops it.
for _,case in ipairs({{'future 6',function(d)d.settingsVersion=6 end},
    {'unverified 5',function(d)d.settings.syncMode='sometimes' end},
    {'malformed 6.5',function(d)d.settingsVersion=6.5 end}}) do
    for _,saved in ipairs({{true,true},{false,false},{'yes',false},{nil,false}}) do
        local db=F.Database({mutate=function(d)d.settings.autoPickLeveling=saved[1];case[2](d)end})
        local before=F.Serialize(db)
        F.Boot(db)
        local label=case[1]..' saved '..tostring(saved[1])
        local S=Nexus.Store.Settings()
        check(S~=NexusDB.settings and S.autoPickLeveling==saved[2],label..': adopted '..tostring(S.autoPickLeveling))
        SlashCmdList.NEXUS('leveling '..(saved[2] and 'off' or 'on'))
        check(Nexus.Store.Settings().autoPickLeveling==(not saved[2]),label..': the command changes this session')
        check(F.Serialize(NexusDB)==before,label..': the saved root is unchanged')
        check(not Nexus.RecomputeStats().autoEnabled,label..': the command never turns Auto ON')
        local other=F.Database({version=7,mutate=function(d)d.settings.autoPickLeveling=nil end})
        NexusDB=other
        check(Nexus.Store.Settings().autoPickLeveling==false,label..': another (stale/replaced) root drops the session override')
    end
end
do -- supported root: the explicit setter writes only the existing boolean key.
    local db=F.Database({version=2})
    F.Boot(db)
    SlashCmdList.NEXUS('leveling on')
    check(rawget(NexusDB.settings,'autoPickLeveling')==true and NexusDB.settings.customGenSetting.keep=='settings',
        'supported root: saved exactly true; unknown fields kept')
end
-- R6 A01: a writable root with the key absent, false or malformed: startup
-- keeps the saved value as it is (no rewrite), Random Roll stays OFF, Auto
-- stays OFF, and the whole root is unchanged from its post-boot baseline.
for _,saved in ipairs({{'absent',nil},{'false',false},{'malformed',"yes"}}) do
    local db=F.Database({version=2,mutate=function(d)d.settings.autoPickLeveling=saved[2] end})
    local L=F.Boot(db)
    check(rawget(NexusDB.settings,'autoPickLeveling')==saved[2],'A01 '..saved[1]..': startup does not rewrite the saved key')
    check(Nexus.Store.Settings().autoPickLeveling~=true and not Nexus.RecomputeStats().autoEnabled,'A01 '..saved[1]..': mode and Auto OFF')
    local label='A01 '..saved[1]
    check(#L.actions==0,label..': startup takes no action')
    -- Startup is not over when F.Boot returns: deferred maintenance bookkeeping
    -- still runs, and the Changelog marker is stamped on one of ten attempts two
    -- simulated seconds apart. The proper post-boot baseline is the root once
    -- that window has passed and it has stopped changing. While it settles, the
    -- saved settings may only ever hold one of the two values fixed here, at
    -- boot return: exactly as booted, or exactly as booted plus the known
    -- marker (the Changelog module's current release key). Both are serialized
    -- now so that nested values cannot change unnoticed later.
    local marker='prototype-P1.6-assigned-orbs'
    local settingsAtBoot=F.Serialize(NexusDB.settings)
    local stamped={}
    for k,v in pairs(NexusDB.settings) do stamped[k]=v end
    stamped.lastChangelogSeen=marker
    local settingsStamped=F.Serialize(stamped)
    local previous=F.Serialize(NexusDB)
    local t,lastChange,settledAt=0,0,nil
    while settledAt==nil and t<30 do
        L.Advance(0.5)
        t=t+0.5
        local at=label..' at t='..tostring(t)
        check(rawget(NexusDB.settings,'autoPickLeveling')==saved[2],at..': the saved key is untouched while startup settles')
        check(#L.actions==0,at..': no action while startup settles')
        local s=F.Serialize(NexusDB.settings)
        check(s==settingsAtBoot or s==settingsStamped,at..': settings are either as booted or as booted plus the Changelog marker')
        local root=F.Serialize(NexusDB)
        if root~=previous then lastChange=t;previous=root
        elseif t>=20 then settledAt=t end
    end
    check(settledAt~=nil,label..': the root settles within 30 simulated seconds (last change at t='..tostring(lastChange)..')')
    check(rawget(NexusDB.settings,'lastChangelogSeen')==marker and F.Serialize(NexusDB.settings)==settingsStamped,label..': startup ends with exactly the known Changelog marker added to the saved settings')
    local postBoot=F.Serialize(NexusDB);local acted=#L.actions
    L.Advance(5)
    check(F.Serialize(NexusDB)==postBoot and #L.actions==acted,'A01 '..saved[1]..': the whole root and actions stay unchanged after boot')
    check(rawget(NexusDB.settings,'autoPickLeveling')==saved[2] and #L.actions==0,label..': the saved key and zero actions hold after the baseline')
    check(Nexus.Store.Settings().autoPickLeveling~=true and not Nexus.RecomputeStats().autoEnabled,label..': mode and Auto stay OFF after the baseline')
end
-- R6 A24: the explicit setter is a whole-root delta of exactly one boolean key.
do
    local db=F.Database({version=2})
    F.Boot(db)
    local before=F.Serialize(NexusDB)
    SlashCmdList.NEXUS('leveling on')
    check(rawget(NexusDB.settings,'autoPickLeveling')==true,'A24: saved exactly true')
    NexusDB.settings.autoPickLeveling=nil
    check(F.Serialize(NexusDB)==before,'A24: nothing else in the whole root changed')
    NexusDB.settings.autoPickLeveling=true
end
-- R6 A23: /nexus reference and /nexus leveling (status) are passive and name
-- Random Roll; opening them changes no saved data, Auto or action.
do
    local db=F.Database({version=2})
    local L=F.Boot(db)
    local before,acted,mark=F.Serialize(NexusDB),#L.actions,#L.chat
    SlashCmdList.NEXUS('reference');SlashCmdList.NEXUS('leveling')
    local said=table.concat(L.chat,'\n',mark+1)
    check(said:find('Random Roll',1,true) and said:find('highest-rarity',1,true) and said:find('/nexus leveling on|off',1,true),
        'A23: reference and status name Random Roll and explain it')
    check(F.Serialize(NexusDB)==before and #L.actions==acted and not Nexus.RecomputeStats().autoEnabled,
        'A23: reading them changes no saved data, action or Auto')
end
print('PASS full UI Settings owner routes and passive navigation')
