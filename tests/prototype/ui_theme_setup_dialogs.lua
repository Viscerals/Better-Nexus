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
Nexus.QuickStart.ShowIfFirstTime()
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
if closeCaptionMissing then
    error('ui_theme_setup_dialogs: EXPECT the Welcome dismiss control reads exactly "Close" (the legacy "Later" control carried '..checks..' original checks)',0)
end
print('PASS '..checks..' setup-dialog theme checks; native pixels NOT_RUN')
