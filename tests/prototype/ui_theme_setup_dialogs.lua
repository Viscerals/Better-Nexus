-- Welcome and Display Settings use the active presentation choice, including
-- a palette/style change after construction and a later reopen. Offline UI
-- model only: actual client pixels remain a separate native check.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(ok,why) assert(ok,why); checks=checks+1 end
local H=F.Boot(F.Database(),function()
    local original=CreateFrame
    CreateFrame=function(kind,name,parent,template)
        local frame=original(kind,name,parent,template)
        frame.SetBackdrop=function(self,value) self.drawnBackdrop=value end
        frame.SetBackdropColor=function(self,...) self.drawnFill={...} end
        frame.SetBackdropBorderColor=function(self,...) self.drawnBorder={...} end
        local createFont=frame.CreateFontString
        frame.CreateFontString=function(self,...)
            local label=createFont(self,...)
            label.SetTextColor=function(self,...) self.drawnText={...} end
            return label
        end
        if kind=='Button' and template=='UIPanelButtonTemplate' then
            local label=frame:CreateFontString(nil,'OVERLAY','GameFontNormal')
            frame.GetFontString=function() return label end
        end
        return frame
    end
end)
local theme=Nexus.Theme
check(theme.Current().style=='vista' and theme.Current().palette=='amethyst',
    'unset settings display default Vista/Amethyst')
local saved=F.Serialize(NexusDB.settings)
-- This is the secondary information-only Welcome's palette test; healthy
-- first use now routes to the guided coach, tested in guided_first_entry.
Nexus.QuickStart.Show()
local welcome=assert(NexusQuickStart,'Welcome window created')
Nexus.WishlistEditor.ToggleDisplayPopup()
local display=assert(NexusDisplayPopup,'Display Settings created')
local function child(root,kind,text)
    for _,entry in ipairs(root.children) do
        local shown=entry:GetText()
        if type(shown)=='string' then
            shown=shown:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
        end
        if entry.kind==kind and shown==text then return entry end
        local nested=child(entry,kind,text)
        if nested then return nested end
    end
end
local welcomeTitle=assert(child(welcome,'FontString','Welcome to Nexus'))
local displayTitle=assert(child(display,'FontString','On-Screen Wishlist'))
-- The exact "Close" caption of the Welcome dismiss control is a collected
-- EXPECT. Only after it misses may the real legacy "Later" control carry the
-- original theme checks; the miss fails this test after them (end of file).
local later=child(welcome,'Button','Close')
local closeCaptionMissing=later==nil
if closeCaptionMissing then
    print('FAIL EXPECT the Welcome dismiss control reads exactly "Close"; the legacy "Later" control carries the original checks')
    later=child(welcome,'Button','Later')
end
later=assert(later)
local lock=assert(child(display,'Button','Lock Position')
    or child(display,'Button','Unlock to Move'))
local reset=assert(child(display,'Button','Reset Position'))
local close=child(display,'Button','X')
local checkboxText=assert(child(display,'FontString','Show on-screen wishlist'))
local function paints(style,palette)
    local s,p=theme.STYLES[style],theme.PALETTES[palette]
    for _,window in ipairs({welcome,display}) do
        check(window._nexusWindowStyled and window.drawnBackdrop==s.windowBackdrop,
            'dialog uses active '..style..' window structure')
        check(window.drawnBorder and window.drawnBorder[1]==p.windowBorder[1],
            'dialog uses active '..palette..' border')
    end
    for _,label in ipairs({welcomeTitle,displayTitle}) do
        check(label.drawnText and label.drawnText[1]==p.accent[1]
            and label.drawnText[4]==1,
            'dialog title follows palette accent')
    end
    check(checkboxText.drawnText and checkboxText.drawnText[1]==s.text[1],
        'settings checkbox label follows style contrast')
    for _,button in ipairs({later,lock,reset}) do
        check(button._nexusDarkStyled and button.drawnBorder
            and button.drawnBorder[1]==p.border[1],
            'dialog action and close buttons follow theme')
    end
    check(close and close._nexusDarkStyled and close.drawnBorder
        and close.drawnBorder[1]==p.border[1],
        'the close action follows the palette rather than stock red art')
end
paints('vista','amethyst')
check(F.Serialize(NexusDB.settings)==saved,
    'opening both dialogs writes no settings')
local body=welcome.body:GetText()
check(body:find('|cffffd100With Auto ON',1,true)
    and body:find('Keep Auto OFF to leave that slot unchanged.|r',1,true),
    'the Auto overwrite warning retains its explicit caution emphasis')
local count=#H.frames
theme.SetPalette('emerald')
paints('vista','emerald')
theme.SetStyle('slate')
theme.SetPalette(nil)
paints('slate','graphite')
display:Hide();Nexus.WishlistEditor.ToggleDisplayPopup()
welcome:Hide();Nexus.QuickStart.Show()
check(display:IsShown() and welcome:IsShown(),
    'both dialogs reopen after theme changes')
paints('slate','graphite')
local slate=theme.STYLES.slate
local text=slate.text
slate.text=nil
check(pcall(theme.StyleLabel, welcome.body, 'text'),
    'an incomplete style cannot break dialog construction')
slate.text=text
theme.StyleLabel(welcome.body, 'text')
check(#H.frames==count,'reopen/repaint allocates no additional frames')
close:Click()
check(not display:IsShown(),'the themed close button preserves dismissal')
check(#H.actions==0,'dialog inspection performs no game action')
-- v28 (native test.163033-40755f5b, 2026-11-14T12:15:47Z: 'Select an Echo'
-- visibly drew over the lower Settings background and a card's lower edge;
-- public ForeignDialogLevel read 110; text obstruction and click failure NOT
-- proved). Contract, as the owned Help/Library/Support windows already have
-- it (support_report section 35): while the game's known control
-- PerkChooseButton is a shown DIALOG frame at a level leaving room below
-- 127, every frame of the open Nexus Options window (NexusSettingsWindow,
-- opened through its real Nexus.SettingsWindow.Show) stands above it (a
-- higher strata, or DIALOG above its level), no DIALOG frame goes past 127,
-- the window keeps its own parent/child and sibling order and its strata,
-- and closing restores its exact defaults. The control is never hidden,
-- moved, re-levelled, clicked or scripted by the addon. Hidden control or a
-- level with no room: the defaults stay (existing family guards). Opening,
-- category changes and closing write no settings and take no game action.
-- Fixture (stated, not native): client creation semantics as support_report
-- section 35 (a child starts one level above its parent and draws in its
-- parent's strata unless it sets its own), installed only for this section
-- and removed at its end. The external control is a synthetic UIParent
-- Button; nothing in the addon is told about it. Misses print as FAIL EXPECT
-- and fail the test after the existing EXPECT below (behavioural RED);
-- checks are SETUP.
local settingsMisses={}
do
    local function expect(v,m) if not v then settingsMisses[#settingsMisses+1]=m;print('FAIL EXPECT '..m) end end
    local PERK,CEILING=110,127
    local RANK={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
    local SKIP={FontString=true,Texture=true,Font=true}
    local SW=assert(Nexus.SettingsWindow,'SETUP: the Settings window module')
    local LM=assert(Nexus.LayoutMetrics,'SETUP: LayoutMetrics')
    check(_G.NexusSettingsWindow==nil,'v28 SETUP: Nexus Options has not been created yet in this session')
    check(_G.PerkChooseButton==nil,'v28 SETUP: no external Select an Echo control exists yet')
    local priorCreate=CreateFrame
    CreateFrame=function(kind,name,parent,template,...)
        local f=priorCreate(kind,name,parent,template,...)
        local p=parent;if type(p)=='string' then p=_G[p] end
        if type(p)=='table' and p~=UIParent and kind~='Font' then
            rawset(f,'frameLevel',(tonumber(p:GetFrameLevel()) or 0)+1)
            rawset(f,'GetFrameStrata',function(self)
                local own=rawget(self,'strata');if own then return own end
                local q=self:GetParent();return q and q:GetFrameStrata() or 'MEDIUM'
            end)
        end
        return f
    end
    local savedSettings=F.Serialize(NexusDB.settings)
    local acts=#H.actions
    local function descendant(f,root)
        local okP,p=pcall(f.GetParent,f)
        while okP and p do if p==root then return true end;okP,p=pcall(p.GetParent,p) end
        return false
    end
    local function Tree(win)
        local out={win}
        for _,f in ipairs(H.frames) do
            if f~=win and not SKIP[f.kind] and type(f.GetFrameLevel)=='function' and descendant(f,win) then out[#out+1]=f end
        end
        return out
    end
    local function Levels(win)
        local t={}
        for _,f in ipairs(Tree(win)) do t[f]={level=tonumber(f:GetFrameLevel()) or 0,strata=f:GetFrameStrata()} end
        return t
    end
    local function sign(x) return x>0 and 1 or x<0 and -1 or 0 end
    local function Same(tag,base)
        local changed,n=0,0
        for f,b in pairs(base) do
            n=n+1
            if (tonumber(f:GetFrameLevel()) or 0)~=b.level or f:GetFrameStrata()~=b.strata then changed=changed+1 end
        end
        expect(n>0 and changed==0,tag..': every Options frame keeps its default level and strata ('..changed..' of '..n..' changed)')
    end
    local function Usable(tag,win,base)
        local nodes=Tree(win)
        local n,below,over,strata,lo,hi=0,0,0,0,math.huge,-math.huge
        local byParent,inTree={},{}
        for _,f in ipairs(nodes) do
            inTree[f]=true
            local s=f:GetFrameStrata();local L=tonumber(f:GetFrameLevel()) or 0
            local b=base[f]
            if b and s~=b.strata then strata=strata+1 end
            n=n+1;lo=math.min(lo,L);hi=math.max(hi,L)
            if not ((RANK[s] or 0)>RANK.DIALOG or (s=='DIALOG' and L>PERK)) then below=below+1 end
            if s=='DIALOG' and L>CEILING then over=over+1 end
            if f~=win then local okP,p=pcall(f.GetParent,f);if okP and p then byParent[p]=byParent[p] or {};table.insert(byParent[p],f) end end
        end
        local flipped=0
        local function pair(a,c)
            local ba,bc=base[a],base[c]
            if ba and bc and sign(ba.level-bc.level)~=sign((tonumber(a:GetFrameLevel()) or 0)-(tonumber(c:GetFrameLevel()) or 0)) then flipped=flipped+1 end
        end
        for p,kids in pairs(byParent) do
            for i,c in ipairs(kids) do
                if inTree[p] then pair(p,c) end
                for j=i+1,#kids do pair(c,kids[j]) end
            end
        end
        expect(n>0 and below==0,tag..': every Nexus Options frame stands above the shown Select an Echo control at '..PERK
            ..' ('..below..' of '..n..' at or below it; levels '..tostring(lo)..'-'..tostring(hi)..')')
        expect(over==0,tag..': no Nexus Options DIALOG frame goes past '..CEILING..' ('..over..' over)')
        expect(flipped==0,tag..': Nexus Options keeps its parent/child and sibling order ('..flipped..' pairs reversed)')
        expect(strata==0,tag..': no Nexus Options frame changes strata ('..strata..' changed)')
    end
    local function NoDrift(tag,ref)
        local moved,n=0,0
        for f,r in pairs(ref) do n=n+1;if (tonumber(f:GetFrameLevel()) or 0)~=r.level then moved=moved+1 end end
        expect(moved==0,tag..': a repeated open gives the same levels ('..moved..' of '..n..' moved)')
    end

    -- a. Control absent: the real open and close record the defaults.
    check(select(1,pcall(SW.Show,'automation')),'v28 SETUP: Nexus Options opens through Nexus.SettingsWindow.Show')
    local win=assert(_G.NexusSettingsWindow,'v28 SETUP: the Nexus Options window')
    check(win:IsShown() and win:GetFrameStrata()=='DIALOG','v28 SETUP: Nexus Options is a shown DIALOG window')
    local xButton=assert(child(win,'Button','X'),'v28 SETUP: the Options close control')
    check(xButton:GetFrameStrata()=='DIALOG' and xButton:GetFrameLevel()==win:GetFrameLevel()+1,
        'v28 SETUP: the stated creation semantics are active (a child reads its parent strata and level + 1)')
    local base=Levels(win)
    local distinct,seen=0,{}
    for _,b in pairs(base) do if b.strata=='DIALOG' and not seen[b.level] then seen[b.level]=true;distinct=distinct+1 end end
    check(distinct>=2,'v28 SETUP: Nexus Options has more than one DIALOG level ('..distinct..')')
    xButton:Click()
    check(not win:IsShown(),'v28 SETUP: the Options X closes the window')
    Same('absent: Nexus Options after close',base)

    -- The external control, as natively read: a shown UIParent Button in DIALOG at 110.
    local ownAnchor=_G.ProjectEbonholdPerkFrame==nil
    local anchor=_G.ProjectEbonholdPerkFrame or CreateFrame('Frame','ProjectEbonholdPerkFrame',UIParent)
    local perk=CreateFrame('Button','PerkChooseButton',UIParent)
    perk:SetFrameStrata('DIALOG');perk:SetFrameLevel(PERK);perk:SetPoint('TOP',anchor,'BOTTOM',0,-50)
    perk:SetText('Select an Echo');perk:Show()
    local real={Show=perk.Show,Hide=perk.Hide,SetFrameLevel=perk.SetFrameLevel}
    local touched,touchedNames=0,{}
    for _,m in ipairs({'SetFrameLevel','SetFrameStrata','SetPoint','ClearAllPoints','SetAllPoints','SetParent','Show','Hide',
        'SetShown','Click','SetScript','HookScript','EnableMouse','SetAlpha','Raise','Lower','SetToplevel','Enable','Disable',
        'SetSize','SetWidth','SetHeight','SetText'}) do
        local orig=perk[m]
        rawset(perk,m,function(self,...)
            touched=touched+1;touchedNames[#touchedNames+1]=m
            if type(orig)=='function' then return orig(self,...) end
        end)
    end
    local function Snapshot()
        return table.concat({tostring(perk:GetFrameStrata()),tostring(perk:GetFrameLevel()),tostring(perk:IsShown()),
            tostring(perk:GetParent()==UIParent),tostring(perk:GetText())},'|')
    end
    local perkBefore=Snapshot()
    check(LM.ForeignDialogLevel()==PERK,'v28 SETUP: the public ForeignDialogLevel reads the control at '..PERK..' (as natively: F true 110)')

    -- b. Shown control: the ordinary open, a category change, close, reopens.
    SW.Show('automation')
    Usable('shown: Nexus Options opened over the control',win,base)
    local firstLifted=Levels(win)
    SW.Select('sync')
    Usable('shown: after a category change',win,base)
    NoDrift('shown: after a category change',firstLifted)
    xButton:Click()
    expect(not win:IsShown(),'shown: the Options X still closes the window')
    Same('shown: Nexus Options closed over the control',base)
    local function Script(f,name)
        local ok,v=pcall(function() return f:GetScript(name) end)
        if ok then return v end
        return type(f.scripts)=='table' and f.scripts[name] or nil
    end
    local frames,hookShow,hookHide
    for cycle=1,3 do
        SW.Show('automation')
        Usable('shown: reopen '..cycle,win,base)
        NoDrift('shown: reopen '..cycle,firstLifted)
        xButton:Click()
        Same('shown: closed after reopen '..cycle,base)
        if cycle==1 then frames,hookShow,hookHide=#H.frames,Script(win,'OnShow'),Script(win,'OnHide') end
    end
    expect(#H.frames==frames,'reopen cycles 2 and 3 make no frame ('..tostring(frames)..' -> '..#H.frames..')')
    expect(Script(win,'OnShow')==hookShow and Script(win,'OnHide')==hookHide,'reopen cycles add no hook')

    -- c. Existing family guards (expected to hold before and after a repair;
    -- non-discriminating today): a hidden control, or one at 126 with no room
    -- for more than one level, leaves every Options level at its default.
    real.Hide(perk)
    SW.Show('automation');Same('guard: control hidden',base);xButton:Click()
    real.Show(perk)
    real.SetFrameLevel(perk,126)
    SW.Show('automation');Same('guard: control at 126 (no room)',base);xButton:Click()
    real.SetFrameLevel(perk,PERK)

    -- d. Nothing else happened; the control is untouched; fixtures removed.
    expect(touched==0,'the Select an Echo control is never changed by the addon ('..touched..' calls: '..table.concat(touchedNames,',')..')')
    expect(Snapshot()==perkBefore,'the Select an Echo control keeps its strata, level, shown state, parent and label')
    expect(F.Serialize(NexusDB.settings)==savedSettings,'opening, changing category and closing Nexus Options write no settings')
    expect(#H.actions==acts,'Nexus Options takes no game action')
    CreateFrame=priorCreate
    _G.PerkChooseButton=nil
    if ownAnchor then _G.ProjectEbonholdPerkFrame=nil end
end
if closeCaptionMissing then
    error('ui_theme_setup_dialogs: EXPECT the Welcome dismiss control reads exactly "Close" (the legacy "Later" control carried '..checks..' original checks)',0)
end
if #settingsMisses>0 then
    error('ui_theme_setup_dialogs v28: Nexus Options over the Select an Echo control: '..#settingsMisses..' expectation(s) missed:\n'
        ..table.concat(settingsMisses,'\n'),0)
end
print('PASS '..checks..' setup-dialog theme checks; native pixels NOT_RUN')
