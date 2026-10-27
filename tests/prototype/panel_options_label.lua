-- Issue #165: the HUD menu button reads "Options" (and "! Options" while a
-- trusted update notice is shown) instead of an ellipsis alone. The label is
-- the localized "panel.button.options"; the "!" is code-owned. Header line 1
-- geometry at 420 px and a wider panel, 125% text in the LayoutMetrics
-- conservative model, long names and a long localized label, the hover named
-- by the visible control, both Difficulty / Soul Ash HUD modes, the notice
-- route and the menu route. Synthetic fixtures; no game client. Native glyph
-- widths are not proven here.
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=T.Profile(3,0);WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
T.Load()
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local P,LM=Nexus.Panel,Nexus.LayoutMetrics

-- 125% text: the owned normal font reports 15 px (12 px base).
local fontName=LM.FontObject('normal')
local font=_G[fontName]
if not font then font=H.Region('Font',fontName) end
font.GetFont=function()return 'Fonts\\FRIZQT__.TTF',15,''end
assert(LM.RuntimeMetrics()==1.25,'fixture: runtime font scale is 125%')
local char=LM.ConservativeText(1.25)
assert(char==8.75,'fixture: conservative width per character at 125%: '..char)

local LONG_WISHLIST='Synthetic Wishlist with a deliberately long localized name'
local LONG_BUILD='Synthetic Saved Build with a deliberately long localized name'
local function Model(o)
 o=o or {}
 local complete=o.complete==true
 return {
  progress={wishlistName=LONG_WISHLIST,total=79,owned=complete and 79 or 12,activeSlot=3,
   activeSlotName=LONG_BUILD,missing=complete and {} or {'Echo 1','Echo 2','Echo 3'},
   shed={},toLock={},unknownTomes={}},
  auto=false,level=complete and 80 or 40,character='Thelongestnm',
  assignment={state='ready',name=LONG_WISHLIST},
  updateNotice=o.notice and {display='1.20.0-beta.1 test.9029',version='1.20.0-beta.1+test.9029'} or nil,
  -- What the Nexus Difficulty / Soul Ash HUD mirrors on the panel; nil while
  -- the stock server HUD is the display (synthetic values).
  serverStatus=o.status and {tier='HC3',mode='HC3',ash='12,345',gain='+150%'} or nil,
 }
end

-- 1. Words. The label is the localized key; the notice mark leads, so a
-- shortened label never loses it.
local L=Nexus.Localization
assert(L.Kind('panel.button.options')=='text' and L.Text('panel.button.options')=='Options',
 'the English base holds the Options label')
assert(P.OptionsText(nil)=='Options' and P.OptionsText(false)=='Options','plain label')
assert(P.OptionsText({display='x'})=='! Options' and P.OptionsText(true)=='! Options','trusted notice label')
-- The seam: the label follows whatever the active language resolves for the
-- key (a synthetic stand-in, not shipped text), and only this code adds the
-- mark: a resolved label that begins with "!" is not shown as the plain label.
local realText=L.Text
local resolved
L.Text=function(key,...)
 if key=='panel.button.options' then return resolved,'candidate',nil end
 return realText(key,...)
end
resolved='Synthetic options label'
local seam={P.OptionsText(nil),P.OptionsText(true),P.OptionsLabel()}
resolved='! Options'
local forged={P.OptionsText(nil),P.OptionsText(true)}
resolved='  !x'
local spaced=P.OptionsText(false)
L.Text=realText
assert(seam[1]=='Synthetic options label' and seam[2]=='! Synthetic options label'
 and seam[3]=='Synthetic options label','the label is read through the localization seam: '..seam[1]..' / '..seam[2])
assert(forged[1]=='Options' and forged[2]=='! Options' and spaced=='Options',
 'a resolved label cannot raise the notice mark: '..forged[1]..' / '..spaced)
assert(P.Render(Model()),'render without a notice')
local f=NexusPanel
assert(f._menuBtn:GetText()=='Options','no notice: Options: '..tostring(f._menuBtn:GetText()))
assert(P.Render(Model({notice=true})),'render with a trusted notice')
assert(f._menuBtn:GetText()=='! Options','trusted notice: ! Options: '..tostring(f._menuBtn:GetText()))
assert(P.Render(Model()),'render after the notice is gone')
assert(f._menuBtn:GetText()=='Options','the mark goes with the notice: '..tostring(f._menuBtn:GetText()))
print('PASS Options words and the trusted-notice route')

-- 2. Label fit at 125%. The harness button has no font string; give it one
-- measured in the conservative model, then place it as a layout pass does.
local menu=f._menuBtn
local label=menu:CreateFontString()
label.GetText=function()return menu:GetText()end
label.GetStringWidth=function()return #((menu:GetText() or ''):gsub('[\128-\191]',''))*char end
menu.GetFontString=function()return label end
local slots=P.PlaceOptionsButton()
assert(slots==P.HeaderSlots(),'the same read-only slots')
assert(menu:GetWidth()==slots.optionsWidth and menu:GetHeight()==slots.height,'Options keeps its slot size')
assert(label:GetWidth()==slots.optionsWidth-slots.caps and label:GetHeight()==slots.height,
 'the label is bounded to the button less its end caps, one line high')
for _,notice in ipairs({false,true})do
 menu:SetText(P.OptionsText(notice))
 assert(not LM.Shortened(label),'"'..menu:GetText()..'" fits whole at 125%: '
  ..label:GetStringWidth()..' <= '..label:GetWidth())
end
print('PASS "Options" and "! Options" fit whole at 125% in the conservative model')

-- 3. A long localized label is shortened by the client; the hover names it
-- in full first and keeps the menu's own lines and the trusted notice line.
-- The hover is headed by the visible control's own name, not another one.
local tip={}
GameTooltip.SetOwner=function()tip={}end
GameTooltip.AddLine=function(_,text)tip[#tip+1]=tostring(text)end
assert(P.Render(Model({notice=true})))
local LONG_LABEL='! Einstellungen und Status'
menu:SetText(LONG_LABEL)
assert(LM.Shortened(label),'fixture: a long localized label does not fit the slot')
menu:GetScript('OnEnter')(menu)
assert(tip[1]==LONG_LABEL,'the complete label comes first while shortened: '..tostring(tip[1]))
local function Has(text)for _,line in ipairs(tip)do if line:find(text,1,true)then return true end end end
assert(tip[2]=='Options','the hover then names the control by its own label: '..tostring(tip[2]))
assert(not Has('Menu and status'),'the hover no longer names a control the panel does not show')
assert(Has('Update available: 1.20.0-beta.1 test.9029'),'the trusted notice is named on hover')
menu:SetText(P.OptionsText(true))
menu:GetScript('OnEnter')(menu)
assert(tip[1]=='Options','a whole label is not repeated on hover; its name heads it: '..tostring(tip[1]))
assert(tip[2]~='! Options','the heading carries no notice mark of its own: '..tostring(tip[2]))
assert(P.Render(Model()))
menu:GetScript('OnEnter')(menu)
assert(not Has('Update available'),'no notice, no notice line on hover')
print('PASS shortened label hover, notice hover')

-- 4. Header geometry: title, Auto (or its state words), Options and Close on
-- line 1; Build beside My Builds and Wishlist beside Change below. Every slot
-- is a right-edge offset, so 420 px and a wider panel keep the same order.
local function Rect(region,W)
 local point,relative,relativePoint,x,y=region:GetPoint(1)
 assert(relative==f and point==relativePoint and (point=='TOPLEFT' or point=='TOPRIGHT'),
  'fixture: header widgets are anchored to the panel corner')
 local w,h=region:GetWidth(),region:GetHeight()
 return {x=point=='TOPLEFT' and x or W+x-w,y=-y,w=w,h=h}
end
local function CheckHeader(W,why)
 f:SetWidth(W)
 P.UpdateContextHeader(P._lastModel)
 P.PlaceOptionsButton()
 local autoShown=f._autoBtn:IsShown()
 local auto=autoShown and f._autoBtn or f._contextAutoState
 assert(auto:IsShown(),why..': the Auto control or its state words are shown')
 local r={title=Rect(f._contextTitle,W),auto=Rect(auto,W),options=Rect(f._menuBtn,W),
  close=Rect(f._closeBtn,W),build=Rect(f._contextBuild,W),switch=Rect(f._switchBtn,W),
  wishlist=Rect(f._contextWishlist,W),change=Rect(f._contextChange,W)}
 assert(r.title.w==W-slots.reserved-12,why..': the title keeps the rest of line 1: '..r.title.w)
 assert(r.title.w>=150,why..': the title stays readable: '..r.title.w)
 assert(r.options.w==slots.optionsWidth and r.auto.w==slots.autoWidth,why..': slot widths')
 local order={'title','auto','options','close'}
 for i=1,#order-1 do
  local a,b=r[order[i]],r[order[i+1]]
  assert(a.x+a.w<=b.x,why..': '..order[i]..' ends before '..order[i+1]..' starts: '..(a.x+a.w)..' > '..b.x)
 end
 assert(r.title.x>=0 and r.close.x+r.close.w<=W,why..': line 1 stays inside the panel')
 assert(r.build.x+r.build.w<=r.switch.x and r.wishlist.x+r.wishlist.w<=r.change.x,
  why..': Build and Wishlist end before My Builds and Change')
 assert(r.build.h==20 and r.wishlist.h==20 and r.title.h==20,why..': one-line header rows')
 assert(f._contextBuild:GetText():find('^Build: ') and f._contextWishlist:GetText():find('^Wishlist: '),
  why..': two-line Build / Wishlist header')
 local names={}
 for name in pairs(r)do names[#names+1]=name end
 table.sort(names)
 for i=1,#names do for j=i+1,#names do
  assert(not LM.Overlap(r[names[i]],r[names[j]]),why..': '..names[i]..' overlaps '..names[j])
 end end
 assert(f._menuBtn:IsShown() and f._closeBtn:IsShown(),why..': Options and Close are shown')
 return autoShown,r
end
assert(P.Render(Model({notice=true})))
for _,W in ipairs({420,640})do
 assert(CheckHeader(W,'Auto shown at '..W..' px')==true,'fixture: Auto is shown for an active build')
end
assert(P.Render(Model({complete=true})))
for _,W in ipairs({420,640})do
 assert(CheckHeader(W,'Auto hidden at '..W..' px')==false,'fixture: Auto is hidden for a finished build at 80')
 assert(f._contextAutoState:GetText()=='Auto OFF','the Auto state words take its slot')
end
f:SetWidth(420)
print('PASS header line 1 order and no overlap at 420 px and 640 px, Auto shown and hidden')

-- 4b. Both Difficulty / Soul Ash HUD preferences, through the setter the
-- Manage menu uses. With the Nexus HUD the panel mirrors the values (attached:
-- the Play summary's one line for a build in progress, the status card for a
-- finished build); with the server HUD the stock widget is the display
-- (detached: neither is shown). The model each mode implies is synthetic
-- (serverStatus above): Main's composition of it is not exercised here.
-- Header line 1 is the same in both modes, and the attached status stays
-- below the header rows, overlapping none of them.
local status=Nexus.ServerStatus
local originalMode=status.VisibilityFacts().mode
local card
for _,child in ipairs(f.children or {})do
 if child._nexusThemeExempt==true and child.intensityBar then card=child end
end
assert(card,'fixture: the Difficulty / Soul Ash card is a child of the panel')
local headerBy={}
for _,mode in ipairs({'nexus','server'})do
 status.SetMode(mode)
 assert(status.IsUsingNexusHud()==(mode=='nexus'),'fixture: the '..mode..' HUD is the preference')
 for _,complete in ipairs({false,true})do
  assert(P.Render(Model({notice=true,complete=complete,status=mode=='nexus'})),'render in '..mode..' mode')
  local line=f._play and f._play.server
  for _,W in ipairs({420,640})do
   local why=mode..' HUD, '..(complete and 'finished' or 'in progress')..' at '..W..' px'
   local autoShown,r=CheckHeader(W,why)
   assert(autoShown==not complete,'fixture: '..why..': Auto follows the build, not the HUD mode')
   assert(f._menuBtn:GetText()=='! Options',why..': the trusted notice mark is kept')
   local shown={}
   if line and line:IsShown() then shown[#shown+1]=line end
   if card:IsShown() then shown[#shown+1]=card end
   if mode=='nexus' then
    assert(#shown==1 and shown[1]==(complete and card or line),
     why..': the mirrored status is shown once, as the '..(complete and 'card' or 'Play line'))
    local s=Rect(shown[1],W)
    local bottom=0
    for _,name in ipairs({'title','auto','options','close','build','switch','wishlist','change'})do
     bottom=math.max(bottom,r[name].y+r[name].h)
     assert(not LM.Overlap(s,r[name]),why..': the mirrored status overlaps '..name)
    end
    assert(s.y>=bottom and s.x>=0 and s.x+s.w<=W,
     why..': the mirrored status sits below the header rows, inside the panel: y '..s.y..' < '..bottom)
   else
    assert(#shown==0,why..': with the server HUD the panel mirrors no status')
   end
   local key=(complete and 'finished' or 'progress')..W
   local mine={options=r.options,close=r.close,auto=r.auto,title=r.title}
   if headerBy[key] then
    for name,box in pairs(mine)do
     local other=headerBy[key][name]
     assert(box.x==other.x and box.y==other.y and box.w==other.w and box.h==other.h,
      why..': '..name..' keeps its header slot in both HUD modes')
    end
   else
    headerBy[key]=mine
   end
  end
 end
end
status.SetMode(originalMode)
assert(status.VisibilityFacts().mode==originalMode,'fixture: the original HUD preference is restored')
f:SetWidth(420)
print('PASS both Difficulty / Soul Ash HUD modes: header line 1 unchanged, the attached status below it')

-- 5. Route: a click opens the same Manage menu at the button and changes
-- nothing: no saved data, no action, no Auto change, no visibility change.
assert(P.Render(Model()))
local opened
EasyMenu=function(list,menuFrame,anchor)opened={list=list,frame=menuFrame,anchor=anchor}end
local db,actions=H.Clone(NexusDB),#H.actions
local autoBefore,shownBefore,autoText=P.AutoSelectedNow(),f:IsShown(),f._autoBtn:GetText()
menu:Click()
assert(opened and opened.anchor==menu and opened.frame==P._moreMenu,'the menu opens at the Options button')
local top=opened.list
assert(top[1] and top[1].isTitle and top[2] and top[2].text=='Manage' and top[2].hasArrow
 and type(top[2].menuList)=='table','the compact menu reaches Manage')
local found={}
for _,item in ipairs(top[2].menuList)do if type(item.text)=='string' then found[item.text]=item end end
for _,text in ipairs({'Open Settings...','Hide Nexus Panel','Log viewer...',Nexus.Updates.Status().menu or 'Open Releases page'})do
 assert(found[text] and type(found[text].func)=='function','Manage keeps '..text)
end
assert(T.Equal(db,NexusDB),'opening the menu writes no saved data')
assert(#H.actions==actions,'opening the menu sends no game action')
assert(P.AutoSelectedNow()==autoBefore and f._autoBtn:GetText()==autoText,'opening the menu leaves Auto as it was')
assert(f:IsShown()==shownBefore,'opening the menu leaves the panel as it was')
print('PASS Options click route: Manage menu, nothing changed')
print('PASS panel options label')
