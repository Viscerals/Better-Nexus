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
----------------------------------------------------------------------------
-- W1-W4: Settings and the guided setup coach never draw through each other.
-- Native finding (test.163027-eb4df21c): with Settings open from the panel's
-- Options, the real Nexus.GuidedSetupUI.Show() returned true and both windows
-- were shown, Settings' title, categories, rows and paging interleaved with
-- the coach's body and footer. Both are DIALOG windows of UIParent with no
-- level of their own (ui/SettingsWindow.lua EnsureFrame; ui/GuidedSetup.lua
-- Ensure), each with the opaque base Theme.StyleWindow puts one level under
-- it, and neither Show closes the other.
-- Real calls only: Settings through its Options row ("Open Settings...", the
-- route checked above) and Settings.Show/Hide; the coach through
-- GuidedSetupUI.Show/Hide (Options > Setup / Welcome, Help.OpenGuide and
-- /nexus help all reach it) and, for first use, QuickStart.ShowIfFirstTime.
-- EXPECT (by reading, expected to fail at 5a8b6922; Root runs it): whenever
-- both windows are shown, every frame of one window's tree draws below every
-- frame of the other's (strata, then level; texts and textures draw with
-- their frame; equal strata and level is not an order). Either may be the
-- front window, and hiding the earlier window is also accepted. Asked
-- Settings first, coach first, each with the other reopened, and over a
-- first-use coach.
-- GUARD (hard, as above): each route still opens its window when asked; an
-- open warning still refuses the coach, and that refusal leaves Settings as
-- it was; a first-use coach is acknowledged only by its own deliberate Close
-- (a hide by another window records nothing, and first use is then offered
-- again); opening writes no saved data; no game action, no send, Auto OFF.
-- MODEL, this block only (the shared harness answers level 1 and MEDIUM for
-- every frame whatever its parent). Installed by each boot's `before` hook,
-- on every frame made through CreateFrame and on UIParent: strata is the
-- frame's own or its nearest ancestor's (setting a frame's strata clears its
-- descendants' own, so they follow it; UIParent MEDIUM); level is the
-- frame's own SetFrameLevel (absolute, floored, at least 0) or its parent's
-- + 1, read when asked (UIParent 0); order is (strata, level), equal keys
-- unordered. Raise, Lower and SetToplevel are recorded, named in the EXPECT
-- message and change no level. Not modelled: the client's re-levelling of
-- children, raising on click, draw layers inside a frame, geometry and mouse
-- hits (the two windows' overlap is the native finding's, not modelled here).
-- Offline model only; native order must still be seen in the game.
do
    local STRATA={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
    local ORDER={unmodelled={}}
    local function Modelled(f) return type(f)=='table' and rawget(f,'_orderModel')==true end
    local function Strata(f)
        local o,guard=f,0
        while type(o)=='table' and guard<64 do
            local s=rawget(o,'_orderStrata') or rawget(o,'strata')
            if STRATA[s] then return s end
            o=rawget(o,'parent');guard=guard+1
        end
        return 'MEDIUM'
    end
    local function Level(f,depth)
        depth=(depth or 0)+1
        local own=rawget(f,'_orderLevel')
        if own then return own end
        local parent=rawget(f,'parent')
        if Modelled(parent) and depth<64 then return Level(parent,depth)+1 end
        if type(parent)=='table' then return (tonumber(parent:GetFrameLevel()) or 0)+1 end
        return 0
    end
    local function ClearStrata(f)
        for _,child in ipairs(rawget(f,'children') or {}) do
            if Modelled(child) then rawset(child,'_orderStrata',nil);ClearStrata(child) end
        end
    end
    local function Adopt(f)
        if type(f)~='table' then return f end
        rawset(f,'_orderModel',true)
        rawset(f,'GetFrameLevel',function(self) return Level(self) end)
        rawset(f,'SetFrameLevel',function(self,v)
            v=tonumber(v)
            if v then rawset(self,'_orderLevel',math.max(0,math.floor(v))) end
        end)
        rawset(f,'GetFrameStrata',function(self) return Strata(self) end)
        rawset(f,'SetFrameStrata',function(self,s)
            if STRATA[s] then rawset(self,'_orderStrata',s);ClearStrata(self) end
        end)
        for _,call in ipairs({'Raise','Lower','SetToplevel'}) do
            rawset(f,call,function(self)
                ORDER.unmodelled[#ORDER.unmodelled+1]=call..' on '..tostring(rawget(self,'name') or rawget(self,'kind'))
            end)
        end
        return f
    end
    -- F.Boot's `before` hook: after the harness loads, before the TOC. Window
    -- names of an earlier session are cleared so none is read as this one's.
    local function InstallOrder(h,keepWarnings)
        NexusSettingsWindow,NexusGuidedSetup,NexusGuidedSetupEscape=nil,nil,nil
        NexusChangelogPopup,NexusQuickStart,NexusQuickStartEscape=nil,nil,nil
        ORDER.unmodelled={}
        if keepWarnings then h.keepOverwriteWarningPrompts=true end
        Adopt(UIParent);rawset(UIParent,'_orderLevel',0)
        local create=CreateFrame
        CreateFrame=function(kind,name,parent,...) return Adopt(create(kind,name,parent,...)) end
    end
    local function Frames(root,out)
        out=out or {}
        if Modelled(root) and root:IsVisible() then out[#out+1]=root end
        for _,child in ipairs(rawget(root,'children') or {}) do
            if Modelled(child) then Frames(child,out) end
        end
        return out
    end
    local function Key(f) return STRATA[Strata(f)]*65536+Level(f) end
    local function Describe(f)
        local text=rawget(f,'text')
        local label=rawget(f,'name') or (tostring(rawget(f,'kind'))..((type(text)=='string' and text~='') and (' "'..text..'"') or ''))
        return label..' '..Strata(f)..'/'..Level(f)
    end
    local function Span(root)
        local low,high,lowFrame
        for _,f in ipairs(Frames(root)) do
            local k=Key(f)
            if not low or k<low then low,lowFrame=k,f end
            if not high or k>high then high=k end
        end
        return low,high,lowFrame
    end
    local function Reach(back,floor)
        local out={}
        for _,f in ipairs(Frames(back)) do if Key(f)>=floor then out[#out+1]=Describe(f) end end
        return out
    end
    local layers,misses=0,{}
    local function Layers(tag)
        layers=layers+1
        local a,b=NexusSettingsWindow,NexusGuidedSetup
        if not (a and b and a:IsVisible() and b:IsVisible()) then return end
        local aLow,aHigh,aFloor=Span(a)
        local bLow,bHigh,bFloor=Span(b)
        check(aLow and bLow,tag..': fixture: both windows have shown frames')
        if aHigh<bLow or bHigh<aLow then return end
        misses[#misses+1]=tag..': Settings and the coach interleave. Coach frames at or above Settings\' lowest frame ('
            ..Describe(aFloor)..'): '..table.concat(Reach(b,aLow),', ')
            ..'. Settings frames at or above the coach\'s lowest frame ('..Describe(bFloor)..'): '
            ..table.concat(Reach(a,bLow),', ')
            ..(#ORDER.unmodelled>0 and ('. Unmodelled order calls: '..table.concat(ORDER.unmodelled,', ')) or '')
    end
    local function Pending() return #misses>0 and (' (interleaving so far: '..table.concat(misses,' | ')..')') or '' end
    local function Coach() local g=NexusGuidedSetup;return g~=nil and g:IsShown() and true or false end
    local function Seen() return type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil end
    local function OpenSettings(tag)
        local row
        for _,item in ipairs(Nexus.Panel.MoreMenuItems()) do
            if item.text=='Open Settings...' then row=item end
        end
        check(row and type(row.func)=='function',tag..': fixture: the Options row Open Settings... exists'..Pending())
        row.func()
        check(Nexus.SettingsWindow.IsShown(),tag..': Settings opens when asked'..Pending())
    end
    local function OpenCoach(tag)
        local shown,why=Nexus.GuidedSetupUI.Show()
        check(shown==true and Coach(),tag..': the coach opens when asked: '..tostring(why)..Pending())
    end
    local function Quiet(L,tag,acts,sent)
        check(#L.actions==acts and #L.sent==sent and not Nexus.RecomputeStats().autoEnabled,
            tag..': no game action, no send, Auto OFF: actions '..(#L.actions-acts)..', sends '..(#L.sent-sent)..Pending())
    end
    -- A settled session that has seen first use and the release note, so no
    -- startup window takes part (synthetic data only).
    local function Settled(extra)
        return F.Database({mutate=function(d)
            d.hasSeenQuickStart=true
            d.lastChangelogSeen='prototype-P1.6-assigned-orbs'
            d.settings.lastChangelogSeen='prototype-P1.6-assigned-orbs'
            if extra then extra(d) end
        end})
    end
    local function Boot(db,keepWarnings)
        local L=F.Boot(db,function(h) F.OrbService(h);InstallOrder(h,keepWarnings) end)
        L.Advance(3,.05)
        return L
    end

    -- W1. Settings first, then the coach (the native order); then Settings
    -- closed and opened again while the coach is shown.
    do
        local tag='W1 Settings first'
        local L=Boot(Settled())
        local saved,acts,sent=F.Serialize(NexusDB),#L.actions,#L.sent
        OpenSettings(tag)
        OpenCoach(tag)
        Layers(tag..', coach opened over Settings')
        Nexus.SettingsWindow.Hide()
        check(not Nexus.SettingsWindow.IsShown(),tag..': Settings closes'..Pending())
        OpenSettings(tag..' (reopened)')
        Layers(tag..', Settings reopened over the coach')
        check(F.Serialize(NexusDB)==saved,tag..': opening and reopening write no saved data'..Pending())
        check(Seen()==true,tag..': first use stays as it was'..Pending())
        Quiet(L,tag,acts,sent)
    end

    -- W2. The coach first, then Settings; then the coach hidden and shown
    -- again while Settings is shown.
    do
        local tag='W2 coach first'
        local L=Boot(Settled())
        local saved,acts,sent=F.Serialize(NexusDB),#L.actions,#L.sent
        OpenCoach(tag)
        OpenSettings(tag)
        Layers(tag..', Settings opened over the coach')
        Nexus.GuidedSetupUI.Hide()
        check(not Coach(),tag..': the coach hides'..Pending())
        OpenCoach(tag..' (reopened)')
        Layers(tag..', coach reopened over Settings')
        check(F.Serialize(NexusDB)==saved,tag..': opening and reopening write no saved data'..Pending())
        check(Seen()==true,tag..': first use stays as it was'..Pending())
        Quiet(L,tag,acts,sent)
    end

    -- W3. A first-use coach (a session that has not seen first use), then
    -- Settings. Opening Settings, or a hide by it, must not acknowledge first
    -- use; only the coach's own Close does.
    do
        local tag='W3 first-use coach'
        local L=Boot(F.Database())
        Nexus.QuickStart.ShowIfFirstTime()
        check(Coach() and type(rawget(NexusGuidedSetup,'firstUse'))=='function' and Seen()==nil,
            tag..': fixture: the first-use coach is shown and first use is not recorded'..Pending())
        local acts,sent=#L.actions,#L.sent
        OpenSettings(tag)
        Layers(tag..', Settings opened over the first-use coach')
        check(Seen()==nil,tag..': opening Settings records no first use'..Pending())
        if Coach() then
            local close
            for _,c in ipairs(rawget(NexusGuidedSetup,'children') or {}) do
                local label=(tostring(c:GetText() or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))
                if rawget(c,'kind')=='Button' and c:IsShown() and label=='X' then close=c end
            end
            check(close~=nil,tag..': fixture: the coach offers its Close'..Pending())
            close:Click()
            check(not Coach() and Seen()==true,tag..': the coach\'s deliberate Close records first use'..Pending())
        else
            check(Seen()==nil,tag..': a coach hidden by another window records nothing'..Pending())
            Nexus.QuickStart.ShowIfFirstTime()
            check(Coach() and Seen()==nil,tag..': first use is offered again'..Pending())
        end
        Quiet(L,tag,acts,sent)
    end

    -- W4. An open warning still refuses the coach, and that refusal leaves
    -- Settings shown as it was (no hide before the refusal).
    do
        local tag='W4 warning open'
        local L=Boot(Settled(function(d) d.overwriteWarnings=nil end),true)
        if not Nexus.OverwriteWarning.IsOpen() then Nexus.OverwriteWarning.EnsureOnboarding() end
        check(Nexus.OverwriteWarning.IsOpen(),tag..': fixture: the onboarding warning is open and unanswered'..Pending())
        local acts,sent=#L.actions,#L.sent
        OpenSettings(tag)
        local saved=F.Serialize(NexusDB)
        local shown,why=Nexus.GuidedSetupUI.Show()
        check(shown==false and why=='warning-open' and not Coach(),tag..': the coach refuses over the open warning: '
            ..tostring(shown)..'/'..tostring(why)..Pending())
        check(Nexus.SettingsWindow.IsShown() and Nexus.OverwriteWarning.IsOpen(),
            tag..': the refusal leaves Settings shown and the warning unanswered'..Pending())
        Layers(tag..', coach refused')
        check(F.Serialize(NexusDB)==saved,tag..': the refusal writes nothing'..Pending())
        Quiet(L,tag,acts,sent)
    end

    -- The collected EXPECT fails only after every check above ran.
    if #misses>0 then
        error('full_ui_settings: EXPECT Settings and the guided setup coach never interleave ('..#misses..' of '
            ..layers..' layer checks): '..table.concat(misses,' | '),0)
    end
end
print('PASS full UI Settings owner routes and passive navigation')
