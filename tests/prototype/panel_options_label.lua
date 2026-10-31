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
  wishlist=Rect(f._contextWishlist,W),change=Rect(f._contextChange,W),grip=Rect(f._dragGrip,W)}
 -- The visible drag grip (design/current) is a distinct target at the
 -- left of line 1, before the title; the pairwise check below keeps it clear.
 assert(f._dragGrip:IsShown() and r.grip.x+r.grip.w<=r.title.x and r.grip.w>=22 and r.grip.h>=22,
  why..': the grip sits before the title as a 22 px target')
 -- Distinct, spaced targets on line 1 (design: no clumped Auto/Options/X).
 assert(r.auto.x+r.auto.w+slots.gap<=r.options.x+0.001 and r.options.x+r.options.w+slots.gap<=r.close.x+0.001,
  why..': Auto, Options and Close keep the design gap between them')
 -- The title starts after the drag grip (slots.titleLeft).
 assert(r.title.w==W-slots.reserved-slots.titleLeft,why..': the title keeps the rest of line 1: '..r.title.w)
 assert(r.title.x==slots.titleLeft,why..': the title starts after the grip: '..r.title.x)
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
-- Options menu uses. With the Nexus HUD the panel mirrors the values (attached:
-- the original b0870929 status card, for a build in progress as for a finished
-- one -- design/current "Nexus Main Panel - Compact Redesign" retired the
-- flattened Play line); with the server HUD the stock widget is the display
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
    assert(#shown==1 and shown[1]==card,
     why..': the mirrored status is shown once, as the original card, never a flattened line')
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

-- 5. Route: a click opens the Options menu at the button and changes
-- nothing: no saved data, no action, no Auto change, no visibility change.
assert(P.Render(Model()))
local opened
EasyMenu=function(list,menuFrame,anchor)opened={list=list,frame=menuFrame,anchor=anchor}end
local db,actions=H.Clone(NexusDB),#H.actions
local autoBefore,shownBefore,autoText=P.AutoSelectedNow(),f:IsShown(),f._autoBtn:GetText()
menu:Click()
assert(opened and opened.anchor==menu and opened.frame==P._moreMenu,'the menu opens at the Options button')
local top=opened.list
-- design/current "Nexus Main Panel - Compact Redesign": Appearance is a
-- top-level Options entry, the shared Theme list with the current choice
-- checked. Native QA test.163008: there is no Manage submenu. Owner-approved
-- item 2 (#165): the optional windows (Log viewer... among them) are one
-- list down, under More help and windows.
local appearanceItem,appearances=nil,0
local found={}
for _,item in ipairs(top)do
 assert(item.text~='Manage','Options opens no Manage submenu')
 if type(item.text)=='string' then found[item.text]=item end
 if type(item.text)=='string' and item.text:find('^Appearance: ') then appearanceItem=item;appearances=appearances+1 end
end
assert(top[1] and top[1].isTitle,'the menu opens with a group title')
assert(appearances==1 and appearanceItem.hasArrow and type(appearanceItem.menuList)=='table'
 and #appearanceItem.menuList==#Nexus.Theme.MenuItems(),'Options opens Appearance directly, once: the shared Theme list')
local checkedRows=0
for _,item in ipairs(appearanceItem.menuList)do if item.checked then checkedRows=checkedRows+1 end end
assert(checkedRows>=1,'the current appearance is checked in the direct Options list')
for _,text in ipairs({'Open Settings...','Hide Nexus Panel',Nexus.Updates.Status().menu or 'Open Releases page'})do
 assert(found[text] and type(found[text].func)=='function','Options offers '..text..' directly')
end
local moreRow=found['More help and windows']
local logs
for _,item in ipairs(moreRow and moreRow.menuList or {})do if item.text=='Log viewer...' then logs=item end end
assert(moreRow and moreRow.hasArrow and logs and type(logs.func)=='function' and not found['Log viewer...'],
 'Options offers Log viewer... under More help and windows')
-- No stock row cap is asserted: the 3.3.5a dropdown export starts at 8 rows
-- and grows them per item; whether the menu fits the screen is native NOT_RUN.
local labelled=0
for _,item in ipairs(top)do if type(item.text)=='string' and item.text~='' then labelled=labelled+1 end end
assert(labelled==#top,'every top-level Options row has a label: '..labelled..'/'..#top)
assert(T.Equal(db,NexusDB),'opening the menu writes no saved data')
assert(#H.actions==actions,'opening the menu sends no game action')
assert(P.AutoSelectedNow()==autoBefore and f._autoBtn:GetText()==autoText,'opening the menu leaves Auto as it was')
assert(f:IsShown()==shownBefore,'opening the menu leaves the panel as it was')
print('PASS Options click route: direct choices and More help and windows, nothing changed')
print('PASS panel options label')

-- 6. Issue #146 O1: an expanded Options label admitted by the REAL loader and
-- consumed by the REAL header, hover and menu. Sections 1-3 reach the label
-- through an L.Text stand-in and a direct SetText; here nothing stands in for
-- the label. Fresh real-TOC boots (format5_support F.Boot) of synthetic saved
-- data: right after data\LocalizationPacks.lua loads, a scoped F.fileHooks
-- entry deep-copies the in-memory packs and overwrites only the copied frFR
-- "panel.button.options" (the shipped complete frFR already holds its own
-- reviewed "Options", which stays unchanged); the real
-- core/Localization.lua then checks and copies it, frFR is chosen only in the
-- synthetic settings, and Panel.Render, OptionsLabel / OptionsText,
-- PlaceOptionsButton and the registered OnEnter / OnLeave / OnClick of the
-- actual NexusPanel._menuBtn do the rest. TEST-ONLY expansion text: no new
-- language ID, no shipped pack, key, cap or data change, no translation.
-- Geometry is the stated uniform-character models of layout_geometry_support
-- (default, 16 px face, 0.75, 2.0) and the 125% conservative model of section
-- 2, at UI scales 1 and 0.64, 420 / 640 px panels and a 640x480 screen: a
-- regression model, not native glyph, wide-script font or pixel proof. Native
-- focus, Escape, hit order and tooltip drawing are NOT RUN; a harness Click is
-- not a native click. The fixed 92x22 control is shortened, never grown; its
-- own hover recovers the complete label. Self-contained: it reads nothing the
-- sections above set up, and restores the globals it replaces.
do
 -- Every global as it is now; each boot's harness replaces many of them.
 local before={}
 for name,value in pairs(_G)do before[name]=value end
 local F=dofile('tests/prototype/format5_support.lua')
 local G=dofile('tests/prototype/layout_geometry_support.lua')
 local S=dofile('tests/prototype/startup_support.lua')
 local same=S.Equal
 local checks=0
 local function check(ok,why)assert(ok,why);checks=checks+1 end
 local KEY='panel.button.options'
 -- Deterministic test-only text from bounded valid UTF-8 pieces: accented
 -- Latin, CJK (wide in the client, one model character here), fullwidth
 -- Latin and Cyrillic, then ASCII padding to an exact byte length.
 local PIECES={'R\195\169glages ','\232\168\173\229\174\154 ',
  '\239\188\175\239\189\144\239\189\148\239\189\137\239\189\143\239\189\142\239\189\147 ',
  '\195\137tat ','\208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184 '}
 local function Expanded(bytes)
  local out,n,i={},0,0
  while n+#PIECES[i%#PIECES+1]<=bytes-3 do
   local piece=PIECES[i%#PIECES+1];out[#out+1]=piece;n=n+#piece;i=i+1
  end
  out[#out+1]=string.rep('.',bytes-3-n)..'fin'
  return table.concat(out)
 end
 local LONG=Expanded(256)
 local SHORT='R\195\169glages'
 local BANG='! R\195\169glages'
 check(#LONG==256 and LONG:sub(1,10)=='R\195\169glages ' and LONG:sub(-3)=='fin' and not LONG:find('[%z\1-\31\127|]'),
  'SETUP O1: the expanded candidate is exactly 256 bytes of plain text: '..#LONG)
 local BAD={
  {'257 bytes',LONG..'.'},
  {'pipe markup','R\195\169glages |cffff0000rouge|r'},
  {'control byte','R\195\169glages\1suite'},
  {'newline','R\195\169glages\nsuite'},
  {'malformed UTF-8','R\195\169glages \195'},
 }
 check(#BAD[1][2]==257,'SETUP O1: the over-long candidate is 257 bytes')
 -- 125%: the conservative model section 2 measures with (8.75 px a
 -- character, a 15 px owned font), as a geometry model beside the four above.
 local C125={name='125% conservative',char=8.75,line=17,size=15}
 local MODELS={G.MODELS.default,G.MODELS.px16,G.MODELS.small,G.MODELS.double,C125}
 -- Literal fits of the short control in the 80 px label room: visible
 -- characters x model width ("Réglages" 8, "! Réglages" 10).
 local SHORT_CUT={[G.MODELS.default]={false,false},[G.MODELS.px16]={false,false},
  [G.MODELS.small]={false,false},[G.MODELS.double]={true,true},[C125]={false,true}}
 -- Independent literal expectations of the surrounding presentation, per
-- active language: the reviewed English base and the reviewed shipped frFR
-- values (panel.tooltip.options_contents, panel.tooltip.update_available,
-- panel.tooltip.update_releases_link, panel.label.auto_state_off,
-- panel.label.context_wishlist with usertext.value.wishlist_assigned_named).
-- Only the Options label itself is the test candidate; the help, notice,
-- Auto state and Wishlist words are the language's own and localize.
 local LOCALE={
  enUS={help='Help and setup, settings, notices, logs and panel actions. Plan, Explore and Orbs are on the footer.',
   notice='Update available: 1.20.0-beta.1 test.9029',
   releases='Open this menu for the manual Releases-page link.',
   autoOff='Auto OFF',
   wishlist='Wishlist: Synthetic |||| Wishlist Caf\195\169 (assigned)'},
  frFR={help='Aide et configuration, param\195\168tres, avis, journaux et actions du panneau. Plan, Explorer et Orbs sont en bas du panneau.',
   notice='Mise \195\160 jour disponible : 1.20.0-beta.1 test.9029',
   releases='Ouvrez ce menu pour le lien manuel vers la page Releases.',
   autoOff='Auto D\195\137SACTIV\195\137',
   wishlist='Liste de souhaits : Synthetic |||| Wishlist Caf\195\169 (assign\195\169e)'},
 }
 local function Words()
  local words=LOCALE[(Nexus.Localization.ActiveLanguage())]
  assert(words,'SETUP O1: literal expectations exist for the active language')
  return words
 end
 -- The control's own hover: its name heads it, complete and wrapped while
 -- the button shows that name shortened (with or without the trusted "! "),
 -- so the complete label is shown exactly once; then help and the notice,
 -- in the active language.
 local function Want(label,notice,shortened)
  local words,out=Words(),{}
  out[#out+1]={label,1,1,1,shortened or nil}
  out[#out+1]={words.help,0.8,0.8,0.8,true}
  if notice then
   out[#out+1]={' '}
   out[#out+1]={words.notice,1,0.82,0,true}
   out[#out+1]={words.releases,0.8,0.8,0.8,true}
  end
  return out
 end
 -- The reviewed shipped frFR Options menu, row by row (Panel MoreMenuItems
 -- under the synthetic fixture), as independent literals.
 local FRENCH_MENU={'Aide et configuration','Questions (FAQ)','Configuration / Bienvenue',
  "L'Auto expliqu\195\169 (d\195\169tails complets)","Plus d'aide et de fen\195\170tres",'Param\195\168tres',
  'Apparence : Nexus Vista, Nexus Am\195\169thyste','Ouvrir les param\195\168tres...',"Param\195\168tres d'automatisation",
  'Langue : Fran\195\167ais','Afficher les records de DPS (masqu\195\169s)',
  'Utiliser le HUD difficult\195\169 / Soul Ash du serveur (HUD du jeu non d\195\169tect\195\169)','Avis',
  'Version et mises \195\160 jour : aucune info de mise \195\160 jour v\195\169rifi\195\169e',
  'Avis de mise \195\160 jour : activ\195\169s, stables + builds de test','Session',
  'Mettre Nexus en pause pour cette session',
  "Met en pause l'Auto, les actions d'Orb, le partage et l'enregistrement du DPS.",
  'Une action d\195\169j\195\160 envoy\195\169e peut encore se terminer.','Panneau',
  'Taille du panneau principal : 100%','R\195\169initialiser la position du panneau','Masquer le panneau Nexus'}
 local NAME='Synthetic || Wishlist Caf\195\169'
 local function Model(o)
  o=o or {}
  local complete=o.complete==true
  return {
   progress={wishlistName=NAME,total=79,owned=complete and 79 or 12,activeSlot=3,
    activeSlotName='Synthetic || Saved Build',missing=complete and {} or {'Echo 1','Echo 2','Echo 3'},
    shed={},toLock={},unknownTomes={}},
   auto=false,level=complete and 80 or 40,character='Thelongestnm',
   assignment={state='ready',name=NAME},
   updateNotice=o.notice and {display='1.20.0-beta.1 test.9029',version='1.20.0-beta.1+test.9029'} or nil,
   cards=o.offer and {{text='Echo 4 (Rare)'}} or nil,recommendation=o.offer and 'Take' or nil,
   charges=o.offer and {banish=0,freeze=7} or nil,
  }
 end
 local H,log,shipped,shippedFacts,baseline
 local function Effects()
  local id,initialized,automatic=Nexus.Localization.ActiveLanguage()
  return {db=F.Serialize(NexusDB),settings=H.Clone(Nexus.Store.Settings()),language=id,initialized=initialized,
   automatic=automatic,actions=#H.actions,sent=#H.sent,chat=#H.chat,popup=H.popup~=nil,
   auto=Nexus.RecomputeStats().autoEnabled==true,
   option=ProjectEbonholdOptionsService:GetSetting('autoAcceptLoadoutEchoes')==true,
   readOnly=tostring(Nexus.MainInternals.SavedRootReadOnlyV1()),warning=Nexus.OverwriteWarning.IsOpen()==true,
   assignment=H.Clone(Nexus.GameAdapter.AssignmentActionSnapshot())}
 end
 -- Passivity: everything above, compared with the snapshot each boot takes
 -- right after start-up and its fixture configuration, before the first
 -- tested render, hover, menu or sweep. Nothing is re-based later.
 local function Passive(why)
  check(same(Effects(),baseline),why..': since start-up no saved root, setting, language, Auto, assignment, action (save, spend), send, chat, popup or consent change')
 end
 -- One fresh real-TOC boot; options nil boots the shipped data unchanged.
 local function Boot(language,options)
  local db=F.Database({version=2});db.settings.uiLanguage=language
  local prior=F.fileHooks
  shipped,shippedFacts=nil,nil
  F.fileHooks=options~=nil and {['data\\LocalizationPacks.lua']=function()
   shipped=Nexus.LocalizationPacks
   local packs={}
   for id,pack in pairs(shipped)do
    local entries={};for key,text in pairs(pack.entries)do entries[key]=text end
    packs[id]={name=pack.name,entries=entries}
   end
   -- What the shipped frFR held before the copy was changed.
   local count=0;for _ in pairs(shipped.frFR.entries)do count=count+1 end
   shippedFacts={entries=shipped.frFR.entries,count=count,options=shipped.frFR.entries[KEY]}
   packs.frFR.entries[KEY]=options
   Nexus.LocalizationPacks=packs
  end} or nil
  -- A new harness measures with its defaults until G.UseFont; an earlier
  -- synthetic NexusFontNormal would keep reporting an earlier font size.
  log={};G.model=nil;NexusFontNormal=nil
  local ok,booted=pcall(F.Boot,db,function()
   local methods=G.RegionMethods();local set=methods.SetText
   -- MODEL (as terminology_consumers #143): a Button draws its text with one
   -- FontString of its own (GetFontString), made on first use at the
   -- button's centre and as wide as its text until its owner sizes it;
   -- Button:SetText sets it. Not modelled: per-state fonts, pushed offsets,
   -- drawn clipping or ellipsis, native measurement.
   methods.GetFontString=function(self)
    if self.kind~='Button' then return nil end
    local label=rawget(self,'_fixtureLabel')
    if not label then
     label=self:CreateFontString()
     label.width,label.height,label.text=nil,nil,self.text
     label.GetWidth=function(fs)return fs.width or fs:GetStringWidth()end
     label.GetHeight=function(fs)return fs.height or (G.model and G.model.line or 14)end
     label:SetPoint('CENTER',self,'CENTER',0,0)
     rawset(self,'_fixtureLabel',label)
    end
    return label
   end
   methods.SetText=function(self,text,...)
    log[#log+1]={self,text}
    local result=set(self,text,...)
    local label=rawget(self,'_fixtureLabel')
    if label then label.text=self.text end
    return result
   end
   methods.SetWordWrap=function(self,value)self.wordWrap=value end
  end)
  F.fileHooks=prior
  if not ok then error(booted,0)end
  H=booted
  UIParent:SetSize(1920,1080)
  check(F.fileHooks==nil and Nexus.StartupStatus().coreReady==true
   and Nexus.Localization.ActiveLanguage()==(language or 'enUS') and (options==nil)==(shipped==nil),
   'SETUP O1: real TOC boot ready with '..tostring(language or 'enUS')..' active; the scoped hook ran once and is gone')
  Nexus.Panel.Show()
  baseline=Effects()
  return Nexus.Localization
 end
 local function Hover(owner)
  local lines,owners={},{}
  local add,own=rawget(GameTooltip,'AddLine'),rawget(GameTooltip,'SetOwner')
  rawset(GameTooltip,'AddLine',function(_,text,r,g,b,wrap)lines[#lines+1]={text,r,g,b,wrap}end)
  rawset(GameTooltip,'SetOwner',function(_,who,anchor)owners[#owners+1]={who,anchor}end)
  GameTooltip:Hide()
  local ok,err=pcall(owner:GetScript('OnEnter'),owner)
  local shown=GameTooltip:IsShown()
  rawset(GameTooltip,'AddLine',add);rawset(GameTooltip,'SetOwner',own)
  assert(ok,err)
  owner:GetScript('OnLeave')(owner)
  return lines,owners,shown==true and not GameTooltip:IsShown()
 end
 local function Menu()
  local opened
  EasyMenu=function(list,frame,anchor)opened={list=list,frame=frame,anchor=anchor}end
  NexusPanel._menuBtn:Click()
  EasyMenu=nil
  Passive('O1 menu opening')
  return opened
 end
 -- The opened menu's rows: their texts, and their structure (title, submenu
-- and its size, click, checked, disabled, checkable) without the text.
 local function TopTexts(opened)
  local out={}
  for _,item in ipairs(opened and opened.list or {})do out[#out+1]=tostring(item.text) end
  return out
 end
 local function TopShape(opened)
  local out={}
  for _,item in ipairs(opened and opened.list or {})do
   out[#out+1]={item.isTitle==true,item.hasArrow==true,type(item.func),item.checked==true,item.disabled==true,
    item.notCheckable==true,type(item.menuList)=='table' and #item.menuList or -1}
  end
  return out
 end
 -- The literal header line 1 slots (Panel M.HeaderSlots: Close 24 px at the
 -- 10 px edge, Options 92 px with an 80 px label, Auto 84 px, 8 px gaps,
 -- the 22 px grip at 8 and the title from 36), as {left, top, right, bottom}.
 local function Slots(W)
  return {options={W-134,7,W-42,29},label={W-128,7,W-48,29},close={W-34,7,W-10,29},
   auto={W-226,7,W-142,29},state={W-226,9,W-142,27},grip={8,7,30,29},title={36,8,W-234,28}}
 end
 local function Header(W,why,want,expectShort,notice)
  local f,P=NexusPanel,Nexus.Panel
  if W~=420 then f:SetWidth(W);P.UpdateContextHeader(P._lastModel);P.PlaceOptionsButton() end
  check(f:GetWidth()==W,'SETUP O1 '..why..': the panel is '..W..' px wide')
  local menu=f._menuBtn
  local label=menu:GetFontString()
  local shown=(notice and '! ' or '')..want
  check(menu:GetText()==shown and label and label:GetText()==shown,
   why..': the actual Options control and its FontString show the admitted text exactly ('..tostring(menu:GetText())..')')
  check(menu:GetWidth()==92 and menu:GetHeight()==22 and label:GetWidth()==80 and label:GetHeight()==22
   and label.wordWrap==false,why..': Options keeps its fixed 92x22 slot and a one-line 80x22 label; it does not grow')
  local slots=Slots(W)
  local autoShown=f._autoBtn:IsShown()
  local r={options=G.Rect(menu,f),label=G.Rect(label,f),close=G.Rect(f._closeBtn,f),
   auto=G.Rect(autoShown and f._autoBtn or f._contextAutoState,f),grip=G.Rect(f._dragGrip,f),title=G.Rect(f._contextTitle,f)}
  check(same(r.options,slots.options) and same(r.label,slots.label) and same(r.close,slots.close)
   and same(r.auto,autoShown and slots.auto or slots.state) and same(r.grip,slots.grip) and same(r.title,slots.title),
   why..': header line 1 keeps its literal slots: Options '..G.Text(r.options)..', label '..G.Text(r.label)..', Auto '..G.Text(r.auto))
  check(G.Inside(r.label,{r.options[1]+6,r.options[2],r.options[3]-6,r.options[4]}),why..': the label stays inside Options less its end caps')
  check(r.auto[3]+8<=r.options[1] and r.options[3]+8<=r.close[1] and r.grip[3]<=r.title[1] and r.title[3]<=r.auto[1],
   why..': grip, title, Auto, Options and Close stay in order with the 8 px gaps')
  local names={'options','close','auto','grip','title'}
  for i=1,#names do for j=i+1,#names do
   check(G.Apart(r[names[i]],r[names[j]]),why..': '..names[i]..' and '..names[j]..' do not overlap')
  end end
  check(G.Inside(r.options,{0,0,W,f:GetHeight()}) and G.Inside(r.close,{0,0,W,f:GetHeight()}),why..': line 1 stays inside the panel')
  check(G.Visible(autoShown and f._autoBtn:GetText() or f._contextAutoState:GetText())==Words().autoOff,
   why..': Auto reads exactly the active language\'s reviewed Auto OFF words ('..Words().autoOff..')')
  check(Nexus.LayoutMetrics.Shortened(label)==expectShort,
   why..': the 80 px label is '..(expectShort and 'shortened' or 'whole')..' in this model ('..label:GetStringWidth()..' px)')
  local lines,owners,cycle=Hover(menu)
  -- Every visible tooltip line counts, whatever its colour or wrap flag.
  local full=0
  for _,line in ipairs(lines)do if tostring(line[1]):find(want,1,true) then full=full+1 end end
  check(full==1,why..': the complete label appears in exactly one visible hover line ('..full..')')
  check(same(lines,Want(want,notice,expectShort)) and #owners==1 and owners[1][1]==menu
   and owners[1][2]=='ANCHOR_TOPLEFT' and cycle,
   why..': the registered hover takes the tooltip once and gives the '..(expectShort and 'complete ' or '')
    ..'control name, its help'..(notice and ' and the complete trusted notice' or '')..' ('..#lines..' lines)')
  Passive(why)
  if W~=420 then f:SetWidth(420) end
  return r
 end
 local function Sweep(language,want,cut,tag)
  local uiScale=rawget(UIParent,'GetEffectiveScale')
  for _,model in ipairs(MODELS)do
   for _,ui in ipairs({1,0.64})do
    G.UseFont(model);rawset(UIParent,'GetEffectiveScale',function()return ui end)
    local fontScale,uiNow=Nexus.LayoutMetrics.RuntimeMetrics()
    check(fontScale==model.size/12 and uiNow==ui,'SETUP O1 '..tag..', '..model.name..', UI '..ui..': the runtime metrics follow the stated model')
    for _,complete in ipairs({false,true})do
     for _,notice in ipairs({false,true})do
      check(Nexus.Panel.Render(Model({notice=notice,complete=complete})),'SETUP O1: render')
      for _,W in ipairs({420,640})do
       Header(W,tag..', '..model.name..', UI '..ui..', '..(complete and 'finished' or 'in progress')
        ..(notice and ', notice' or '')..', '..W..' px',want,cut(model)[notice and 2 or 1],notice)
      end
     end
    end
   end
   -- The 640x480 floor: the panel is fitted to the screen as a whole; header
   -- line 1 keeps its slots in panel units.
   UIParent:SetSize(640,480)
   check(Nexus.Panel.Render(Model({notice=true})),'SETUP O1: render at 640x480')
   local scale=NexusPanel:GetScale()
   check(scale>0 and scale<=1 and NexusPanel:GetWidth()*scale<=616+1e-6 and NexusPanel:GetHeight()*scale<=456+1e-6,
    tag..', '..model.name..': at a 640x480 screen the whole panel fits less the 24 px margin (scale '..scale..')')
   Header(420,tag..', '..model.name..', 640x480 screen',want,cut(model)[2],true)
   UIParent:SetSize(1920,1080)
  end
  rawset(UIParent,'GetEffectiveScale',uiScale)
  G.UseFont(G.MODELS.default)
 end
 -- The shipped frFR table is untouched: same table, same entry count, its own
-- reviewed "Options" (equal to the English word in the reviewed frFR draft),
-- while the deep copy differs from it only in the overwritten Options entry.
 local function Shipped(tag,want)
  local copy=Nexus.LocalizationPacks
  check(shipped and shippedFacts and copy~=shipped and copy.frFR~=shipped.frFR and copy.frFR.entries~=shipped.frFR.entries
   and shipped.frFR.entries==shippedFacts.entries,tag..': the hook kept the shipped tables and loaded a deep copy')
  local count,copied,others=0,0,true
  for key,text in pairs(shipped.frFR.entries)do
   count=count+1
   if key~=KEY then others=others and copy.frFR.entries[key]==text end
  end
  for _ in pairs(copy.frFR.entries)do copied=copied+1 end
  check(count==shippedFacts.count and count==#Nexus.Localization.Keys() and copied==count,
   tag..': the shipped frFR still holds '..count..' entries, one per English key; the copy as many ('..copied..')')
  check(shipped.frFR.entries[KEY]=='Options' and shippedFacts.options=='Options' and shipped.frFR.entries[KEY]~=want,
   tag..': the shipped frFR keeps its own reviewed Options entry, unchanged and different from the test text')
  check(copy.frFR.entries[KEY]==want and others,tag..': only the copied Options entry holds the test text; every other copied entry is the shipped one')
 end
 local function Admitted(L,want,tag)
  local text,source,reason=L.Text(KEY)
  check(text==want and source=='candidate' and reason==nil,tag..': the real loader admitted the test candidate ('..tostring(source)..')')
  local base,baseSource=L.Resolve(KEY)
  check(base=='Options' and baseSource=='base' and Nexus.LocalizationEnglish[KEY]=='Options',tag..': pure Resolve and the English base stay Options')
  local row
  for _,r in ipairs(L.Diagnostics().packs.rows)do if r.id=='frFR' then row=r end end
  local ids={}
  for _,language in ipairs(L.Languages())do ids[#ids+1]=language.id..'='..language.name end
  -- The shipped frFR is a complete pack: one entry per English key. The copy
  -- overwrites its existing Options entry, so the count does not grow.
  local keys=#L.Keys()
  check(keys==4078 and L.Diagnostics().base.accepted==keys,tag..': the English base holds the 4078-key catalog ('..keys..')')
  check(table.concat(ids,',')=='enUS=English,frFR=Fran\195\167ais,deDE=Deutsch,esES=Espa\195\177ol,plPL=Polski,ptBR=Portugu\195\170s (Brasil),ruRU=\208\160\209\131\209\129\209\129\208\186\208\184\208\185'
   and L.Diagnostics().packs.adopted==6 and L.Diagnostics().packs.refused==0 and row and row.accepted==keys and row.rejected==0,
   tag..': the same seven offered languages, no pseudo language; frFR copied all '..keys..' entries, the overwritten Options among them ('
    ..table.concat(ids,',')..'; '..tostring(row and row.accepted)..'/'..tostring(row and row.rejected)..')')
  Shipped(tag,want)
 end
 -- A. English control: the shipped data, no hook.
 local L=Boot(nil,nil)
 G.UseFont(G.MODELS.default)
 check(L.Text(KEY)=='Options' and select(2,L.Text(KEY))=='base','SETUP O1 English: the shipped data shows Options')
 check(Nexus.Panel.Render(Model()),'SETUP O1 English: render')
 Passive('O1 English render')
 local englishWishlist=NexusPanel._contextWishlist:GetText()
 local englishOpened=Menu()
 local englishMenu,englishShape=TopTexts(englishOpened),TopShape(englishOpened)
 check(englishWishlist==LOCALE.enUS.wishlist and #englishMenu>10 and #englishMenu==#FRENCH_MENU,
  'SETUP O1 English: the escaped Wishlist name and the Options menu ('..tostring(englishWishlist)..', '..#englishMenu..' rows)')
 -- The English control keeps the English hover, notice and Auto OFF words.
 check(Nexus.Panel.Render(Model({notice=true})),'SETUP O1 English: render with the notice')
 Header(420,'O1 English, trusted notice','Options',false,true)
 check(Nexus.Panel.Render(Model()),'SETUP O1 English: render')
 -- B. The exact 256-byte expanded candidate through the real loader.
 L=Boot('frFR',LONG)
 Admitted(L,LONG,'O1 expanded')
 G.UseFont(G.MODELS.default)
 check(Nexus.Panel.Render(Model()),'SETUP O1 expanded: first render')
 local f,P=NexusPanel,Nexus.Panel
 local menu=f._menuBtn
 check(menu:GetText()==LONG and P.OptionsLabel()==LONG and P.OptionsText(true)=='! '..LONG,
  'O1 expanded: OptionsLabel and OptionsText give the admitted bytes; only the trusted notice adds "! "')
 Sweep('frFR',LONG,function()return {true,true}end,'O1 expanded')
 -- Notice on, then off (the notice-only update path), copied, raw
 -- and committed re-renders, hide / reopen and the menu, on the same
 -- warm control with its own handlers.
 local raw=Model({notice=true});local pristine=H.Clone(raw)
 check(P.Render(raw) and same(raw,pristine),'O1 expanded: Render leaves the raw model untouched')
 Header(420,'O1 expanded, notice on',LONG,true,true)
 local stats=P.RenderStats()
 check(P.Render(Model()) and P.RenderStats().layouts==stats.layouts and P.RenderStats().noticePasses==stats.noticePasses+1,
  'SETUP O1 expanded: the notice change takes the notice-only update path')
 Header(420,'O1 expanded, notice gone',LONG,true,false)
 local frames=#H.frames
 local opened=Menu()
 check(opened and opened.anchor==menu and opened.frame==P._moreMenu and opened.list[1].isTitle,'O1 expanded: the click opens the Options menu at the control')
 local menuTexts=TopTexts(opened)
 check(same(TopShape(opened),englishShape),'O1 expanded: the Options menu offers the same rows as in English: titles, submenus and their sizes, clicks and states, row by row')
 check(same(menuTexts,FRENCH_MENU),'O1 expanded: every row shows the reviewed frFR words, the Language row naming Fran\195\167ais')
 local localized=0
 for i,text in ipairs(menuTexts)do if text~=englishMenu[i] then localized=localized+1 end end
 check(localized==#menuTexts-2,'O1 expanded: all rows but the two whose reviewed frFR equals English (Questions (FAQ), Session) differ from English ('..localized..')')
 for _,text in ipairs(menuTexts)do check(not text:find(LONG,1,true),'O1 expanded: the menu rows do not carry the label') end
 frames=#H.frames
 local warm={label=menu:GetFontString(),regions=#menu.regions,children=#menu.children,enter=menu:GetScript('OnEnter'),
  leave=menu:GetScript('OnLeave'),click=menu:GetScript('OnClick')}
 local saved=P.SavedLayoutRoot()
 check(P.Render(H.Clone(P._lastModel)) and P.Render(Model({notice=true})) and P.Render(Model()),'SETUP O1 expanded: copied and raw renders')
 check(P.Render(P._lastModel) and menu:GetText()==LONG and P.OptionsLabel()==LONG,'O1 expanded: rendering the committed model again keeps the admitted label once')
 check(P.Render(Model()),'SETUP O1 expanded: render')
 P.Hide()
 check(rawget(saved,'panelHidden')==true and not f:IsShown(),'SETUP O1 expanded: the hide records the existing panelHidden display choice')
 P.Show()
 check(rawget(saved,'panelHidden')==nil and f:IsShown(),'SETUP O1 expanded: the reopen removes it again')
 for _=1,2 do
  Hover(menu)
  opened=Menu()
  check(opened and opened.anchor==menu and opened.frame==P._moreMenu and same(TopTexts(opened),menuTexts),'O1 expanded: reopening the menu keeps its anchor, frame and rows')
 end
 Header(420,'O1 expanded, after refreshes, reopen and menus',LONG,true,false)
 check(#H.frames==frames and menu==f._menuBtn and menu:GetFontString()==warm.label and #menu.regions==warm.regions
  and #menu.children==warm.children and menu:GetScript('OnEnter')==warm.enter and menu:GetScript('OnLeave')==warm.leave
  and menu:GetScript('OnClick')==warm.click and rawget(menu,'_nexusOneLine')==nil,
  'O1 expanded: the same warm control, FontString and registered handlers; no frame, label or hook added')
 check(same(Effects(),baseline),'O1 expanded: since start-up, sweeps, renders, refreshes, hovers, hide / reopen and the menu change no saved root, setting, language, Auto, assignment, action, send, chat, popup or consent')
 check(rawget(NexusDB.settings,'uiLanguage')=='frFR' and Nexus.RecomputeStats().autoEnabled~=true,'O1 expanded: the synthetic frFR choice and Auto OFF stay')
 local sets=0
 for _,entry in ipairs(log)do
  if entry[1]==menu then
   sets=sets+1
   check(entry[2]==LONG or entry[2]=='! '..LONG,'O1 expanded: every SetText of the control is the admitted label (no English reset or double mark): '..tostring(entry[2]):sub(1,40))
  end
 end
 check(sets>=3,'SETUP O1 expanded: the control was set on creation and on renders ('..sets..')')
 -- Charges and names keep their own semantics beside the expanded label.
 check(P.Render(Model({offer=true})) and f._chargesText:IsShown() and f._chargesText:GetText()=='Ban:0 Rel:? Gel:7',
  'O1 expanded: the real charge row keeps the copied frFR template: known 0, unknown ?, known 7')
 Passive('O1 expanded, offer with charges')
 check(Nexus.Readout.ChargesLine({banish=0,freeze=7,trustworthy=false})=='Ban:0 Rel:? Gel:7 ~'
  and L.Format('readout.charge_counts',{banish={known=true,value=0},reroll={known=false},freeze={known=true,value=7}},{})=='B:0 R:? F:7',
  'O1 expanded: the estimate mark follows the whole row; an explicit {} pack gives the English row')
 -- The surrounding Wishlist words localize; the supplied name bytes do not.
 local ESCAPED='Synthetic |||| Wishlist Caf\195\169'
 local shownWishlist=f._contextWishlist:GetText()
 local function Count(text)local n,i=0,1;while true do local s,e=text:find(ESCAPED,i,true);if not s then return n end;n=n+1;i=e+1 end end
 check(shownWishlist==LOCALE.frFR.wishlist and Count(shownWishlist)==1 and Count(englishWishlist)==1
  and P._lastModel.progress.wishlistName==NAME,
  'O1 expanded: the reviewed frFR Wishlist line shows the escaped name byte for byte, once, as in English, and keeps it raw ('..tostring(shownWishlist)..')')
 -- C. The short control: the same route; whole where the model fits it.
 L=Boot('frFR',SHORT)
 Admitted(L,SHORT,'O1 short')
 Sweep('frFR',SHORT,function(model)return SHORT_CUT[model]end,'O1 short')
 -- D. A candidate that begins with "!" is admitted text but never a notice.
 L=Boot('frFR',BANG)
 Admitted(L,BANG,'O1 bang')
 G.UseFont(G.MODELS.default)
 check(Nexus.Panel.OptionsLabel()=='Options' and Nexus.Panel.OptionsText(false)=='Options','O1 bang: OptionsLabel falls back to the English base')
 check(Nexus.Panel.Render(Model()),'SETUP O1 bang: render')
 Header(420,'O1 bang, no notice',"Options",false,false)
 check(Nexus.Panel.Render(Model({notice=true})),'SETUP O1 bang: render with the notice')
 Header(420,'O1 bang, trusted notice',"Options",false,true)
 -- E. Refusals: each invalid candidate is left out by the real loader and
 -- the actual control shows the reviewed English, the rest of frFR intact.
 for _,bad in ipairs(BAD)do
  L=Boot('frFR',bad[2])
  local tag='O1 refused '..bad[1]
  local text,source,reason=L.Text(KEY)
  local row
  for _,r in ipairs(L.Diagnostics().packs.rows)do if r.id=='frFR' then row=r end end
  local keys=#L.Keys()
  check(keys==4078 and text=='Options' and source=='base' and reason=='missing_candidate' and row.accepted==keys-1 and row.rejected==1,
   tag..': the loader refused the one overwritten entry, kept the other '..(keys-1)..' and Options falls back to English ('
    ..tostring(reason)..', accepted '..tostring(row and row.accepted)..', rejected '..tostring(row and row.rejected)..')')
  check(shipped.frFR.entries[KEY]=='Options' and shipped.frFR.entries[KEY]==shippedFacts.options,
   'SETUP '..tag..': the shipped frFR Options entry is unchanged')
  check(select(3,L.Resolve(KEY,{[KEY]=bad[2]}))=='invalid_candidate','SETUP '..tag..': the same bytes are an invalid candidate under the text contract')
  check(Nexus.LocalizationPacks.frFR.entries[KEY]==bad[2] and #Nexus.LocalizationPacks.frFR.entries[KEY]==#bad[2],
   'SETUP '..tag..': the test data kept its own raw bytes ('..#bad[2]..')')
  -- The reviewed frFR keeps the game page name My Builds; Auto OFF is translated.
  check(select(2,L.Text('panel.button.my_builds'))=='candidate' and L.Text('panel.button.my_builds')=='My Builds'
   and select(2,L.Text('panel.button.auto_off'))=='candidate' and L.Text('panel.button.auto_off')=='Auto D\195\137SACTIV\195\137',
   'SETUP '..tag..': the rest of the frFR fixture pack is still active')
  G.UseFont(G.MODELS.default)
  check(Nexus.Panel.Render(Model({notice=true})),'SETUP '..tag..': render')
  Header(420,tag,'Options',false,true)
 end
 rawset(UIParent,'GetEffectiveScale',nil)
 F.fileHooks=nil
 for name in pairs(_G)do if before[name]==nil then rawset(_G,name,nil)end end
 for name,value in pairs(before)do rawset(_G,name,value)end
 local restored=true
 for name,value in pairs(_G)do restored=restored and before[name]==value end
 for name,value in pairs(before)do restored=restored and rawget(_G,name)==value end
 check(restored and F.fileHooks==nil,'O1: the replaced globals, fonts and hooks are restored')
 print('PASS #146 O1 real-loader Options expansion checks='..checks..' (offline models; native NOT_RUN)')
end
