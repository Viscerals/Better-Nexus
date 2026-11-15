-- Issue #165: the HUD menu button reads "Options" (and "! Options" while a
-- trusted update notice is shown) instead of an ellipsis alone. The label is
-- the localized "panel.button.options"; the "!" is code-owned. Header line 1
-- geometry at the panel's own width and a wider panel, 125% text in the LayoutMetrics
-- conservative model, long names and a long localized label, the hover named
-- by the visible control, both Difficulty / Soul Ash HUD modes, the notice
-- route and the menu route. Synthetic fixtures; no game client. Native glyph
-- widths are not proven here.
-- The approved compact panel (design draft "Nexus compact panel": 420
-- reference pixels wide, where the reference panel is 284 units, so one
-- reference pixel is 284/420 of the text scale in units). Its header line 1
-- sizes each control by its own words: Options is as wide as the label it
-- shows, as the client measures it, with the draft's 14 pixels of room
-- (never under the 14 units that keep the label's two 6-unit end caps with 2
-- to spare), held to three tenths of the panel; it is no longer a fixed
-- 92-unit slot with an 80-unit label. The Auto control is sized the same way
-- from its three labels, Close is the draft's 24 pixels, the gaps its 6, and
-- the title keeps the rest. The Build and Wishlist names wrap in their
-- column, and the Wishlist line shows the name alone, with its assignment
-- on the line's hover. Each assertion of the former fixed slots is marked
-- where it stood and replaced by the draft's own assertion, not relaxed:
-- the label, the notice mark, the hover, the route and the passivity checks
-- are unchanged.
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
-- The approved compact control is as wide as its label measures, so the
-- label fits because the control is sized to it, and that needs the
-- control's own measurement in the same model as the label. From here to
-- the end of section 5 every text of this harness therefore measures in the
-- one conservative model (layout_geometry_support UseFont: 8.75 units a
-- character, 17-unit lines, the 15 px owned font; its new font reader is
-- what makes the panel measure its words again), as one face does in the
-- client. A label that changes is followed by the next layout pass
-- (P.PlaceOptionsButton), as a render follows it.
-- One reference pixel in units at this text scale, on whole units.
local function Design(px) return math.max(1,math.floor(px*284/420*1.25+0.5)) end
-- The room around Options' label: the draft's 14 pixels (12 units at 125%)
-- and never under 14 units.
local ROOM=math.max(Design(14),14)
-- The width a render lays the panel out at with 125% text: 284 x 1.25.
local RENDERED=355
local G=dofile('tests/prototype/layout_geometry_support.lua')
G.UseFont({name='125% conservative',char=char,line=17,size=15})
assert(LM.RuntimeMetrics()==1.25 and ROOM==14,'fixture: the conservative model keeps the 125% runtime font scale')
assert(P.Render(Model()) and f:GetWidth()==RENDERED,'fixture: a render in the conservative model, '..RENDERED..' units wide: '..tostring(f:GetWidth()))
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
-- EXPECT: the slot was the fixed 92 x 22 units with an 80-unit label, which
-- both labels fitted. The compact control is the draft's 22 pixels high (19
-- units here) and as wide as the label it shows and its room, with the same
-- two 6-unit end caps.
assert(slots.caps==12 and slots.height==Design(22) and slots.height==19,'Options is the draft\'s 22 pixels high, its label inside two 6-unit end caps: '
 ..tostring(slots.height)..' / '..tostring(slots.caps))
for _,notice in ipairs({false,true})do
 menu:SetText(P.OptionsText(notice))
 slots=P.PlaceOptionsButton()
 local want=math.ceil(#menu:GetText()*char)+ROOM
 assert(menu:GetWidth()==want and slots.optionsWidth==want and label:GetWidth()==want-12,
  'Options is as wide as "'..menu:GetText()..'" measures and its room: '..menu:GetWidth()..' of '..want)
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
-- The approved compact control follows its label only up to three tenths of
-- the panel (106 of this render's 355 units) and is not grown wider than
-- that.
-- v9 (Root's ruling SPEC-A3-A7: "Preserve full long translated captions at
-- current native fonts, including Options ... Let owned
-- text/button/header/progress-row heights grow and wrap as needed. Remove
-- compact-path shortening/font fitting"). After the layout pass that follows
-- a changed label the long label is no longer shortened in that control: it
-- wraps inside the same two end caps and is whole there. Its box is that
-- room wide and as tall as its wrapped lines in this font model (stated here
-- with G.Rows: 17 units a line, more than one line), and the control is as
-- tall as those lines with the draft's 3 pixels above and below them (3
-- units each at 125%), taller than its one-line height. EXPECT: the
-- assertion that stood here asked for the label to stay shortened
-- (LM.Shortened) in a control of the one-line height. Its own line is still
-- wider than its room, which is why its hover names it in full first, as
-- below.
do
 local held=P.PlaceOptionsButton()
 local room=menu:GetWidth()-12
 local lines=G.Rows(LONG_LABEL,room,char)*17
 assert(menu:GetWidth()==math.floor(RENDERED*0.3) and held.optionsWidth==menu:GetWidth() and label:GetWidth()==room
  and label:GetStringWidth()>room and lines>=2*17 and label:GetHeight()==lines
  and menu:GetHeight()==lines+2*Design(3) and menu:GetHeight()>held.height,
  'a long label holds Options at three tenths of the panel and wraps there, whole, in a control as tall as its lines: '
   ..menu:GetWidth()..'x'..tostring(menu:GetHeight())..', label '..tostring(label:GetHeight())..' of '..lines)
end
menu:GetScript('OnEnter')(menu)
assert(tip[1]==LONG_LABEL,'the complete label comes first while its line is wider than its room: '..tostring(tip[1]))
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
-- is a right-edge offset, so the panel's own width and a wider panel keep the
-- same order.
-- The approved compact panel: the widths are the one this render laid the
-- panel out at (355 units at 125% text) and a forced 640. The former pair was
-- 420, the fixed-slot panel's least width, and 640.
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
 assert(f._dragGrip:IsShown() and r.grip.x+r.grip.w<=r.title.x and r.grip.w>=24 and r.grip.h>=24,
  why..': the grip sits before the title as an at-least-24 x 24 UI-unit target')
 -- Distinct, spaced targets on line 1 (design: no clumped Auto/Options/X).
 assert(r.auto.x+r.auto.w+slots.gap<=r.options.x+0.001 and r.options.x+r.options.w+slots.gap<=r.close.x+0.001,
  why..': Auto, Options and Close keep the design gap between them')
 -- The title starts after the drag grip (slots.titleLeft).
 assert(r.title.w==W-slots.reserved-slots.titleLeft,why..': the title keeps the rest of line 1: '..r.title.w)
 assert(r.title.x==slots.titleLeft,why..': the title starts after the grip: '..r.title.x)
 -- The compact slots, stated from the draft and the shown words (not read
 -- from the panel): after the 7-pixel inset come Close (24 pixels), Options
 -- (its shown label and its room) and the Auto control or its state words'
 -- slot (the widest of the three Auto labels, "Auto OFF", and the draft's 16
 -- pixels, never under the 12 units its label fit keeps clear), Options and
 -- the Auto slot each held to three tenths of the panel this render laid
 -- out, 6 pixels apart; the title starts 6 pixels after the 24-unit grip.
 -- EXPECT: the assertion that stood here asked for the 150 units the title
 -- had left of the fixed slots in the 420-unit panel. The title keeps what
 -- the controls' own words leave, and its own word must fit there.
 local limit=math.floor(RENDERED*0.3)
 local optionsW=math.min(limit,math.ceil(#f._menuBtn:GetText()*char)+ROOM)
 local autoW=math.min(limit,math.ceil(#'Auto OFF'*char)+math.max(Design(16),12))
 local reserved=Design(7)+Design(24)+Design(6)+optionsW+Design(6)+autoW+Design(6)
 assert(slots.reserved==reserved and slots.titleLeft==Design(7)+24+Design(6) and slots.gap==Design(6)
  and r.close.w==Design(24) and r.options.w==optionsW and r.auto.w==autoW,
  why..': line 1 keeps the draft\'s slots for these words: '..tostring(slots.reserved)..' of '..reserved)
 assert(f._contextTitle:GetText()=='Nexus' and #'Nexus'*char<=r.title.w,why..': the title\'s own word fits its slot: '..r.title.w)
 assert(r.options.w==slots.optionsWidth and r.auto.w==slots.autoWidth,why..': slot widths')
 local order={'title','auto','options','close'}
 for i=1,#order-1 do
  local a,b=r[order[i]],r[order[i+1]]
  assert(a.x+a.w<=b.x,why..': '..order[i]..' ends before '..order[i+1]..' starts: '..(a.x+a.w)..' > '..b.x)
 end
 assert(r.title.x>=0 and r.close.x+r.close.w<=W,why..': line 1 stays inside the panel')
 assert(r.build.x+r.build.w<=r.switch.x and r.wishlist.x+r.wishlist.w<=r.change.x,
  why..': Build and Wishlist end before My Builds and Change')
 -- The approved compact header's rows. Line 1's row is the at-least-24-unit
 -- grip less the design pixel it stands out above and below (22 units here,
 -- where the draft's 22 pixels are 19), and the title's one line stands in
 -- it. The Build and Wishlist rows are the draft's 20 pixels (16 or 17
 -- units here, each laid on whole units) and as tall as their names' wrapped
 -- lines where that is more: the long names of this fixture wrap in their
 -- column and nothing is shortened (17 units a line in this model). The
 -- rows keep the heights this render's own layout gave them, so at the
 -- forced wider panel a name may need fewer lines than its row holds.
 -- EXPECT: the assertion that stood here held the three to one 20-unit line
 -- each, with the names cut at the column's end.
 local function Lines(region,width) return G.Rows(region:GetText() or '',width,char)*17 end
 local buildLines,wishlistLines=Lines(f._contextBuild,r.build.w),Lines(f._contextWishlist,r.wishlist.w)
 assert(r.title.h==math.max(Design(22),24-2*Design(1)) and r.title.h==22 and Lines(f._contextTitle,r.title.w)==17,
  why..': the title is one line in line 1\'s row: '..r.title.h)
 assert(buildLines>=Design(20) and wishlistLines>=Design(20) and r.build.h>=buildLines and r.wishlist.h>=wishlistLines
  and (W~=RENDERED or (r.build.h==buildLines and r.wishlist.h==wishlistLines)),
  why..': the Build and Wishlist rows hold their names\' wrapped lines whole: '..r.build.h..' / '..buildLines..', '..r.wishlist.h..' / '..wishlistLines)
 -- Main-panel visual correction ("Split Build/Wishlist captions from
 -- values"): each line's label is a caption of its own before the names
 -- (f._contextBuildCaption, f._contextWishlistCaption) and the line's own
 -- text is its value. The assertion that stood here looked for "Build: " and
 -- "Wishlist: " at the start of the two lines' own texts. Both halves are
 -- kept: the labels, each shown as its caption, before its value on the same
 -- row; and the values, each the whole name without its label. The captions
 -- join the pairwise overlap check below.
 local buildCaption,wishlistCaption=f._contextBuildCaption,f._contextWishlistCaption
 assert(buildCaption and buildCaption:IsShown() and buildCaption:GetText()=='Build:'
  and wishlistCaption and wishlistCaption:IsShown() and wishlistCaption:GetText()=='Wishlist:',
  why..': the Build and Wishlist lines keep their labels, each as a caption of its own')
 r.buildCaption,r.wishlistCaption=Rect(buildCaption,W),Rect(wishlistCaption,W)
 assert(r.buildCaption.x+r.buildCaption.w<=r.build.x and r.buildCaption.y==r.build.y
  and r.wishlistCaption.x+r.wishlistCaption.w<=r.wishlist.x and r.wishlistCaption.y==r.wishlist.y
  and r.build.x==r.wishlist.x,
  why..': each caption stands before its value on the same row and the two values share one left edge: '
   ..r.buildCaption.x..'+'..r.buildCaption.w..' / '..r.build.x..' / '..r.wishlist.x)
 local buildValue,wishlistValue=f._contextBuild:GetText() or '',f._contextWishlist:GetText() or ''
 assert(buildValue:find(LONG_BUILD,1,true) and not buildValue:find('^Build:')
  and wishlistValue:find(LONG_WISHLIST,1,true) and not wishlistValue:find('^Wishlist:'),
  why..': two-line Build / Wishlist header: each value is the whole name, without its label: '..buildValue..' / '..wishlistValue)
 local names={}
 for name in pairs(r)do names[#names+1]=name end
 table.sort(names)
 for i=1,#names do for j=i+1,#names do
  assert(not LM.Overlap(r[names[i]],r[names[j]]),why..': '..names[i]..' overlaps '..names[j])
 end end
 assert(f._menuBtn:IsShown() and f._closeBtn:IsShown(),why..': Options and Close are shown')
 -- A forced width is this check's own. The panel gets its render's width
 -- back with its header applied there, so the next render starts from what
 -- a render leaves: the names wrap now, and a render measures them at the
 -- frame's own width, a width a caller gave it included.
 if W~=RENDERED then
  f:SetWidth(RENDERED)
  P.UpdateContextHeader(P._lastModel)
  P.PlaceOptionsButton()
 end
 return autoShown,r
end
assert(P.Render(Model({notice=true})) and f:GetWidth()==RENDERED,'fixture: the render lays the panel out '..RENDERED..' units wide')
for _,W in ipairs({RENDERED,640})do
 assert(CheckHeader(W,'Auto shown at '..W..' px')==true,'fixture: Auto is shown for an active build')
end
assert(P.Render(Model({complete=true})) and f:GetWidth()==RENDERED,'fixture: the render lays the panel out '..RENDERED..' units wide')
for _,W in ipairs({RENDERED,640})do
 assert(CheckHeader(W,'Auto hidden at '..W..' px')==false,'fixture: Auto is hidden for a finished build at 80')
 assert(f._contextAutoState:GetText()=='Auto OFF','the Auto state words take its slot')
end
f:SetWidth(RENDERED)
print('PASS header line 1 order and no overlap at the panel\'s own 355 units and at 640, Auto shown and hidden')

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
-- Main-panel visual correction ("Let this panel width follow text scale
-- through a bounded deterministic rule against actual screen width";
-- "Readability has priority over fixed420 width"): at this fixture's 125%
-- text a render lays the panel out at its reference width x 1.25, and the
-- mirrored status is that render's block. The forced 640 below moves only
-- the header's right-edge slots, as before; the status keeps the place its
-- render gave it, so "inside the panel" is held against the render's own
-- width at both widths (tighter than the forced 640 was). The assertion that
-- stood here held it inside the forced width.
-- The approved compact panel: the reference width is 284 units, so the
-- render's own width is RENDERED, 355 units (section 2); it was 420 x 1.25 =
-- 525. The widths are that one and the forced 640 (they were the forced 420
-- and 640).
for _,mode in ipairs({'nexus','server'})do
 status.SetMode(mode)
 assert(status.IsUsingNexusHud()==(mode=='nexus'),'fixture: the '..mode..' HUD is the preference')
 for _,complete in ipairs({false,true})do
  assert(P.Render(Model({notice=true,complete=complete,status=mode=='nexus'})),'render in '..mode..' mode')
  assert(f:GetWidth()==RENDERED,'at 125% text the render lays the panel out '..RENDERED..' units wide (284 x 1.25): '..tostring(f:GetWidth()))
  local line=f._play and f._play.server
  for _,W in ipairs({RENDERED,640})do
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
    assert(s.y>=bottom and s.x>=0 and s.x+s.w<=RENDERED,
     why..': the mirrored status sits below the header rows, inside the panel its render laid out: y '..s.y..' < '..bottom
      ..', right edge '..(s.x+s.w)..' of '..RENDERED)
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
f:SetWidth(RENDERED)
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
-- "panel.button.options" (the shipped frFR already holds its own
-- reviewed "Options", which stays unchanged); the real
-- core/Localization.lua then checks and copies it, frFR is chosen only in the
-- synthetic settings, and Panel.Render, OptionsLabel / OptionsText,
-- PlaceOptionsButton and the registered OnEnter / OnLeave / OnClick of the
-- actual NexusPanel._menuBtn do the rest. TEST-ONLY expansion text: no new
-- language ID, no shipped pack, key, cap or data change, no translation.
-- Geometry is the stated uniform-character models of layout_geometry_support
-- (default, 16 px face, 0.75, 2.0) and the 125% conservative model of section
-- 2, at UI scales 1 and 0.64, the panel's own width and a forced 640, and a
-- 640x480 screen: a regression model, not native glyph, wide-script font or
-- pixel proof. Native focus, Escape, hit order and tooltip drawing are NOT
-- RUN; a harness Click is not a native click. The approved compact control is
-- as wide as its label up to three tenths of the panel and is not grown
-- wider than that (it was a fixed 92x22 control). v9 (Root's ruling
-- SPEC-A3-A7): a longer label is not shortened there any more. It wraps in
-- the control, whole, the control and header line 1 grow for it, and its
-- own hover still names the complete label first (EXPECT: "a longer label
-- is shortened there, and its own hover recovers the complete label").
-- v11 (Root's disposition on partial packs: "Full shipped frFR completeness
-- is not a current panel UI-test prerequisite"): a pack may hold fewer
-- entries than the English catalog, and a key it lacks falls back to
-- English. This section asks nothing about how many entries the shipped
-- frFR holds. The hook counts the entries of the copy it hands the loader,
-- before the loader runs, and every accepted and rejected figure asked of
-- the loader is stated from that count; part F hands over a copy without
-- its Options entry and asks for the English word in the French panel.
-- (EXPECT: the shipped frFR one entry per English key, and the loader's
-- frFR row equal to the size of the English catalog.)
-- Self-contained: it reads nothing the sections above set up, and restores
-- the globals it replaces.
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
 -- v11: given to Boot in place of a candidate text, it has the hook leave
 -- the copied frFR Options entry out (part F). A table of its own, so it
 -- equals no text.
 local OMIT={}
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
 -- Literal fits of the short control: visible characters x model width
 -- ("Réglages" 8, "! Réglages" 10).
 -- The approved compact control is sized to the label it shows, so the short
 -- label is whole in every model: with its room it stays under the three
 -- tenths of the panel that hold the control (58 and 69 of 85 units in the
 -- default face, 70 and 84 of 85 at 16 px, 48 and 56 of 85 at 0.75, 107 and
 -- 129 of 170 at 2.0, 84 and 102 of 106 at 125%). EXPECT: in the fixed 80 px
 -- label room it was cut at 2.0 (both) and, with the notice mark, at 125%.
 local SHORT_CUT={[G.MODELS.default]={false,false},[G.MODELS.px16]={false,false},
  [G.MODELS.small]={false,false},[G.MODELS.double]={false,false},[C125]={false,false}}
 -- Independent literal expectations of the surrounding presentation, per
-- active language: the reviewed English base and the reviewed shipped frFR
-- values (panel.tooltip.options_contents, panel.tooltip.update_available,
-- panel.tooltip.update_releases_link, panel.label.auto_state_off,
-- panel.label.context_wishlist with usertext.value.wishlist_assigned_named).
-- Only the Options label itself is the test candidate; the help, notice,
-- Auto state and Wishlist words are the language's own and localize.
-- The approved compact panel: the Wishlist line shows the name alone (the
-- reviewed line with the destination's own compact form of the name) and
-- the line's hover keeps the reviewed line with its state. `wishlist` is
-- the line as shown; `assigned` is the reviewed line with its state, as it
-- stood on the line itself (the literal that was `wishlist`).
 -- v9 (Root's ruling ST8-2: "Fix the misleading Main Options help ...
 -- through semantic composition from EXISTING localized menu/control labels
 -- ... Leave the existing options_contents definition untouched; if not used
 -- in Main, report this explicitly with the fixture consequence"). The
 -- reviewed sentence (`help`, panel.tooltip.options_contents) ends "Plan,
 -- Explore and Orbs are on the footer", and the compact footer's hubs read
 -- Wishlist, Builds and Orbs. The compact panel's hover no longer shows that
 -- sentence: under the control's name it lists the Options menu's own five
 -- group titles (`sections`: panel.menu.section_help, _settings, _notices,
 -- _session, _panel), each whole on a line of its own, in the menu's order.
 -- `sections` are independent literals: the reviewed English, and for frFR
 -- the same five reviewed titles FRENCH_MENU below already states as rows of
 -- the opened menu. `help` stays as the literal of the sentence's untouched
 -- definition, which Header asks for and asks not to be on the hover.
 -- EXPECT: `help` was the hover's second line (Want), in both languages.
 local LOCALE={
  enUS={help='Help and setup, settings, notices, logs and panel actions. Plan, Explore and Orbs are on the footer.',
   sections={'Help and setup','Settings','Notices','Session','Panel'},
   notice='Update available: 1.20.0-beta.1 test.9029',
   releases='Open this menu for the manual Releases-page link.',
   autoOff='Auto OFF',
   wishlist='Wishlist: Synthetic |||| Wishlist Caf\195\169',
   assigned='Wishlist: Synthetic |||| Wishlist Caf\195\169 (assigned)'},
  frFR={help='Aide et configuration, param\195\168tres, avis, journaux et actions du panneau. Plan, Explorer et Orbs sont en bas du panneau.',
   sections={'Aide et configuration','Param\195\168tres','Avis','Session','Panneau'},
   notice='Mise \195\160 jour disponible : 1.20.0-beta.1 test.9029',
   releases='Ouvrez ce menu pour le lien manuel vers la page Releases.',
   autoOff='Auto D\195\137SACTIV\195\137',
   wishlist='Liste de souhaits : Synthetic |||| Wishlist Caf\195\169',
   assigned='Liste de souhaits : Synthetic |||| Wishlist Caf\195\169 (assign\195\169e)'},
 }
 local function Words()
  local words=LOCALE[(Nexus.Localization.ActiveLanguage())]
  assert(words,'SETUP O1: literal expectations exist for the active language')
  return words
 end
 -- The control's own hover: its name heads it, complete and wrapped while
 -- the name's own line is wider than its room in the button (with or without
 -- the trusted "! "), so the complete label is shown exactly once; then the
 -- menu's five group titles (v9: `sections`; EXPECT: the one `help`
 -- sentence) and the notice, in the active language.
 local function Want(label,notice,shortened)
  local words,out=Words(),{}
  out[#out+1]={label,1,1,1,shortened or nil}
  for _,title in ipairs(words.sections)do out[#out+1]={title,0.8,0.8,0.8,true} end
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
 -- (v11: OMIT has the hook leave the copied frFR Options entry out; any
 -- other value is put there, as before.)
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
   if options==OMIT then packs.frFR.entries[KEY]=nil else packs.frFR.entries[KEY]=options end
   -- v11 (Root's disposition, required 2): the fixture's own INPUT, counted
   -- here, before the real loader (core\Localization.lua, the next file of
   -- the TOC) checks it: how many entries the copied frFR is handed over
   -- with. Every accepted and rejected figure asked of the loader below is
   -- stated from this count and from what the case did to the Options
   -- entry, never from the loader's own diagnostics and never from the
   -- size of the English catalog.
   local supplied=0;for _ in pairs(packs.frFR.entries)do supplied=supplied+1 end
   shippedFacts.supplied=supplied
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
 -- v9 (ST8-2): the opened menu's own group titles, in its order: what the
 -- hover's help lines must be (LOCALE sections), read from the real menu.
 local function TopTitles(opened)
  local out={}
  for _,item in ipairs(opened and opened.list or {})do
   if item.isTitle==true then out[#out+1]=tostring(item.text) end
  end
  return out
 end
 -- The approved compact header's line 1 (design draft "Nexus compact
 -- panel"), stated from the draft, the active font model and the shown
 -- words; not read from the panel. One reference pixel is 284/420 of the
 -- text scale in units, laid on whole units (Design). From the right edge:
 -- the 7-pixel inset; Close, 24 pixels; Options, as wide as the label it
 -- shows measures in the model and its room (the draft's 14 pixels and
 -- never under 14 units: its label's two 6-unit end caps and 2 to spare);
 -- the Auto control, or the Auto state words in its slot, as wide as the
 -- widest of the three Auto labels and the draft's 16 pixels (never under
 -- the 12 units its label fit keeps clear). Options and the Auto slot are
 -- each held to three tenths of the panel the render laid out (`own`). The
 -- three are 6 pixels apart and 22 pixels high, in the middle of line 1's
 -- row, which starts 5 pixels down and is 22 pixels or, where that is more,
 -- the at-least-24-unit grip less the design pixel it stands out above and
 -- below. The grip stands at the inset, centred on that row; the title
 -- starts 6 pixels after it and ends 6 pixels before the Auto slot, in the
 -- row's height or its own wrapped lines where they need more. As {left,
 -- top, right, bottom}.
 -- EXPECT: the slots that stood here were the former fixed literals (Close
 -- 24 at the 10-unit edge, Options 92 with an 80-unit label, Auto 84, 8-unit
 -- gaps, the grip at (8, 6), the title from 36).
 local function Design(px)
  local scale=math.max(0.75,math.min(2,(G.model and G.model.size or 12)/12))
  return math.max(1,math.floor(px*284/420*scale+0.5))
 end
 local function Wide(text) return math.ceil(G.Length(G.Visible(text))*G.model.char) end
 -- The width a render lays the panel out at: 284 units x the text scale
 -- (from 1 to 2), or what the screen leaves it at its chosen size where that
 -- is less, never under 284 (stated from the model, the screen and the
 -- chosen size; it was 420 units x the text scale).
 local function OwnWidth()
  local width=math.floor(284*math.max(1,math.min(2,(G.model and G.model.size or 12)/12))+0.5)
  local screen,chosen=tonumber(UIParent:GetWidth()),Nexus.Panel.PanelScale()
  if screen and screen>=640 then width=math.min(width,math.floor((screen-24)/chosen)) end
  return math.max(284,width)
 end
 -- v9 (Root's ruling SPEC-A3-A7: whole labels in the compact controls, no
 -- shortening and no smaller font; the control and line 1 grow instead).
 -- The widths above are unchanged. What a control held to three tenths of
 -- the panel does with words wider than its room is new, and is stated here
 -- from the same words, the font model and the draft, not read from the
 -- panel:
 --   Options: its label's room is the control less its two 6-unit end caps.
 --   A label wider than that wraps there; its box is as tall as its wrapped
 --   lines (G.Rows) and stands in the control's middle, and the control is
 --   those lines with the draft's 3 pixels above and below them;
 --   the Auto control: its labels' room is the control less the 12 units its
 --   label fit keeps clear. When the widest of its three labels is wider
 --   than that, the control is as tall as the tallest of the three wrapped
 --   there with the same 3 pixels, whichever label it shows;
 --   the Auto state words (the control hidden): words wider than the slot
 --   wrap in it and their box is as tall as their wrapped lines.
 -- A control whose words fit keeps the draft's 22 pixels, as before. `stated`
 -- is the Auto state text the header shows (nil while the control is shown).
 -- EXPECT: every control and the state words had the one 22-pixel height
 -- whatever their words (slot = auto = state; the label box the control's).
 local function Slots(W,own,shown,title,stated)
  local L=Nexus.Localization
  local edge,close,gap,high=Design(7),Design(24),Design(6),Design(22)
  local grip=math.max(24,Design(24))
  local row=math.max(Design(22),grip-2*Design(1))
  local top=Design(5)+math.floor((row-high)/2)
  local limit=math.floor(own*0.3)
  local autoWords={(L.Text('panel.button.auto_on')),(L.Text('panel.button.auto_off')),(L.Text('panel.button.auto_unknown'))}
  local widest=math.max(Wide(autoWords[1]),Wide(autoWords[2]),Wide(autoWords[3]))
  local options=math.min(limit,Wide(shown)+math.max(Design(14),14))
  local auto=math.min(limit,widest+math.max(Design(16),12))
  local closeLeft=W-edge-close
  local optionsLeft=closeLeft-gap-options
  local autoLeft=optionsLeft-gap-auto
  local titleLeft,titleRight=edge+grip+gap,autoLeft-gap
  local titleHigh=math.max(row,G.Rows(title,titleRight-titleLeft,G.model.char)*G.model.line)
  local gripTop=Design(5)-math.floor((grip-row)/2)
  local pad=Design(3)
  local function Lines(words,room) return G.Rows(words,room,G.model.char)*G.model.line end
  local optionsWraps=Wide(shown)>options-12
  local labelHigh=optionsWraps and Lines(shown,options-12) or high
  local optionsHigh=optionsWraps and math.max(high,labelHigh+2*pad) or high
  local labelTop=top+(optionsHigh-labelHigh)/2
  local autoHigh=high
  if widest>auto-12 then
   autoHigh=math.max(high,math.max(Lines(autoWords[1],auto-12),Lines(autoWords[2],auto-12),Lines(autoWords[3],auto-12))+2*pad)
  end
  local stateHigh=high
  if stated and G.Length(G.Visible(stated))*G.model.char>auto then stateHigh=math.max(high,Lines(stated,auto)) end
  return {options={optionsLeft,top,optionsLeft+options,top+optionsHigh},
   label={optionsLeft+6,labelTop,optionsLeft+options-6,labelTop+labelHigh},
   close={closeLeft,top,W-edge,top+high},auto={autoLeft,top,autoLeft+auto,top+autoHigh},
   state={autoLeft,top,autoLeft+auto,top+stateHigh},grip={edge,gripTop,edge+grip,gripTop+grip},
   title={titleLeft,Design(5),titleRight,Design(5)+titleHigh},optionsWidth=options,high=high,gap=gap,
   optionsWraps=optionsWraps,optionsHigh=optionsHigh,labelHigh=labelHigh,autoHigh=autoHigh,stateHigh=stateHigh}
 end
 -- W: a width forced on the panel for this check, or nil for the width its
 -- render laid it out at.
 local function Header(W,why,want,expectShort,notice)
  local f,P=NexusPanel,Nexus.Panel
  local own=f:GetWidth()
  check(own==OwnWidth(),'SETUP O1 '..why..': the render laid the panel out at its own width for this text scale and screen ('
   ..tostring(own)..' of '..OwnWidth()..')')
  if W then f:SetWidth(W);P.UpdateContextHeader(P._lastModel);P.PlaceOptionsButton() else W=own end
  check(f:GetWidth()==W,'SETUP O1 '..why..': the panel is '..W..' px wide')
  local menu=f._menuBtn
  local label=menu:GetFontString()
  local shown=(notice and '! ' or '')..want
  check(menu:GetText()==shown and label and label:GetText()==shown,
   why..': the actual Options control and its FontString show the admitted text exactly ('..tostring(menu:GetText())..')')
  local autoShown=f._autoBtn:IsShown()
  local slots=Slots(W,own,shown,f._contextTitle:GetText() or '',not autoShown and f._contextAutoState:GetText() or nil)
  -- EXPECT: Options kept its fixed 92x22 slot and a one-line 80x22 label and
  -- did not grow. It is as wide as its label and its room, up to three
  -- tenths of the panel and never past that, in the draft's 22-pixel
  -- height, with a one-line label inside its two 6-unit end caps.
  -- v9: that is what a label that fits its room still is (the same sizes,
  -- wordWrap==false). A label wider than its room wraps there instead of
  -- being shortened: its box is the room wide and as tall as its wrapped
  -- lines, the control as tall as those lines with the draft's 3 pixels
  -- above and below, and wordWrap is on (Slots). EXPECT: the check that
  -- stood here asked every label, the long one too, for the one-line box
  -- (the control's 22 pixels, wordWrap==false).
  check(menu:GetWidth()==slots.optionsWidth and menu:GetWidth()<=math.floor(own*0.3) and menu:GetHeight()==slots.optionsHigh
   and label:GetWidth()==slots.optionsWidth-12 and label:GetHeight()==slots.labelHigh and label.wordWrap==slots.optionsWraps
   and (not slots.optionsWraps or (slots.labelHigh>=2*G.model.line and slots.optionsHigh>slots.high)),
   why..': Options is as wide as its label and its room, held to three tenths of the panel, with its label inside its end caps: '
    ..(slots.optionsWraps and 'wrapped whole, the control as tall as its lines (' or 'one line (')
    ..tostring(menu:GetWidth())..'x'..tostring(menu:GetHeight())..' of '..slots.optionsWidth..'x'..slots.optionsHigh
    ..', label '..tostring(label:GetHeight())..' of '..slots.labelHigh..')')
  local r={options=G.Rect(menu,f),label=G.Rect(label,f),close=G.Rect(f._closeBtn,f),
   auto=G.Rect(autoShown and f._autoBtn or f._contextAutoState,f),grip=G.Rect(f._dragGrip,f),title=G.Rect(f._contextTitle,f)}
  check(same(r.options,slots.options) and same(r.label,slots.label) and same(r.close,slots.close)
   and same(r.auto,autoShown and slots.auto or slots.state) and same(r.grip,slots.grip) and same(r.title,slots.title),
   why..': header line 1 keeps the draft\'s slots for these words: Options '..G.Text(r.options)..', label '..G.Text(r.label)..', Auto '..G.Text(r.auto)
    ..', Close '..G.Text(r.close)..', grip '..G.Text(r.grip)..', title '..G.Text(r.title))
  check(G.Inside(r.label,{r.options[1]+6,r.options[2],r.options[3]-6,r.options[4]}),why..': the label stays inside Options less its end caps')
  -- (EXPECT: the gaps were 8 units; they are the draft's 6 pixels.)
  check(r.auto[3]+slots.gap<=r.options[1] and r.options[3]+slots.gap<=r.close[1] and r.grip[3]<=r.title[1] and r.title[3]<=r.auto[1],
   why..': grip, title, Auto, Options and Close stay in order with the draft\'s 6-pixel gaps')
  local names={'options','close','auto','grip','title'}
  for i=1,#names do for j=i+1,#names do
   check(G.Apart(r[names[i]],r[names[j]]),why..': '..names[i]..' and '..names[j]..' do not overlap')
  end end
  check(G.Inside(r.options,{0,0,W,f:GetHeight()}) and G.Inside(r.close,{0,0,W,f:GetHeight()}),why..': line 1 stays inside the panel')
  check(G.Visible(autoShown and f._autoBtn:GetText() or f._contextAutoState:GetText())==Words().autoOff,
   why..': Auto reads exactly the active language\'s reviewed Auto OFF words ('..Words().autoOff..')')
  -- (v9: a label whose own line is wider than its room is the one that
  -- wraps, and it is whole there, as checked above; it is not shortened.
  -- EXPECT: this check said such a label was shortened. The literal
  -- expectation per model is unchanged and is asked of the derived slots
  -- too.)
  check(Nexus.LayoutMetrics.Shortened(label)==expectShort and slots.optionsWraps==expectShort,
   why..': the label\'s own line is '..(expectShort and 'wider than its room, so it wraps there' or 'whole in its room')
    ..' in this model ('..label:GetStringWidth()..' in '..tostring(label:GetWidth())..')')
  local lines,owners,cycle=Hover(menu)
  -- Every visible tooltip line counts, whatever its colour or wrap flag.
  local full=0
  for _,line in ipairs(lines)do if tostring(line[1]):find(want,1,true) then full=full+1 end end
  check(full==1,why..': the complete label appears in exactly one visible hover line ('..full..')')
  check(same(lines,Want(want,notice,expectShort)) and #owners==1 and owners[1][1]==menu
   and owners[1][2]=='ANCHOR_TOPLEFT' and cycle,
   why..': the registered hover takes the tooltip once and gives the '..(expectShort and 'complete ' or '')
    ..'control name, its help'..(notice and ' and the complete trusted notice' or '')..' ('..#lines..' lines)')
  -- v9 (ST8-2): the reviewed sentence that names the footer hubs Plan and
  -- Explore keeps its definition, unchanged, in the active language, and
  -- the compact panel's hover shows it on no line.
  local sentence,onHover=(Nexus.Localization.Text('panel.tooltip.options_contents')),false
  for _,line in ipairs(lines)do if tostring(line[1])==Words().help then onHover=true end end
  check(sentence==Words().help and not onHover,
   why..': the reviewed Options sentence that names Plan and Explore on the footer is still defined, unchanged, and is not on the compact panel\'s hover')
  Passive(why)
  -- A forced width is this check's own: the panel gets its render's width
  -- back with its header applied there.
  if W~=own then f:SetWidth(own);P.UpdateContextHeader(P._lastModel);P.PlaceOptionsButton() end
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
      -- (The panel's own width, then a forced 640; they were the forced
      -- 420 and 640.)
      for _,W in ipairs({false,640})do
       Header(W or nil,tag..', '..model.name..', UI '..ui..', '..(complete and 'finished' or 'in progress')
        ..(notice and ', notice' or '')..', '..(W and (W..' px') or 'its own width'),want,cut(model)[notice and 2 or 1],notice)
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
   Header(nil,tag..', '..model.name..', 640x480 screen',want,cut(model)[2],true)
   UIParent:SetSize(1920,1080)
  end
  rawset(UIParent,'GetEffectiveScale',uiScale)
  G.UseFont(G.MODELS.default)
 end
 -- The shipped frFR table is untouched: same table, same entry count, its own
-- reviewed "Options" (equal to the English word in the reviewed frFR draft),
-- while the deep copy differs from it only in the overwritten Options entry.
 -- v11 (Root's disposition, required 4: "Retire ONLY the assertion that the
 -- shipped frFR input has one entry per English key; prove no original entry
 -- is lost/altered, and copies differ only in the explicitly changed Options
 -- entry"). How many entries the shipped frFR holds is not compared with the
 -- English catalog any more: a pack may be partial. EXPECT: the second check
 -- carried "count==#Nexus.Localization.Keys()". It still asks that the
 -- shipped table holds as many entries as the hook counted in it (none lost,
 -- none added), and the loop before it that every other copied entry is the
 -- shipped one (none altered). New in it: the copy holds exactly the entries
 -- the hook counted in it for the loader (shippedFacts.supplied), which is as
 -- many as the shipped table when its Options entry was overwritten (`want`
 -- is the text put there) and one fewer when the hook left that entry out
 -- (`want` is nil, part F).
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
  check(count==shippedFacts.count and copied==(want==nil and count-1 or count) and copied==shippedFacts.supplied,
   tag..': the shipped frFR still holds its '..count..' entries; the copy '..(want==nil and 'one fewer' or 'as many')..' ('..copied
    ..'), the number the hook counted for the loader ('..tostring(shippedFacts.supplied)..')')
  check(shipped.frFR.entries[KEY]=='Options' and shippedFacts.options=='Options' and shipped.frFR.entries[KEY]~=want,
   tag..': the shipped frFR keeps its own reviewed Options entry, unchanged'
    ..(want==nil and ', while the copy has none' or ' and different from the test text'))
  check(copy.frFR.entries[KEY]==want and others,tag..': only the copied Options entry '
   ..(want==nil and 'is left out' or 'holds the test text')..'; every other copied entry is the shipped one')
 end
 -- v11: what every boot through the hook is asked about the pack the loader
 -- was handed, whatever the case did to its Options entry (`want` as for
 -- Shipped). It is the body Admitted had after its first check, which
 -- Admitted still runs first; part F runs it after its own first check.
 local function Loaded(L,want,tag)
  local base,baseSource=L.Resolve(KEY)
  check(base=='Options' and baseSource=='base' and Nexus.LocalizationEnglish[KEY]=='Options',tag..': pure Resolve and the English base stay Options')
  local row
  for _,r in ipairs(L.Diagnostics().packs.rows)do if r.id=='frFR' then row=r end end
  local ids={}
  for _,language in ipairs(L.Languages())do ids[#ids+1]=language.id..'='..language.name end
  -- The English catalog is asked strictly, as before: 4116 keys, every one
  -- of them admitted English. (v45: 4116 is the accepted catalog since the
  -- 4 opacity and 16 FAQ meanings joined the earlier 4096; it stays an
  -- independent literal, never read from the loader or the table.)
  local keys=#L.Keys()
  check(keys==4116 and L.Diagnostics().base.accepted==keys,tag..': the English base holds the 4116-key catalog ('..keys..')')
  -- v11 (Root's disposition, required 2 and 3): the loader's frFR row is
  -- asked for the hook's own count of the entries it handed over
  -- (shippedFacts.supplied, counted before the loader ran): every one of
  -- them accepted and none rejected, the overwritten Options entry among
  -- them where the case put one there. An entry the loader cannot admit,
  -- under whichever key, is a rejection and fails here; none is excused.
  -- EXPECT: "row.accepted==keys", the pack one entry per English key.
  local supplied=shippedFacts and shippedFacts.supplied
  check(table.concat(ids,',')=='enUS=English,frFR=Fran\195\167ais,deDE=Deutsch,esES=Espa\195\177ol,plPL=Polski,ptBR=Portugu\195\170s (Brasil),ruRU=\208\160\209\131\209\129\209\129\208\186\208\184\208\185'
   and L.Diagnostics().packs.adopted==6 and L.Diagnostics().packs.refused==0 and row and row.accepted==supplied and row.rejected==0,
   tag..': the same seven offered languages, no pseudo language; frFR admitted every one of the '..tostring(supplied)
    ..' entries it was handed'..(want==nil and '' or ', the overwritten Options among them')..', and rejected none ('
    ..table.concat(ids,',')..'; '..tostring(row and row.accepted)..'/'..tostring(row and row.rejected)..')')
  Shipped(tag,want)
 end
 local function Admitted(L,want,tag)
  local text,source,reason=L.Text(KEY)
  check(text==want and source=='candidate' and reason==nil,tag..': the real loader admitted the test candidate ('..tostring(source)..')')
  Loaded(L,want,tag)
 end
 -- A. English control: the shipped data, no hook.
 local L=Boot(nil,nil)
 G.UseFont(G.MODELS.default)
 check(L.Text(KEY)=='Options' and select(2,L.Text(KEY))=='base','SETUP O1 English: the shipped data shows Options')
 check(Nexus.Panel.Render(Model()),'SETUP O1 English: render')
 Passive('O1 English render')
 -- Main-panel visual correction ("Split Build/Wishlist captions from
 -- values"): the Wishlist line's label is a caption of its own
 -- (NexusPanel._contextWishlistCaption) and NexusPanel._contextWishlist holds
 -- the value. The line is read as the player reads it, the shown caption and
 -- then the value, so the reviewed line keeps its whole literal; the caption
 -- and the value are then each checked on their own.
 local englishCaption=NexusPanel._contextWishlistCaption
 local englishValue=NexusPanel._contextWishlist:GetText()
 local englishWishlist=englishValue
 if englishCaption and englishCaption:IsShown() and (englishCaption:GetText() or '')~='' then
  englishWishlist=englishCaption:GetText()..' '..tostring(englishValue)
 end
 local englishOpened=Menu()
 local englishMenu,englishShape=TopTexts(englishOpened),TopShape(englishOpened)
 check(englishWishlist==LOCALE.enUS.wishlist and #englishMenu>10 and #englishMenu==#FRENCH_MENU,
  'SETUP O1 English: the escaped Wishlist name and the Options menu ('..tostring(englishWishlist)..', '..#englishMenu..' rows)')
 -- v9 (ST8-2): the five lines the hover lists (LOCALE sections, asked of
 -- the real hover by Header) are the real menu's own group titles, in the
 -- menu's order, so the hover names exactly the groups the menu then shows.
 check(same(TopTitles(englishOpened),LOCALE.enUS.sections),
  'O1 English: the opened Options menu has exactly the five group titles its hover lists, in the same order ('
   ..table.concat(TopTitles(englishOpened),' / ')..')')
 -- The approved compact Wishlist line. EXPECT: the value was the escaped
 -- name with its state, "(assigned)". It is the escaped name alone, and the
 -- line's own registered hover keeps the reviewed line with its state.
 local englishHover={}
 for _,line in ipairs((Hover(NexusPanel._contextWishlistHit)))do englishHover[#englishHover+1]=tostring(line[1]) end
 englishHover=table.concat(englishHover,'\n')
 check(englishCaption~=nil and englishCaption:IsShown() and englishCaption:GetText()=='Wishlist:'
  and englishValue=='Synthetic |||| Wishlist Caf\195\169' and englishHover:find(LOCALE.enUS.assigned,1,true)~=nil,
  'SETUP O1 English: the label Wishlist: is a caption of its own, its value is the escaped name alone and its hover keeps the line with its state ('
   ..tostring(englishValue)..' / '..englishHover..')')
 -- The English control keeps the English hover, notice and Auto OFF words.
 check(Nexus.Panel.Render(Model({notice=true})),'SETUP O1 English: render with the notice')
 Header(nil,'O1 English, trusted notice','Options',false,true)
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
 Header(nil,'O1 expanded, notice on',LONG,true,true)
 local stats=P.RenderStats()
 check(P.Render(Model()) and P.RenderStats().layouts==stats.layouts and P.RenderStats().noticePasses==stats.noticePasses+1,
  'SETUP O1 expanded: the notice change takes the notice-only update path')
 Header(nil,'O1 expanded, notice gone',LONG,true,false)
 local frames=#H.frames
 local opened=Menu()
 check(opened and opened.anchor==menu and opened.frame==P._moreMenu and opened.list[1].isTitle,'O1 expanded: the click opens the Options menu at the control')
 local menuTexts=TopTexts(opened)
 check(same(TopShape(opened),englishShape),'O1 expanded: the Options menu offers the same rows as in English: titles, submenus and their sizes, clicks and states, row by row')
 check(same(menuTexts,FRENCH_MENU),'O1 expanded: every row shows the reviewed frFR words, the Language row naming Fran\195\167ais')
 check(same(TopTitles(opened),LOCALE.frFR.sections),
  'O1 expanded: the opened Options menu has exactly the five reviewed frFR group titles its hover lists, in the same order ('
   ..table.concat(TopTitles(opened),' / ')..')')
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
 Header(nil,'O1 expanded, after refreshes, reopen and menus',LONG,true,false)
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
 -- v12 (Root's focused run stopped at the check below): the charge counts
 -- are counts, and the panel shows them only while Details is open
 -- (Panel.ChargesLineShown; the base, eef1608f, has the same rule, and the
 -- check never ran there: it stood behind the '4078' stop). This render had
 -- Details closed, as the panel opens, and asked for the row. Both states
 -- are asked now. Closed: no row is shown, while the model still carries the
 -- charge facts (nothing is dropped, only not drawn). Open (the panel's own
 -- memory-only switch, what its Details control toggles; set and put back
 -- here as ux_manual_recommendation's WithDetails does): the real row with
 -- the copied frFR template, known 0, unknown ?, known 7, exactly as the
 -- check stated it. EXPECT: that row with Details closed.
 check(P.Render(Model({offer=true})) and P._playDetails~=true and not f._chargesText:IsShown()
  and type(P._lastModel.charges)=='table' and P._lastModel.charges.banish==0 and P._lastModel.charges.freeze==7,
  'O1 expanded: with Details closed the charge counts are not drawn; the model keeps the facts')
 local wasDetails=P._playDetails
 P._playDetails=true
 check(P.Render(Model({offer=true})) and f._chargesText:IsShown() and f._chargesText:GetText()=='Ban:0 Rel:? Gel:7',
  'O1 expanded: the real charge row keeps the copied frFR template: known 0, unknown ?, known 7')
 Passive('O1 expanded, offer with charges')
 P._playDetails=wasDetails
 check(P.Render(Model({offer=true})) and P._playDetails~=true and not f._chargesText:IsShown(),
  'O1 expanded: with Details closed again the charge row is gone')
 check(Nexus.Readout.ChargesLine({banish=0,freeze=7,trustworthy=false})=='Ban:0 Rel:? Gel:7 ~'
  and L.Format('readout.charge_counts',{banish={known=true,value=0},reroll={known=false},freeze={known=true,value=7}},{})=='B:0 R:? F:7',
  'O1 expanded: the estimate mark follows the whole row; an explicit {} pack gives the English row')
 -- The surrounding Wishlist words localize; the supplied name bytes do not.
 local ESCAPED='Synthetic |||| Wishlist Caf\195\169'
 local shownWishlist=f._contextWishlist:GetText()
 local function Count(text)local n,i=0,1;while true do local s,e=text:find(ESCAPED,i,true);if not s then return n end;n=n+1;i=e+1 end end
 -- (The approved compact Wishlist line: the reviewed frFR line with the
 -- name alone, and the line with its state on the line's own hover. EXPECT:
 -- the line itself ended with the state, "(assign\195\169e)".)
 local frenchHover={}
 for _,line in ipairs((Hover(f._contextWishlistHit)))do frenchHover[#frenchHover+1]=tostring(line[1]) end
 frenchHover=table.concat(frenchHover,'\n')
 check(shownWishlist==LOCALE.frFR.wishlist and Count(shownWishlist)==1 and Count(englishWishlist)==1
  and frenchHover:find(LOCALE.frFR.assigned,1,true)~=nil and P._lastModel.progress.wishlistName==NAME,
  'O1 expanded: the reviewed frFR Wishlist line shows the escaped name byte for byte, once, as in English, keeps it raw, and its hover keeps the line with its state ('
   ..tostring(shownWishlist)..' / '..frenchHover..')')
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
 Header(nil,'O1 bang, no notice',"Options",false,false)
 check(Nexus.Panel.Render(Model({notice=true})),'SETUP O1 bang: render with the notice')
 Header(nil,'O1 bang, trusted notice',"Options",false,true)
 -- E. Refusals: each invalid candidate is left out by the real loader and
 -- the actual control shows the reviewed English, the rest of frFR intact.
 for _,bad in ipairs(BAD)do
  L=Boot('frFR',bad[2])
  local tag='O1 refused '..bad[1]
  local text,source,reason=L.Text(KEY)
  local row
  for _,r in ipairs(L.Diagnostics().packs.rows)do if r.id=='frFR' then row=r end end
  local keys=#L.Keys()
  -- v11 (Root's disposition, required 3: "exactly ONE rejection and all
  -- other supplied entries accepted"): the figures are stated from the
  -- hook's own counts, taken before the loader ran. The copied frFR was
  -- handed over with as many entries as the shipped frFR holds, the bad
  -- candidate in place of its Options entry (SETUP); the loader's row is
  -- then that count less the one refused, and one rejected. EXPECT:
  -- "row.accepted==keys-1", the pack one entry per English key. The strict
  -- English count stays in the check.
  local supplied=shippedFacts and shippedFacts.supplied
  check(type(supplied)=='number' and supplied==shippedFacts.count,
   'SETUP '..tag..': the hook handed the loader as many entries as the shipped frFR holds, the bad candidate in place of its Options entry ('
    ..tostring(supplied)..' of '..tostring(shippedFacts and shippedFacts.count)..')')
  -- (v45: the same independent literal as above, 4116 English keys.)
  check(keys==4116 and text=='Options' and source=='base' and reason=='missing_candidate' and row.accepted==supplied-1 and row.rejected==1,
   tag..': the loader refused the one overwritten entry, kept the other '..(supplied-1)..' and Options falls back to English ('
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
  Header(nil,tag,'Options',false,true)
 end
 -- F. v11 (Root's disposition, required 5: "Add one deliberately partial
 -- copied-candidate case in this SAME fixture: omit the copied Options entry
 -- through the existing scoped hook"). A partial pack, on purpose: the same
 -- hook hands the real loader the copied frFR WITHOUT its Options entry and
 -- with every other copied entry as shipped. Nothing in it is invalid, so
 -- nothing is rejected: the loader's row is the hook's own count of what it
 -- handed over, one entry fewer than it counted in the shipped table. The
 -- key the pack lacks resolves to the English base as a missing candidate,
 -- and the rest of the panel stays French: in the default font model the
 -- actual Options control shows the whole English word on one line, without
 -- and with the trusted notice; its registered hover names it above the
 -- reviewed frFR group titles; its click opens the reviewed frFR menu; and
 -- Auto keeps its reviewed frFR words (Header asks that of every header).
 -- These are the header, hover and menu checks parts B and D make, with the
 -- same literals, so the fallback itself is shown, not only a count. No
 -- pseudo language: frFR is one of the seven offered languages (Loaded) and
 -- the pack is the shipped one's copy.
 L=Boot('frFR',OMIT)
 do
  local tag='O1 partial'
  local text,source,reason=L.Text(KEY)
  check(text=='Options' and source=='base' and reason=='missing_candidate',
   tag..': with no Options entry in the copied frFR the real loader gives the English base as a missing candidate ('
    ..tostring(text)..', '..tostring(source)..', '..tostring(reason)..')')
  -- The omission is real and is the only difference in size: both numbers
  -- are the hook's own, counted before the loader ran.
  check(type(shippedFacts.supplied)=='number' and shippedFacts.supplied==shippedFacts.count-1,
   'SETUP '..tag..': the hook handed the loader one entry fewer than the shipped frFR holds ('
    ..tostring(shippedFacts.supplied)..' of '..tostring(shippedFacts.count)..')')
  Loaded(L,nil,tag)
  -- The reviewed frFR keeps the game page name My Builds; Auto OFF is translated.
  check(select(2,L.Text('panel.button.my_builds'))=='candidate' and L.Text('panel.button.my_builds')=='My Builds'
   and select(2,L.Text('panel.button.auto_off'))=='candidate' and L.Text('panel.button.auto_off')=='Auto D\195\137SACTIV\195\137',
   tag..': the rest of the copied frFR is still active: My Builds and Auto OFF come from the pack')
  G.UseFont(G.MODELS.default)
  check(Nexus.Panel.OptionsLabel()=='Options' and Nexus.Panel.OptionsText(false)=='Options' and Nexus.Panel.OptionsText(true)=='! Options',
   tag..': OptionsLabel and OptionsText give the English base; only the trusted notice adds "! "')
  check(Nexus.Panel.Render(Model()),'SETUP '..tag..': render')
  check(NexusPanel:IsShown() and NexusPanel._menuBtn:IsShown(),tag..': the Options control is shown on the shown panel')
  Header(nil,tag..', no notice','Options',false,false)
  check(Nexus.Panel.Render(Model({notice=true})),'SETUP '..tag..': render with the notice')
  Header(nil,tag..', trusted notice','Options',false,true)
  check(Nexus.Panel.Render(Model()),'SETUP '..tag..': render')
  local opened=Menu()
  check(opened and opened.anchor==NexusPanel._menuBtn and opened.frame==Nexus.Panel._moreMenu and opened.list[1].isTitle,
   tag..': the click opens the Options menu at the control')
  check(same(TopShape(opened),englishShape),
   tag..': the Options menu offers the same rows as in English: titles, submenus and their sizes, clicks and states, row by row')
  check(same(TopTexts(opened),FRENCH_MENU),
   tag..': every row shows the reviewed frFR words, the Language row naming Fran\195\167ais')
  check(same(TopTitles(opened),LOCALE.frFR.sections),
   tag..': the opened Options menu has exactly the five reviewed frFR group titles its hover lists, in the same order ('
    ..table.concat(TopTitles(opened),' / ')..')')
  check(rawget(NexusDB.settings,'uiLanguage')=='frFR' and Nexus.RecomputeStats().autoEnabled~=true,tag..': the synthetic frFR choice and Auto OFF stay')
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
