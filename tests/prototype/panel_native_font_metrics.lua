-- Main panel text against the client's own font metrics (native report on
-- test.163017: the offer name was 10 units high beside the loading overlay's
-- 16 at the same effective scale). The owned fonts must follow the native
-- reference font object the loading overlay's detail line uses
-- (GameFontHighlightSmall), keep the 10 / 12 / 14 hierarchy, and the header,
-- status card, offer heading, charges, offer rows and body must be laid out
-- for the font they then hold.
--
-- SETUP: real TOC boot (format5_support), synthetic host services and models
-- only. Before any module loads, a synthetic client font model is installed on
-- the harness: CreateFont, font objects with SetFont / GetFont / SetFontObject,
-- FontStrings that inherit the font object they are created with, the native
-- GameFont* objects at a chosen height, and text measured from the resolved
-- font size (0.55 em per visible character, 1.15 em lines: a stated model,
-- not native glyph measurement). UIParent reports effective scale 0.72.
-- Receivers are the real widgets: NexusPanel._offerCards[i].name / .quality /
-- .tag, _rollStatus, _rollRec, _chargesText, the context header lines and the
-- difficulty card's own font strings.
--
-- EXPECT (fails before the correction): at native heights 12, 16 and 20 each
-- role is drawn at the native-derived size and its row is at least that tall,
-- on the panel at the width its text scale gives it and at a 272 px roll box;
-- a native height that changes
-- after start-up is followed, with one font build and a new runtime revision;
-- the difficulty card grows with the font; the charges cell is the layout's
-- cell for the font scale (72 px x the scale) in the room the shown heading
-- leaves, so the compact charges row is whole inline at native 12 and 16
-- beside the same heading form as before (revision 2, R1); a client that
-- reports a one-line width no wider than its set box does not shrink a later
-- tag to an earlier text's width.
-- GUARD (holds before and after): a native height of 10, or under 10, keeps
-- exactly 10 / 12 / 14 and the former geometry, the 72 px charges cell
-- included; the heading form is the one fitted beside the 72 px minimum; a
-- heading that fitted its row still does; a charges row wider than its cell
-- is shortened there and complete on its hover; no game font and no scale is
-- set; nothing depends on a loading frame; cards stay display-only passive
-- drag surfaces in compact rows with their complete line and tag on hover;
-- Details stays collapsed; the header slots and grip are unchanged; repeated
-- renders rebuild nothing.
-- The visual corrections of the main panel.
-- EXPECT, failing at aca67cf4 by design: the panel's width follows the text
-- scale, bounded by the screen at the chosen size (W1; N2 states the rule);
-- a one-line heading, charges row and progress caption is as tall as the
-- line the client measures for it (N2: at native 16 the 17.6-unit secondary
-- text measures 21 units here where its modelled row is 18); an offer row is
-- a grid of the name over its quality with the tag in a status column (the
-- OfferRows helper, N7); the Build and Wishlist captions stand apart from
-- their names, which share one left edge (N2, N7); the title is the 12-unit
-- primary role and the card's Soul Ash line the 11-unit secondary one (N2,
-- T1, N10); only the selected row has an outline (N8). Assertions of the
-- former look that these replace are marked where they stood (the 420-unit
-- width at every text size, the one-line offer row and its literals, the
-- names at x 12, the 15-unit title, a primary Soul Ash line); they are
-- replaced by the new look's own assertions, not relaxed.
-- The setup and completion views' texts are measured and whole, at native 10
-- and 16, with a long note and a long Wishlist name (M1).
-- Count disclosure (C1): the banish / reroll / freeze charges are counts, so
-- they are on the panel only while Details is open. EXPECT, failing at
-- aca67cf4 by design (there the row stood whatever Details was): with Details
-- closed no shown text carries the charges row, its hover is not shown and no
-- cell is kept beside the offer heading, which has its whole row and is
-- worded for it (N2, N7, R1, W1, C1). The checks of the charges cell named
-- above (its layout-derived width, its row's height, the heading beside it,
-- the complete row on its hover) are unchanged and are made where the row
-- stands, with Details open; the assertions that asked for the row on a
-- panel with Details closed are replaced there, each marked where it stood.
-- A scenario that opens Details puts it back (KeepDetails), so N8's
-- "Details stays collapsed" holds for everything after.
-- Native pixels, glyph coverage, real font faces and tooltip drawing: NOT RUN.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('panel_native_font_metrics')

----------------------------------------------------------------------------
-- Synthetic client font model.
----------------------------------------------------------------------------
local PATH='Fonts\\FRIZQT__.TTF'
local CHAR,LINE=0.55,1.15
local RATIOS={GameFontHighlightSmall=1,GameFontNormalSmall=1,GameFontDisableSmall=1,
 GameFontNormal=1.2,GameFontHighlight=1.2,GameFontDisable=1.2,GameFontNormalLarge=1.6}
local NATIVE={height=16,uiScale=0.72,bounded=false,objects={},nativeSets=0}

local function SetNative(height)
 NATIVE.height=height
 for name,ratio in pairs(RATIOS) do
  local font=NATIVE.objects[name]
  font._fontPath,font._fontSize,font._fontFlags=PATH,height*ratio,''
 end
end

local function Install()
 local m=G.RegionMethods()
 STANDARD_TEXT_FONT=PATH
 local function Resolve(region)
  local o,guard=region,0
  while type(o)=='table' and guard<8 do
   if rawget(o,'_fontSize') then return rawget(o,'_fontPath'),rawget(o,'_fontSize'),rawget(o,'_fontFlags') or '' end
   o=rawget(o,'_fontObject');guard=guard+1
  end
  return nil
 end
 m.SetFont=function(self,path,size,flags)
  if rawget(self,'_native') then NATIVE.nativeSets=NATIVE.nativeSets+1 end
  self._fontPath,self._fontSize,self._fontFlags=path,tonumber(size),flags or ''
  return true
 end
 m.SetFontObject=function(self,font)
  if type(font)=='string' then font=_G[font] end
  self._fontObject=font
  -- A font string takes the object's face; a font object keeps what it sets.
  if self.kind~='Font' then self._fontPath,self._fontSize,self._fontFlags=nil,nil,nil end
 end
 m.GetFontObject=function(self) return rawget(self,'_fontObject') end
 m.GetFont=function(self)
  local path,size,flags=Resolve(self)
  if path then return path,size,flags end
  return PATH,12,''
 end
 local create=m.CreateFontString
 m.CreateFontString=function(self,name,layer,template)
  local region=create(self,name)
  if template then m.SetFontObject(region,template) end
  return region
 end
 local setWidth,setSize=m.SetWidth,m.SetSize
 m.SetWidth=function(self,value) self._sized=true;return setWidth(self,value) end
 m.SetSize=function(self,w,h) self._sized=true;return setSize(self,w,h) end
 local function Natural(self)
  local _,size=m.GetFont(self)
  return G.Length(G.Visible(self.text))*CHAR*size
 end
 m.GetStringWidth=function(self)
  local natural=Natural(self)
  -- The bounded model: a one-line string reports no more than a set box.
  if NATIVE.bounded and rawget(self,'_sized') and (tonumber(self.width) or 0)>0 then
   return math.min(natural,self.width)
  end
  return natural
 end
 m.GetTextWidth=function(self) return Natural(self) end
 m.GetStringHeight=function(self)
  local _,size=m.GetFont(self)
  return math.max(1,G.Rows(self.text,tonumber(self.width) or 0,CHAR*size))*math.ceil(size*LINE)
 end
 CreateFont=function(name) return CreateFrame('Font',name) end
 for name in pairs(RATIOS) do
  local font=_G[name] or CreateFrame('Font',name)
  font._native=true
  NATIVE.objects[name]=font
 end
 SetNative(NATIVE.height)
 rawset(UIParent,'GetEffectiveScale',function() return NATIVE.uiScale end)
end

local H=F.Boot(F.Database(),function(h) Install();F.OrbService(h) end)
local R,P,LM=Nexus.Readout,Nexus.Panel,Nexus.LayoutMetrics

local tip={}
GameTooltip.SetOwner=function() tip={} end
GameTooltip.AddLine=function(_,text) tip[#tip+1]=tostring(text) end

----------------------------------------------------------------------------
-- Helpers.
----------------------------------------------------------------------------
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local function Size(region) local _,size=region:GetFont();return size end
local function Near(a,b) return type(a)=='number' and type(b)=='number' and math.abs(a-b)<0.011 end
-- The native scale the owned fonts follow: never under the former sizes.
local function Scale() return math.max(1,math.min(2,NATIVE.height/10)) end
-- Approved readable sizes (T1): the main panel's secondary text is its own
-- 11-unit font ("secondary"), not the shared 10-unit small font, and offer
-- names and the difficulty multiplier are primary text (normal, 12). Each
-- follows the same native reference scale as before.
local function Role(kind) return ({small=10,normal=12,large=14,secondary=11,title=15})[kind]*Scale() end
local function Owned(kind)
 local font=_G[({small='NexusFontSmall',normal='NexusFontNormal',large='NexusFontLarge'})[kind]]
 return font and Size(font) or nil
end
local function Rect(region) local ok,r=pcall(G.Rect,region,NexusPanel);return ok and r or nil end
-- The panel's width for the native scale (main-panel visual correction),
-- as the rule is stated: the 420-unit reference width x the font scale (1 to
-- 2), no wider than the screen leaves at the chosen size (the screen's width
-- less the 24-unit fit margin, over the chosen size; a screen under 640
-- units bounds nothing, as for the fit), and never under 420.
local function WantWidth()
 local want=math.floor(420*Scale()+0.5)
 local screen=tonumber(UIParent:GetWidth())
 if screen and screen>=640 and screen<math.huge then want=math.min(want,math.floor((screen-24)/P.PanelScale())) end
 return math.max(420,want)
end
-- The plan progress caption: the text its fitted hover covers (the region
-- the hover's first anchor names).
local function ProgressCaption()
 local hit=NexusPanel._progressLabelHit
 local anchor=hit and hit.points and hit.points[1] and hit.points[1][2]
 return type(anchor)=='table' and anchor or nil
end
local function Natural(region) return G.Length(G.Visible(region:GetText() or ''))*CHAR*Size(region) end
local function Text(r) return r and G.Text(r) or 'no rect' end
local function Chars(region) return G.Length(G.Visible(region:GetText() or '')) end

-- Revision 2, R1. The charges cell for a shown heading, derived here from
-- the native scale, the heading row (the roll width less 4) and the heading's
-- own line; nothing is read from the panel. 72 px at scale 1; above it 72 px
-- x the scale, in the room the heading leaves after the 4 px gap, and never
-- under 72 px. A fitted offer heading needs its measured line. Any other
-- heading also needs the conservative model (0.70 em of the 10 px small size
-- x the scale, at least 7 px, per visible character), as its row held before.
local function Cell(row,head,fitted)
 local scaled=math.max(72,math.floor(72*Scale()+0.5))
 local need=Natural(head)
 if not fitted then need=math.max(need,Chars(head)*math.max(7.0,0.70*10*Scale())) end
 return math.max(72,math.min(scaled,row-4-math.ceil(need)))
end
-- The form a fitted offer heading must show: the longest of the Readout's
-- forms whose whole line fits the row less the 72 px minimum cell and its
-- gap (the rule before the correction), else the shortest. Returns the index
-- shown and the index that rule gives.
-- Count disclosure (C1): `reserve` is what the row keeps for a charges row,
-- the 76 px of the 72 px minimum cell and its gap unless given; 0 for a
-- heading with no charges row beside it (Details closed), which is fitted
-- to its whole row.
local function Form(head,row,auto,reserve)
 local forms=R.OfferHeadingForms(auto)
 local shown=G.Visible(head:GetText() or '')
 local index,rest
 for i,form in ipairs(forms) do
  local at=shown:find(form,1,true)
  if at and (not index or #form>#forms[index]) then index,rest=i,G.Length(shown)-G.Length(form) end
 end
 if not index then return nil,nil end
 local want=#forms
 for i,form in ipairs(forms) do
  if (G.Length(form)+rest)*CHAR*Size(head)<=row-(reserve or 76) then want=i;break end
 end
 return index,want
end

local CHARGES={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true}
local SERVER={tier='HC3',ash='12,345',gain='+12.5%',intensity=40,intensityMax=100,intensityThresholds={20,40,60,80}}
local LONG={
 {text='[Guaranteed offer] Resonance of the Unbroken Covenant (Uncommon) wanted',highlight=true},
 {text='Hollow Bell (Rare) wanted'},
 {text='[Guaranteed offer] Ashen Tithe of the Wandering Choir (Uncommon)'},
}
local function Model(o)
 o=o or {}
 return {status='ready',level=40,auto=o.auto,paused=o.paused,cards=o.cards or {},recommendation=o.recommendation or '',
  charges=o.charges,serverStatus=o.serverStatus,character='SyntheticHero',
  progress={wishlistName='Synthetic Play plan',total=6,owned=1,missing={},shed={},toLock={},unknownTomes={},
   activeSlot=o.slot}}
end
local function Play(cards)
 return Model({auto=false,cards=cards or LONG,recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2})
end
-- Another layout first, so the target is applied in full.
local function Render(model)
 P.Render(Model({auto=false}))
 return P.Render(model)
end
-- Count disclosure (C1). The banish, reroll and freeze charges are counts,
-- and counts are on the panel only while Details is open: with Details
-- closed there is no charges row, no hover and no cell beside the offer
-- heading, which has its whole row; with Details open the row stands in its
-- cell as it always did. Details is the panel's own memory-only state
-- (P._playDetails). A scenario that opens it runs through KeepDetails, which
-- puts it back as it was, also when the scenario raises, so no later
-- scenario runs with Details left open (N8 states that it is collapsed).
local function KeepDetails(fn,...)
 local was=P._playDetails
 local ok,err=pcall(fn,...)
 P._playDetails=was
 if not ok then error(err,0) end
end
-- How many shown texts of the panel carry the compact charges row of this
-- fixture's charge facts (the Readout's own line, colour codes aside).
local function ChargeRows()
 local line=G.Visible(R.ChargesLine(CHARGES) or '')
 local n=0
 for _,region in ipairs(G.Shown(NexusPanel)) do
  if region.kind=='FontString' and line~='' and G.Visible(region:GetText() or ''):find(line,1,true) then n=n+1 end
 end
 return n
end
-- The panel with Details closed: no shown text carries the charges row, its
-- own text and its hover are not shown, and the offer heading is `row` wide,
-- its whole row, so no cell is kept beside it. Returns that and what it saw.
local function NoCharges(row)
 local charges,hover,head=NexusPanel._chargesText,NexusPanel._chargesHover,NexusPanel._rollStatus
 local rows=ChargeRows()
 return P._playDetails~=true and rows==0 and not charges:IsShown() and hover~=nil and not hover:IsShown()
  and head:IsShown() and head:GetWidth()==row,
  rows..' shown text(s) with the charges row; its own text shown: '..tostring(charges:IsShown())..'; its hover shown: '
  ..tostring(hover~=nil and hover:IsShown())..'; heading '..tostring(head:GetWidth())..' in a row of '..tostring(row)
end

-- The difficulty card: the panel child that owns the intensity bar; its font
-- strings in creation order are the tier, the Soul Ash line and the multiplier.
local function StatusCard()
 for _,child in ipairs(NexusPanel.children or {}) do
  if type(child)=='table' and rawget(child,'intensityBar') and rawget(child,'PositionIntensityTicks') then
   local strings={}
   for _,region in ipairs(child.regions or {}) do
    if region.kind=='FontString' then strings[#strings+1]=region end
   end
   return child,strings[1],strings[2],strings[3]
  end
 end
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
C.setup(type(CreateFont)=='function' and Near(Size(GameFontHighlightSmall),16),'fixture: the synthetic native small font is 16 high')
C.setup(G.Visible(R.ChargesLine(CHARGES) or '')~='','fixture: the Readout words this fixture\'s charge facts as a charges row',
 tostring(R.ChargesLine(CHARGES)))
Nexus.DisableOrdinaryAutomation()
P.Show()
local baselineEffects=Effects()
local panelScale=NexusPanel:GetScale()

----------------------------------------------------------------------------
-- Offer rows of the shown cards against `area` (a rect) at role size `small`.
----------------------------------------------------------------------------
local function OfferRows(tag,area,small,lines,kind)
 local cards=NexusPanel._offerCards
 local fonts,rows,inside,ordered,apart,whole,sixth,hover=true,true,true,true,true,true,true,true
 local notes,rects={}, {}
 for i=1,3 do
  local card=cards[i]
  local cr=Rect(card);rects[i]=cr
  if not (card:IsShown() and cr and G.Inside(cr,area,0.01)) then inside=false;notes[#notes+1]='card'..i..' '..Text(cr) end
  if card:GetHeight()<small-0.01 then rows=false;notes[#notes+1]='card'..i..' h='..tostring(card:GetHeight()) end
  local edge
  for _,key in ipairs({'name','quality','tag'}) do
   local text=card[key]
   -- The name is primary text (normal); its quality and tag are secondary.
   local want=key=='name' and Role('normal') or small
   if not Near(Size(text),want) then fonts=false;notes[#notes+1]=i..'.'..key..' font='..tostring(Size(text)) end
   if (text:GetText() or '')~='' then
    local tr=Rect(text)
    if text:GetHeight()<want-0.01 then rows=false end
    if not (tr and G.Inside(tr,cr,0.01)) then inside=false;notes[#notes+1]=i..'.'..key..' '..Text(tr) end
    -- The right end of the row's texts (the tag's, or the name column's
    -- when the row has no tag).
    if tr then edge=math.max(edge or tr[3],tr[3]) end
   end
  end
  local nr=Rect(card.name)
  -- The grid (main-panel visual correction): the quality stands under the
  -- name in the name's own column, and a tag in the status column right of
  -- that column. The order this helper held before was one line (name, then
  -- quality, then tag, left to right); that one-line order is intentionally
  -- gone, so it is replaced by the grid's order here.
  local qr,gr=Rect(card.quality),Rect(card.tag)
  if not (nr and qr and math.abs(qr[1]-nr[1])<=0.01 and qr[2]>=nr[4]-0.01) then
   ordered=false;notes[#notes+1]=i..' quality '..Text(qr)..' under name '..Text(nr)
  end
  if (card.tag:GetText() or '')~='' and not (nr and qr and gr and gr[1]>=nr[3]-0.01 and gr[1]>=qr[3]-0.01) then
   ordered=false;notes[#notes+1]=i..' tag '..Text(gr)..' right of '..Text(nr)
  end
  if nr and cr then
   -- The room the text and status columns share: from the name's left, after the icon square and its gap, to the last text's right.
   local rest=(edge or cr[3])-nr[1]
   local tagText=card.tag:GetText() or ''
   if tagText~='' and Natural(card.tag)<=math.floor(rest/2) and card.tag:GetWidth()<math.ceil(Natural(card.tag))-0.01 then
    whole=false;notes[#notes+1]=i..'.tag box='..tostring(card.tag:GetWidth())..' natural='..tostring(Natural(card.tag))
   end
   -- A name shorter than a sixth is whole and gives its idle room to the status words (offer-row spacing).
   if card.name:GetWidth()<math.min(math.floor(rest/6),math.ceil(Natural(card.name)))-0.01 then sixth=false end
  end
  local enter=card:GetScript('OnEnter')
  tip={}
  if enter then enter(card) end
  local full=R.CardLineShown(lines[i].text,lines[i].facts)
  if not (tip[1]==full and card._nexusFull==full and (card._nexusTag==nil or card._nexusTag=='' or tip[2]==card._nexusTag)) then
   hover=false;notes[#notes+1]='hover'..i..'='..tostring(tip[1])
  end
  if card._nexusLayout~='rows' then ordered=false end
 end
 for i=1,3 do for j=i+1,3 do
  if not (rects[i] and rects[j] and G.Apart(rects[i],rects[j])) then apart=false end
 end end
 local detail=table.concat(notes,'; ')
 -- How much of each text its row shows (box / natural width in the model).
 local shares={}
 for i=1,3 do
  local parts={}
  for _,key in ipairs({'name','quality','tag'}) do
   local text=cards[i][key]
   if (text:GetText() or '')~='' then parts[#parts+1]=key..' '..tostring(text:GetWidth())..'/'..string.format('%.0f',Natural(text)) end
  end
  shares[#shares+1]=i..': '..table.concat(parts,', ')
 end
 print('OBSERVED',tag,'offer rows '..table.concat(shares,' | '))
 kind(fonts,tag..': every offer name is drawn at the native-derived primary size and its quality and tag at the secondary size '..small,detail)
 kind(rows,tag..': every offer row and text box is at least that tall',detail)
 C.guard(inside and apart,tag..': the rows are apart and inside the roll area, and their texts inside them',detail)
 -- EXPECT: fails at aca67cf4, where a row was one line of name, quality, tag.
 C.expect(ordered,tag..': each row is the grid: the quality under its name, the tag in the status column to their right',detail)
 C.guard(whole,tag..': a tag no wider than half the row is whole',detail)
 C.guard(sixth,tag..': the name keeps at least a sixth of the row, or its whole text when that is shorter',detail)
 C.guard(hover,tag..': each card\'s hover gives its complete line and tag',detail)
end

----------------------------------------------------------------------------
-- N1: the reported receiver, at the reported metrics.
----------------------------------------------------------------------------
C.scenario('N1 the offer name is drawn at the loading overlay\'s native font height',function()
 C.setup(Render(Play())==true and NexusPanel:IsShown(),'N1: fixture: the Play panel renders an offer')
 local name=NexusPanel._offerCards[1].name
 local receiver,reference=Size(name),Size(GameFontHighlightSmall)
 print('OBSERVED','N1 receiver='..tostring(receiver),'reference='..tostring(reference),
  'ratio='..string.format('%.4f',receiver/reference),'uiScale='..tostring(NATIVE.uiScale))
 -- The name is primary text: 12 units where the native small reference is
 -- 10, so 1.2 x the reference height (never smaller than the reference).
 C.expect(Near(receiver,reference*1.2),'N1: NexusPanel._offerCards[1].name is primary text on the native reference (ratio 1.2)',
  tostring(receiver)..'/'..tostring(reference))
 C.expect(Near(Owned('small'),16) and Near(Owned('normal'),19.2) and Near(Owned('large'),22.4),
  'N1: the owned fonts keep the 10 / 12 / 14 hierarchy on the native 16',
  tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large')))
 local fontScale=LM.RuntimeMetrics()
 C.expect(Near(fontScale,1.6),'N1: the runtime font scale is the native scale, not the owned size against itself',fontScale)
end)

----------------------------------------------------------------------------
-- N2: every role at native heights 12, 16 and 20 on the panel, at the width
-- its text scale gives it (504, 672 and 840 units on a screen that has the
-- room: W1).
----------------------------------------------------------------------------
local function Roles(height)
 local tag='N2 native '..height
 local wasDetails=P._playDetails
 SetNative(height)
 C.setup(Render(Play())==true,tag..': fixture: the Play panel renders with charge facts, the difficulty card and long names')
 local layout=NexusPanel._responsiveLayout
 if not C.setup(type(layout)=='table' and layout.boxes and layout.boxes.roll and layout.boxes.status and layout.boxes.header,
  tag..': fixture: the responsive layout holds the header, status and roll boxes') then return end
 local small,normal=Role('secondary'),Role('normal')
 local fontScale=LM.RuntimeMetrics()
 print('OBSERVED',tag,'owned='..tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large')),
  'fontScale='..tostring(fontScale),'rows='..layout.small..'/'..layout.normal..'/'..layout.large,
  'panel='..NexusPanel:GetWidth()..'x'..NexusPanel:GetHeight())
 C.expect(Near(fontScale,Scale()) and layout.small==math.ceil(11*Scale()-1e-9) and layout.small>=small,
  tag..': the layout rows follow the native font scale',tostring(fontScale)..' small row '..tostring(layout.small))
 -- Main-panel visual correction: the width follows the text scale. The
 -- guard that stood here held the panel at 420 units at every native height;
 -- that fixed width is what crowded the larger text, so it is replaced by
 -- the rule (WantWidth above; W1 pins its numbers on stated screens).
 local wantWidth=WantWidth()
 C.expect(wantWidth>420 and NexusPanel:GetWidth()==wantWidth and layout.width==wantWidth,
  tag..': the panel is as wide as its text scale asks ('..wantWidth..' units), not the reference 420',NexusPanel:GetWidth())
 C.guard(NexusPanel:GetHeight()==layout.height,tag..': the panel keeps the layout height')

 -- Offer rows, heading and body.
 local area=Rect(NexusPanel._rollArea)
 OfferRows(tag,area,small,LONG,C.expect)
 local head,body=NexusPanel._rollStatus,NexusPanel._rollRec
 C.expect(Near(Size(head),small) and head:GetHeight()>=small-0.01 and Near(Size(body),small),
  tag..': the offer heading and the recommendation body are drawn at the small size in rows that tall',
  tostring(Size(head))..' in '..tostring(head:GetHeight())..'; body '..tostring(Size(body)))
 local bodyRect=Rect(body)
 C.guard(bodyRect and G.Inside(bodyRect,area,0.01),tag..': the body stays inside the roll area',Text(bodyRect))
 -- Font height (main-panel visual correction): a row that holds one line
 -- is as tall as the line the client measures, not only as its modelled
 -- row. At native 16 the 17.6-unit secondary text measures 21 units in this
 -- model where the modelled small row is 18 (16 for 14 at native 12, 26 for
 -- 22 at native 20), so before the correction the heading's and the progress
 -- caption's boxes were lower than their own line.
 local caption=ProgressCaption()
 C.expect(head:GetHeight()+0.5>=head:GetStringHeight(),tag..': the offer heading\'s row is as tall as its measured line',
  tostring(head:GetHeight())..' for '..tostring(head:GetStringHeight()))
 C.expect(caption~=nil and caption:IsShown() and Near(Size(caption),small) and caption:GetHeight()+0.5>=caption:GetStringHeight(),
  tag..': the progress caption\'s row is as tall as its measured line',
  caption and (tostring(caption:GetHeight())..' for '..tostring(caption:GetStringHeight())) or 'no caption')

 -- Count disclosure (C1). The charges are counts, so this panel, whose
 -- Details is closed, has no charges row: no shown text carries it, its
 -- hover is not shown and no cell is kept beside the heading, which is as
 -- wide as its whole row (the roll area less its two 2-unit insets; Auto is
 -- OFF here, so no disclosure shares the row). At aca67cf4 the row stood
 -- here whatever Details was, and the heading ended 4 units before its cell.
 -- The checks of that row and its cell below are unchanged; they are made
 -- with Details open, where the row stands, and Details is then closed
 -- again for the header and the difficulty card.
 local closedHead,closedRoll,closedPanel=head:GetHeight(),layout.boxes.roll.h,NexusPanel:GetHeight()
 local none,noneDetail=NoCharges((area[3]-area[1])-4)
 C.expect(none,tag..': with Details closed there is no charges row, hover or cell: the heading has its whole row',noneDetail)
 P._playDetails=true
 C.setup(Render(Play())==true and P._playDetails==true,tag..': fixture: the same panel with Details open')
 layout=NexusPanel._responsiveLayout
 area=Rect(NexusPanel._rollArea)

 -- Charges: a native-font text in the heading row.
 local charges=NexusPanel._chargesText
 local chargesRect,headRect=Rect(charges),Rect(head)
 print('OBSERVED',tag,'charges="'..tostring(charges:GetText())..'" font='..tostring(Size(charges)),
  'cell='..tostring(charges:GetWidth())..'x'..tostring(charges:GetHeight()),'natural='..string.format('%.1f',Natural(charges)))
 C.guard(charges:IsShown() and Near(Size(charges),Role('secondary')),tag..': the charges are already drawn in the client\'s own small font',Size(charges))
 -- Revision 2, R1: the cell is the layout's cell for the font scale, in the
 -- room the fitted heading leaves; the heading keeps the rest of the row
 -- less the cell and its 4 px gap. The heading form is still the one fitted
 -- beside the 72 px minimum. A row wider than its cell wraps there in full
 -- (approved panel cleanup: nothing on the main panel is shortened) and is
 -- still complete on its hover.
 local row=(area[3]-area[1])-4
 local cell=Cell(row,head,true)
 local shownForm,wantForm=Form(head,row,false)
 local cellDetail='cell '..tostring(charges:GetWidth())..' want '..cell..'; heading box '..tostring(head:GetWidth())..' want '..(row-cell-4)
  ..'; charges natural '..string.format('%.1f',Natural(charges))..'; heading natural '..string.format('%.1f',Natural(head))
 print('OBSERVED',tag,'heading natural='..string.format('%.1f',Natural(head)),'box='..tostring(head:GetWidth()),
  'form='..tostring(shownForm)..'/'..tostring(wantForm),'derived cell='..cell)
 C.expect(charges:GetHeight()>=small-0.01 and charges:GetHeight()+0.5>=charges:GetStringHeight(),
  tag..': the charges cell is as tall as the font it holds and as its measured lines',
  tostring(charges:GetHeight())..' for '..tostring(charges:GetStringHeight()))
 C.guard(shownForm~=nil and shownForm==wantForm,tag..': the heading shows the form fitted beside the 72 px minimum cell, as before',
  tostring(shownForm)..'/'..tostring(wantForm)..' '..G.Visible(head:GetText() or ''))
 -- Where the derived cell is wider than 72 px this fails before revision 2.
 ;(cell>72 and C.expect or C.guard)(charges:GetWidth()==cell and head:GetWidth()==row-cell-4,
  tag..': the charges cell is the layout-derived '..cell..' px and the heading keeps the rest of the row less the cell and its gap',cellDetail)
 if Natural(charges)<=cell then
  C.expect(Natural(charges)<=charges:GetWidth()+0.01,tag..': the compact charges row is whole inline in its cell',cellDetail)
 else
  -- The top of the range: no room for the row on one line beside the
  -- heading. (The charges are the panel's 11-unit secondary text now, so a
  -- row can also be wider than a derived cell above the 72 px minimum.)
  -- Approved panel cleanup: the row keeps that cell and wraps in it, in a
  -- box as tall as its lines need; it is not shortened. This is behaviour
  -- of the cleanup (the row was one shortened line before), so it is an
  -- expectation; the cell's width is checked above.
  C.expect(charges:GetWidth()==cell and Natural(charges)>charges:GetWidth()
   and charges:GetHeight()+0.5>=charges:GetStringHeight(),
   tag..': with no room on one line beside the heading the charges row wraps whole in its derived cell',
   cellDetail..'; box '..tostring(charges:GetHeight())..' for text '..tostring(charges:GetStringHeight()))
 end
 if Natural(head)<=row-76 then
  C.guard(Natural(head)<=head:GetWidth()+0.01,tag..': a heading that fitted beside the 72 px minimum is still whole beside the wider cell',cellDetail)
 else
  print('OBSERVED',tag,'LIMIT: the shortest heading form is wider than its row at this height (shortened by the client, as before)')
 end
 C.guard(charges:GetWidth()>=72 and Near(Size(charges),Role('secondary')),tag..': the cell is never under 72 px and the charges keep their font (no shrink)',cellDetail)
 C.guard(chargesRect and headRect and headRect[3]<=chargesRect[1]+0.01 and G.Inside(chargesRect,area,0.01),
  tag..': the heading ends before the charges cell, inside the roll area',Text(headRect)..' '..Text(chargesRect))
 local legend=NexusPanel._chargesHover and NexusPanel._chargesHover:GetScript('OnEnter')
 tip={}
 if legend then legend(NexusPanel._chargesHover) end
 C.guard(tip[2]==charges:GetText(),tag..': the charges hover still gives the complete row',tostring(tip[2]))
 -- Count disclosure (C1): the row is on the panel a single time, with its
 -- hover, and only while Details is open. Closing Details takes the row,
 -- the hover and the cell away again and leaves the heading row, the offer
 -- block and the panel exactly as they were closed.
 C.guard(ChargeRows()==1 and NexusPanel._chargesHover:IsShown(),tag..': with Details open the charges row is on the panel once, with its hover',
  ChargeRows())
 P._playDetails=wasDetails
 C.setup(Render(Play())==true and P._playDetails~=true,tag..': fixture: Details closed again')
 layout=NexusPanel._responsiveLayout
 area=Rect(NexusPanel._rollArea)
 local again,againDetail=NoCharges((area[3]-area[1])-4)
 C.expect(again and head:GetHeight()==closedHead and layout.boxes.roll.h==closedRoll and NexusPanel:GetHeight()==closedPanel,
  tag..': closing Details takes the charges row, its hover and its cell away again: the heading row, the offer block and the panel are as they were',
  againDetail..'; heading row '..tostring(head:GetHeight())..' / '..tostring(closedHead)..', offer block '..tostring(layout.boxes.roll.h)
  ..' / '..tostring(closedRoll)..', panel '..tostring(NexusPanel:GetHeight())..' / '..tostring(closedPanel))

 -- Header lines (owned normal font).
 local lines={NexusPanel._contextTitle,NexusPanel._contextBuild,NexusPanel._contextWishlist}
 local headerFonts,headerRows,headerApart,headerInside=true,true,true,true
 local headerBox=layout.boxes.header
 local headerRect={headerBox.x,headerBox.y,headerBox.x+headerBox.w,headerBox.y+headerBox.h}
 local rects,notes={}, {}
 for i,line in ipairs(lines) do
  rects[i]=Rect(line)
  notes[#notes+1]=Text(rects[i])..' font='..tostring(Size(line))
  -- Main-panel visual correction: the title is primary text too (the
  -- 12-unit normal role, a quieter existing role); its own 15-unit role,
  -- which this check asked for, is intentionally gone. The Build and
  -- Wishlist lines stay primary text.
  if not Near(Size(line),normal) then headerFonts=false end
  -- The title keeps line 1's literal 20 px row (checked below); the Build
  -- and Wishlist rows follow their font.
  if i>1 and line:GetHeight()<normal-0.01 then headerRows=false end
  if not (rects[i] and rects[i][2]>=headerRect[2]-0.01 and rects[i][4]<=headerRect[4]+0.01) then headerInside=false end
  if i>1 and not (rects[i] and rects[i-1] and rects[i][2]>=rects[i-1][4]-0.01) then headerApart=false end
 end
 local headerDetail=table.concat(notes,' | ')
 print('OBSERVED',tag,'header '..headerDetail,'box='..Text(headerRect))
 C.expect(headerFonts,tag..': the title, Build and Wishlist lines are drawn at the native-derived normal size '..normal,headerDetail)
 ;(height>=20 and C.expect or C.guard)(headerRows,tag..': the Build and Wishlist rows are at least as tall as their font',headerDetail)
 C.guard(rects[1] and rects[1][1]==36 and rects[1][2]==8,tag..': the title stays at 36, 8 on header line 1',Text(rects[1]))
 -- Independent Spec review, required finding 2 (no fixed-height text
 -- container): the title's box was a literal 20 px whatever its font needed
 -- (18, 24 and 30 px fonts here). It is the 20 px line while the text needs
 -- no more, and the text's own measured height when it needs more; the rows
 -- under it start lower by the difference (N10).
 local titleNeeds=math.max(20,math.ceil(lines[1]:GetStringHeight()))
 ;(titleNeeds>20 and C.expect or C.guard)(lines[1]:GetHeight()==titleNeeds,
  tag..': the title\'s box is as tall as its text needs, at least the 20 px line',tostring(lines[1]:GetHeight())..' / '..tostring(titleNeeds))
 C.guard(headerApart and headerInside,tag..': the header lines are apart and inside the header the layout reserves',headerDetail)
 local switch,change=Rect(NexusPanel._switchBtn),Rect(NexusPanel._contextChange)
 C.guard(switch and change and G.Apart(switch,change) and rects[2] and rects[3]
  and switch[2]<=rects[2][2] and switch[4]>=rects[2][2] and change[2]<=rects[3][2] and change[4]>=rects[3][2],
  tag..': My Builds and Change stay beside their own lines, apart',Text(switch)..' '..Text(change))
 -- The Build and Wishlist captions (main-panel visual correction): each
 -- line's own label stands in a column of its own at the header's left, in
 -- the secondary role; the two names start at one left edge after that
 -- column and end before their buttons. The label is the reviewed line's own
 -- words: the line worded here with a stand-in name begins with it.
 local caps={NexusPanel._contextBuildCaption,NexusPanel._contextWishlistCaption}
 local worded={Nexus.Localization.Format('panel.label.context_build',{build='Zed'}),
  Nexus.Localization.Format('panel.label.context_wishlist',{wishlist='Zed'})}
 if C.setup(type(worded[1])=='string' and worded[1]:sub(-3)=='Zed' and #worded[1]>4
  and type(worded[2])=='string' and worded[2]:sub(-3)=='Zed' and #worded[2]>4,
  tag..': fixture: the Build and Wishlist lines are a label followed by the name',tostring(worded[1])..' | '..tostring(worded[2])) then
  local capOk,capNotes=caps[1]~=nil and caps[2]~=nil,{}
  for i=1,2 do
   local cap,name=caps[i],lines[i+1]
   local cr2=cap and Rect(cap) or nil
   local label=worded[i]:sub(1,-4):gsub('%s+$','')
   capNotes[#capNotes+1]=tostring(cap and cap:GetText())..' '..Text(cr2)..' font='..tostring(cap and Size(cap))
   if not (cap and cap:IsShown() and G.Visible(cap:GetText() or '')==label and Near(Size(cap),small)
    and cr2 and cr2[1]==12 and math.abs(cr2[2]-rects[i+1][2])<=0.01 and cr2[3]<=rects[i+1][1]+0.01
    and cap:GetWidth()+0.5>=cap:GetStringWidth()
    and G.Visible(name:GetText() or '')~='' and G.Visible(name:GetText() or ''):sub(1,#label)~=label) then capOk=false end
  end
  C.expect(capOk and rects[2] and rects[3] and rects[2][1]==rects[3][1] and rects[2][1]>12
   and switch and rects[2][3]<=switch[1]+0.01 and change and rects[3][3]<=change[1]+0.01,
   tag..': the Build and Wishlist captions stand apart, whole, in the secondary role; the names share one left edge after them',
   table.concat(capNotes,' | ')..' names at '..tostring(rects[2] and rects[2][1])..' / '..tostring(rects[3] and rects[3][1]))
 end

 -- Difficulty card (owned normal and small fonts in its own boxes).
 local card,tier,ash,gain=StatusCard()
 if not C.setup(card and tier and ash and gain and card:IsShown(),tag..': fixture: the difficulty card and its three texts are found') then return end
 local cardRect,tierRect,ashRect,gainRect=Rect(card),Rect(tier),Rect(ash),Rect(gain)
 local statusDetail='card '..Text(cardRect)..' tier '..Text(tierRect)..' font='..tostring(Size(tier))
  ..' ash '..Text(ashRect)..' font='..tostring(Size(ash))..' gain '..Text(gainRect)..' font='..tostring(Size(gain))
 print('OBSERVED',tag,statusDetail)
 -- Main-panel visual correction (the Compact A card as approved: tier and
 -- multiplier primary, Soul Ash under them secondary): the Soul Ash line is
 -- the 11-unit secondary role. This check asked for the primary size on all
 -- three; for Soul Ash that is intentionally gone. The tier and the
 -- multiplier start at one top.
 C.expect(Near(Size(tier),normal) and Near(Size(ash),small) and Near(Size(gain),normal),
  tag..': the difficulty card\'s tier and multiplier use the normal (primary) size and its Soul Ash line the secondary size',statusDetail)
 ;(height>=16 and C.expect or C.guard)(tier:GetHeight()>=normal-0.01 and ash:GetHeight()>=small-0.01 and gain:GetHeight()>=normal-0.01,
  tag..': each difficulty card text box is at least as tall as its font',statusDetail)
 C.guard(tierRect and gainRect and math.abs(tierRect[2]-gainRect[2])<=0.01,tag..': the tier and the multiplier start at one top',statusDetail)
 -- Whole before too (a 10 / 12 px text in a 10 / 12 px box); it must stay whole.
 C.guard(tier:GetWidth()>=Natural(tier)-0.01 and ash:GetWidth()>=Natural(ash)-0.01 and gain:GetWidth()>=Natural(gain)-0.01,
  tag..': the tier, Soul Ash and multiplier are whole in their boxes',
  string.format('%.1f/%s %.1f/%s %.1f/%s',Natural(tier),tostring(tier:GetWidth()),Natural(ash),tostring(ash:GetWidth()),Natural(gain),tostring(gain:GetWidth())))
 local bar=Rect(card.intensityBar)
 C.guard(cardRect and tierRect and ashRect and gainRect and G.Inside(tierRect,cardRect,0.01) and G.Inside(ashRect,cardRect,0.01)
  and G.Inside(gainRect,cardRect,0.01) and ashRect[2]>=tierRect[4]-0.01 and G.Apart(tierRect,gainRect)
  and bar and bar[2]>=ashRect[4]-0.01 and card:GetHeight()==layout.boxes.status.h,
  tag..': the card\'s texts stay inside it, on separate lines, above the Intensity bar',statusDetail..' bar '..Text(bar))

 -- Nothing global is touched.
 local nativeOk=true
 for name,ratio in pairs(RATIOS) do if not Near(Size(NATIVE.objects[name]),height*ratio) then nativeOk=false end end
 C.guard(nativeOk and NATIVE.nativeSets==0,tag..': no game font object is set',NATIVE.nativeSets)
 C.guard(NexusPanel:GetScale()==panelScale and (UIParent:GetScale() or 1)==1,tag..': the panel scale and the UI scale are unchanged',NexusPanel:GetScale())
end
for _,height in ipairs({12,16,20}) do
 C.scenario('N2 roles at native height '..height,function() KeepDetails(Roles,height) end)
end

----------------------------------------------------------------------------
-- N3: a narrow roll box (272 px panel width) at the real receiver functions.
----------------------------------------------------------------------------
local function Narrow(height)
 local tag='N3 native '..height..' at 272 px'
 SetNative(height)
 C.setup(Render(Play())==true,tag..': fixture: the cards exist and hold the long offer')
 local fontScale,uiScale,revision=LM.RuntimeMetrics()
 local layout=LM.Panel({width=272,fontScale=fontScale,uiScale=uiScale,revision=revision,activeRoll=true,
  statusVisible=true,cardRows=true})
 local box=layout.boxes.roll
 local area=NexusPanel._rollArea
 -- The roll area takes the narrow box (the panel itself never asks for one
 -- this narrow: it is 420 units wide at least).
 area:ClearAllPoints();area:SetPoint('TOPLEFT',NexusPanel,'TOPLEFT',box.x,-box.y);area:SetSize(box.w,box.h)
 local lines={}
 for i,card in ipairs(LONG) do lines[i]=card.text end
 C.setup(P.RenderOfferCards(lines,R.MarkedCard(LONG),false,true,nil,nil)==true and P.PlaceOfferCards(layout,box,2)=='rows',
  tag..': fixture: the real card render and placement ran at the narrow box')
 local small=Role('secondary')
 print('OBSERVED',tag,'roll='..box.w..'x'..box.h,'row='..layout.small,'name box='..tostring(NexusPanel._offerCards[1].name:GetWidth()),
  'name natural='..string.format('%.1f',Natural(NexusPanel._offerCards[1].name)))
 OfferRows(tag,Rect(area),small,LONG,C.expect)
 local name=NexusPanel._offerCards[1].name
 C.guard(name:GetStringWidth()>name:GetWidth() and tostring(NexusPanel._offerCards[1]._nexusFull):find('Resonance of the Unbroken Covenant',1,true)~=nil,
  tag..': the long name is wider than one line of its column (it wraps there) and complete on the card hover')
 C.expect(Near(Size(name),Role('normal')) and Near(Size(NexusPanel._offerCards[1].tag),small),
  tag..': the shortened name keeps the full native-derived primary size (no per-text shrink)',Size(name))
 -- Revision 2, R1 at the narrow box, through the real heading and cell
 -- functions (the panel itself lays out at 420 units or wider): the Play
 -- fixture's slot heading, then a preview heading with its shorter forms.
 -- Before revision 2 the panel has no cell resolver: its cell is 72 px.
 -- Count disclosure (C1): the heading function reserves the cell whenever
 -- the render gives it a charges line, which a render now does only with
 -- Details open. The panel rendered above has Details closed and holds no
 -- row to hand on (the row it showed at aca67cf4 was read here), so the line
 -- given is that same row from its source: the Readout's wording of this
 -- fixture's charge facts.
 local head,charges=NexusPanel._rollStatus,NexusPanel._chargesText
 local chargeLine=R.ChargesLine(CHARGES)
 local chargeNatural=G.Length(G.Visible(chargeLine))*CHAR*Size(charges)
 local row=box.w-4
 for _,case in ipairs({{'slot heading',false,2},{'preview heading',nil,0}}) do
  P.SetOfferHeading(head,{auto=case[2],_nexusChargeLine=chargeLine},case[3],layout)
  local cell=Cell(row,head,true)
  local actual=type(P.ChargesCell)=='function' and P.ChargesCell(layout,head) or 72
  local shownForm,wantForm=Form(head,row,case[2])
  local detail='cell '..tostring(actual)..' want '..cell..'; row '..row..'; heading "'..G.Visible(head:GetText() or '')..'" natural '
   ..string.format('%.1f',Natural(head))..'; charges natural '..string.format('%.1f',chargeNatural)
  print('OBSERVED',tag,case[1],detail,'form='..tostring(shownForm)..'/'..tostring(wantForm))
  C.guard(shownForm~=nil and shownForm==wantForm,tag..', '..case[1]..': the form fitted beside the 72 px minimum cell is shown, as before',detail)
  ;(cell>72 and C.expect or C.guard)(actual==cell,tag..', '..case[1]..': the charges cell is the layout-derived '..cell..' px',detail)
  C.guard(actual>=72 and actual+4<=row and (Natural(head)>row-76 or Natural(head)<=row-actual-4+0.01),
   tag..', '..case[1]..': the cell is never under 72 px, stays in the row and leaves a fitted heading whole',detail)
  -- Count disclosure (C1): with Details closed the render gives no charges
  -- line, and the heading is worded for its whole row: the longest form
  -- whose line fits the row itself, never a shorter one than beside the
  -- cell. GUARD: the heading function already fitted a heading without a
  -- charges line to the whole row; what is new is that a render with
  -- Details closed gives it none (N2, N7, R1, W1, and C1 where the two
  -- forms differ on the panel itself).
  P.SetOfferHeading(head,{auto=case[2],_nexusChargeLine=''},case[3],layout)
  local wholeForm,wholeWant=Form(head,row,case[2],0)
  C.guard(wholeForm~=nil and shownForm~=nil and wholeForm==wholeWant and wholeForm<=shownForm,
   tag..', '..case[1]..': with no charges line the heading is the form fitted to its whole row, never shorter than beside the cell',
   'form '..tostring(wholeForm)..' want '..tostring(wholeWant)..'; beside the cell '..tostring(shownForm)..'; "'..G.Visible(head:GetText() or '')
   ..'" natural '..string.format('%.1f',Natural(head))..' in a row of '..row)
 end
end
for _,height in ipairs({12,16,20}) do
 C.scenario('N3 narrow roll box at native height '..height,function() Narrow(height) end)
end

----------------------------------------------------------------------------
-- N4: the native height changes after start-up; caches follow.
----------------------------------------------------------------------------
C.scenario('N4 a native height that changes after start-up is followed, without a loading frame',function()
 SetNative(16)
 C.setup(Render(Play())==true,'N4: fixture: the Play panel at native 16')
 local _,_,revision=LM.RuntimeMetrics()
 local builds=LM.Stats().fontBuilds
 local computations=LM.Stats().computations
 for _=1,3 do P.Render(Play()) end
 local _,_,same=LM.RuntimeMetrics()
 C.guard(LM.Stats().fontBuilds==builds and same==revision,'N4: repeated renders build no font and advance no revision',
  tostring(LM.Stats().fontBuilds)..'/'..tostring(builds))
 C.guard(LM.Stats().computations==computations,'N4: repeated renders reuse the cached layout',LM.Stats().computations-computations)
 local small16,height16=NexusPanel._responsiveLayout.small,NexusPanel:GetHeight()
 -- No loading frame at all while the native metrics move.
 local loading=NexusLoadingStatusFrame
 NexusLoadingStatusFrame=nil
 SetNative(20)
 C.setup(P.Render(Play())==true,'N4: fixture: the same model renders after the native change')
 local name=NexusPanel._offerCards[1].name
 local _,_,after=LM.RuntimeMetrics()
 print('OBSERVED','N4 16->20 receiver='..tostring(Size(name)),'builds='..tostring(LM.Stats().fontBuilds-builds),
  'revision '..tostring(revision)..'->'..tostring(after),'row '..tostring(small16)..'->'..tostring(NexusPanel._responsiveLayout.small),
  'height '..tostring(height16)..'->'..tostring(NexusPanel:GetHeight()))
 C.expect(Near(Size(name),Role('normal')),'N4: the offer name follows the new native height on the next render',Size(name))
 C.expect(LM.Stats().fontBuilds==builds+1 and after>revision,'N4: one font build and a new runtime revision record the change',
  tostring(LM.Stats().fontBuilds-builds)..' builds, revision '..tostring(after))
 C.expect(NexusPanel._responsiveLayout.small==22 and NexusPanel:GetHeight()>height16,
  'N4: the cached layout is not reused: the rows and the panel grow',NexusPanel._responsiveLayout.small)
 SetNative(16)
 P.Render(Play())
 C.expect(Near(Size(name),Role('normal')) and NexusPanel._responsiveLayout.small==small16,'N4: and it returns with the native height',Size(name))
 NexusLoadingStatusFrame=loading
 -- The supported font scales bound the owned sizes.
 SetNative(30);P.Render(Play())
 C.expect(Near(Owned('small'),20) and Near(Owned('normal'),24) and Near(Owned('large'),28),'N4: a native 30 is held at the largest supported scale (2)',Owned('small'))
 -- Revision 2, O4: a native small font under 10 never makes the owned fonts
 -- smaller than the former 10 / 12 / 14. This held before the correction;
 -- the first candidate (lower bound 0.75) gave 7.5 at a native 6.
 for _,under in ipairs({6,8}) do
  SetNative(under);P.Render(Play())
  local scale=LM.RuntimeMetrics()
  C.guard(Owned('small')==10 and Owned('normal')==12 and Owned('large')==14 and scale==1 and NexusPanel._responsiveLayout.small==11,
   'N4: a native '..under..' keeps the former 10 / 12 / 14 at font scale 1 (never smaller than before)',
   tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large'))..' scale '..tostring(scale))
 end
 C.guard(NATIVE.nativeSets==0,'N4: following the native font sets no game font object',NATIVE.nativeSets)
end)

----------------------------------------------------------------------------
-- N5: shared scale. The sizes are UI units, as the reference's are.
----------------------------------------------------------------------------
C.scenario('N5 the owned size equals the reference at any shared effective scale',function()
 SetNative(16)
 local seen={}
 for _,uiScale in ipairs({0.72,1}) do
  NATIVE.uiScale=uiScale
  C.setup(Render(Play())==true,'N5: fixture: the Play panel at effective scale '..uiScale)
  local _,reported=LM.RuntimeMetrics()
  seen[#seen+1]=tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large'))
  C.expect(Near(Size(NexusPanel._offerCards[1].name),Size(GameFontHighlightSmall)*1.2),
   'N5: at effective scale '..uiScale..' the offer name keeps its primary size on the reference (1.2 x its height)',Size(NexusPanel._offerCards[1].name))
  C.guard(Near(reported,uiScale) and NexusPanel:GetScale()==panelScale,'N5: the UI scale is read, never set',reported)
 end
 C.guard(seen[1]==seen[2],'N5: the owned sizes do not depend on the effective scale',seen[1]..' vs '..seen[2])
 NATIVE.uiScale=0.72
end)

----------------------------------------------------------------------------
-- N6: a client that reports a one-line width no wider than its set box.
----------------------------------------------------------------------------
C.scenario('N6 a bounded one-line measurement does not shrink a later tag to an earlier width',function()
 SetNative(16)
 NATIVE.bounded=true
 local first={{text='Cinder Lattice (Epic)'},{text='Hollow Bell (Rare) wanted'},{text='Ashen Tithe (Uncommon)'}}
 local second={{text='Cinder Lattice (Epic) wanted',highlight=true},{text='Hollow Bell (Rare)'},{text='[Guaranteed offer] Ashen Tithe (Uncommon)'}}
 C.setup(Render(Play(first))==true,'N6: fixture: a board whose first and third cards have no tag')
 local cards=NexusPanel._offerCards
 C.setup((cards[1].tag:GetText() or '')=='' and cards[2].tag:GetText()~='','N6: fixture: only the second card is tagged')
 C.setup(Render(Play(second))==true,'N6: fixture: the next board tags the first and third cards')
 local whole,notes=true,{}
 NATIVE.bounded=false
 for _,i in ipairs({1,3}) do
  local tagText=cards[i].tag
  local natural=Natural(tagText)
  notes[#notes+1]=i..': "'..tostring(tagText:GetText())..'" box='..tostring(tagText:GetWidth())..' natural='..string.format('%.1f',natural)
  if tagText:GetWidth()<math.ceil(natural)-0.01 then whole=false end
 end
 print('OBSERVED','N6 '..table.concat(notes,' | '))
 C.setup(cards[1].tag:GetText()==R.OFFER_PICK_TAG and cards[3].tag:GetText()==R.OFFER_GUARANTEED_TAG,'N6: fixture: the pick and guaranteed tags are shown')
 C.expect(whole,'N6: each new tag gets its own width, not the earlier text\'s box',table.concat(notes,' | '))
end)
NATIVE.bounded=false

----------------------------------------------------------------------------
-- N7: a client whose small font is 10 keeps everything as it was.
----------------------------------------------------------------------------
C.scenario('N7 a native height of 10, or no readable reference, keeps 10 / 12 / 14, the 420-unit width and the reference geometry',function()
 SetNative(10)
 C.setup(Render(Play())==true,'N7: fixture: the Play panel at native 10')
 local layout=NexusPanel._responsiveLayout
 local fontScale=LM.RuntimeMetrics()
 C.guard(Owned('small')==10 and Owned('normal')==12 and Owned('large')==14 and fontScale==1,
  'N7: the owned fonts are exactly 10 / 12 / 14 at font scale 1',tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large')))
 C.guard(layout.small==11 and layout.normal==14 and layout.large==16 and layout.gap==6,'N7: the layout rows are 11 / 14 / 16 with a 6 px gap')
 -- The width follows the text scale (W1): at the reference size it is the
 -- reference width, exactly as before.
 C.guard(NexusPanel:GetWidth()==420 and layout.width==420,'N7: at the reference text size the panel keeps its 420-unit width',NexusPanel:GetWidth())
 local cards=NexusPanel._offerCards
 -- Main-panel visual correction (the offer-row grid): a row is the name's
 -- primary line over its quality's secondary line with a 2-unit row gap
 -- above and below: never under the layout's 29-unit model row (14 + 11 + 2
 -- + 2) and as tall as its measured lines. In this model the 12-unit name
 -- measures 14 and the 11-unit quality 13, so a row of one-line texts is 31
 -- (row 2 here: 'Hollow Bell', 'Rare', 'wanted'). A row whose own texts need
 -- more is as tall as they need. The guard that stood here held a row to one
 -- 15-unit line with its quality and tag beside the name (row 2 at 15, its
 -- name box 15, row 1's wrapped name 28); that one-line row is intentionally
 -- gone, so its literals are replaced by the grid's, not relaxed.
 -- Approved panel cleanup, kept: the selected offer's complete reason is
 -- inside its own row and is not repeated under the rows. Row 1 is this
 -- fixture's selected offer, so under its name and quality it also holds
 -- the recommendation's reason, with no more than the layout's gap between
 -- and around them (no reserved empty band).
 local reason=NexusPanel._rollRec
 local rowRect,reasonRect=Rect(cards[1]),Rect(reason)
 print('OBSERVED','N7 row 1='..tostring(cards[1]:GetHeight())..' name='..tostring(cards[1].name:GetHeight())
  ..' quality='..tostring(cards[1].quality:GetHeight())..' tag='..tostring(cards[1].tag:GetHeight())
  ..' reason='..tostring(reason:GetHeight())..' "'..G.Visible(reason:GetText() or '')..'" row 2='..tostring(cards[2]:GetHeight())
  ..' row 3='..tostring(cards[3]:GetHeight()))
 local gridRows,rowNotes=true,{}
 for i=1,3 do
  local stack=cards[i].name:GetHeight()+cards[i].quality:GetHeight()
  local content=math.max(stack,(cards[i].tag:GetText() or '')~='' and cards[i].tag:GetHeight() or 0)
  local want=math.max(29,2+content+2+(i==1 and (2+reason:GetHeight()) or 0))
  rowNotes[#rowNotes+1]=i..': '..tostring(cards[i]:GetHeight())..' want '..want
  if cards[i]:GetHeight()~=want then gridRows=false end
 end
 C.expect(select(2,LM.OfferRows(layout.small,layout.gap,layout.normal))==29 and gridRows
  and cards[2].name:GetHeight()==14 and cards[2].quality:GetHeight()==13 and cards[2]:GetHeight()==31,
  'N7: an offer row is its name line over its quality line with a 2-unit row gap above and below: 31 units for one-line texts (14 + 13 measured), never under the 29-unit model row',
  table.concat(rowNotes,'; '))
 local qualityRect=Rect(cards[1].quality)
 C.guard(reason:IsShown() and G.Visible(reason:GetText() or '')~='' and rowRect and reasonRect and G.Inside(reasonRect,rowRect,0.01)
  and reason:GetHeight()+0.5>=reason:GetStringHeight() and Size(cards[1].name)==12 and Size(cards[1].tag)==11,
  'N7: the selected row holds its whole reason; the name is 12 units and the tag 11',
  tostring(cards[1]:GetHeight())..' / '..tostring(cards[2]:GetHeight()))
 -- GUARD: before the grid the reason already stood under the first line's
 -- quality inside its row, and the row held no more than its texts and the
 -- layout gap; the grid keeps both.
 C.guard(reasonRect and qualityRect and reasonRect[2]>=qualityRect[4]-0.01
  and cards[1]:GetHeight()<=cards[1].name:GetHeight()+cards[1].quality:GetHeight()+reason:GetHeight()+layout.gap,
  'N7: the selected row holds its reason under its quality, with no more than its texts and the layout gap (no reserved band)',
  Text(reasonRect)..' under '..Text(qualityRect)..' in a row of '..tostring(cards[1]:GetHeight()))
 -- Count disclosure (C1). The guard that stood here asked for the 72 px
 -- charges cell, and for the heading 76 px short of its row, on this panel,
 -- whose Details is closed. The charges are counts: with Details closed
 -- there is no row and no cell, and the heading has its whole row, 400 px
 -- of the 420-unit panel (EXPECT; at aca67cf4 the row stood here whatever
 -- Details was). The reference geometry of the cell is unchanged and is
 -- asked for where the row stands, with Details open (GUARD: the two
 -- literals that stood here); Details is then closed again for the checks
 -- below, which are the reference panel's.
 local none,noneDetail=NoCharges(400)
 C.expect(none,'N7: with Details closed there is no charges row or cell: the heading has the whole 400 px row',noneDetail)
 local opened,cellW,headW,rollW,rowShown,rowCount
 KeepDetails(function()
  P._playDetails=true
  opened=Render(Play())==true
  cellW,headW,rollW=NexusPanel._chargesText:GetWidth(),NexusPanel._rollStatus:GetWidth(),NexusPanel._responsiveLayout.boxes.roll.w
  rowShown,rowCount=NexusPanel._chargesText:IsShown(),ChargeRows()
 end)
 C.setup(opened and Render(Play())==true and P._playDetails~=true,'N7: fixture: the same panel with Details open, then closed again')
 C.guard(rowShown and rowCount==1 and cellW==72 and headW==rollW-4-76,
  'N7: with Details open the charges row is on the panel once, its cell is 72 px and the heading keeps the rest less 76',
  tostring(cellW)..' / '..tostring(headW)..' of '..tostring(rollW)..', shown '..tostring(rowShown)..' x'..tostring(rowCount))
 local back,backDetail=NoCharges(400)
 C.expect(back,'N7: and with Details closed again the row and its cell are gone',backDetail)
 local title,build,wishlist=Rect(NexusPanel._contextTitle),Rect(NexusPanel._contextBuild),Rect(NexusPanel._contextWishlist)
 -- Approved compact insets and gaps: the Build row starts at 32 and the
 -- Wishlist line follows the Build line's own row after a 2-unit gap
 -- (formerly a fixed 57, 5 units under it).
 -- Approved panel cleanup (full Build and Wishlist names, wrapped): a line
 -- whose text fits keeps its 20-unit row; a longer one is as tall as its
 -- wrapped text instead of being shortened.
 -- Main-panel visual correction: each line's label is a caption in a
 -- column of its own at x 12 and the two names share one left edge after it
 -- (the next check), so the two x == 12 literals that stood in this guard
 -- went with the former look. Its other pins stand as they were: the lines
 -- at 8 and 32, the Build line in one 20-unit row and so the Wishlist line
 -- at 32 + 20 + 2 = 54. This fixture's Build name still fits one line beside
 -- its caption: the SETUP states that from the words and the fixture's own
 -- font model (nothing is read from the row's box), so a Build row that
 -- grows at the reference size fails this guard instead of moving what the
 -- guard expects.
 local buildLine,wishlistLine=NexusPanel._contextBuild,NexusPanel._contextWishlist
 local captionColumn=0
 for _,caption in ipairs({NexusPanel._contextBuildCaption,NexusPanel._contextWishlistCaption}) do
  if caption:IsShown() then captionColumn=math.max(captionColumn,math.ceil(Natural(caption))+6) end
 end
 C.setup(Natural(buildLine)<=286-captionColumn,
  'N7: fixture: the Build line\'s words fit one line of the 286-unit row less the caption column',
  string.format('%.1f',Natural(buildLine))..' in '..tostring(286-captionColumn))
 C.guard(title and build and wishlist and title[2]==8 and build[2]==32 and wishlist[2]==build[4]+2 and wishlist[2]==54
  and NexusPanel._contextTitle:GetHeight()==20 and buildLine:GetHeight()==20
  and wishlistLine:GetHeight()>=20 and wishlistLine:GetHeight()==math.max(20,math.ceil(wishlistLine:GetStringHeight())),
  'N7: the header lines are at 8 / 32 / 54: the Build line in its 20-unit row, the Wishlist line 2 units under it, in a 20-unit row or as tall as its wrapped text',
  Text(title)..' '..Text(build)..' '..Text(wishlist))
 local buildCap,wishlistCap=Rect(NexusPanel._contextBuildCaption),Rect(NexusPanel._contextWishlistCaption)
 C.expect(buildCap and wishlistCap and build and wishlist and buildCap[1]==12 and wishlistCap[1]==12
  and buildCap[2]==build[2] and wishlistCap[2]==wishlist[2] and build[1]==wishlist[1]
  and build[1]>=math.max(buildCap[3],wishlistCap[3])+6-0.01 and Size(NexusPanel._contextBuildCaption)==11
  and Size(NexusPanel._contextWishlistCaption)==11,
  'N7: the Build and Wishlist captions stand at x 12 in the 11-unit secondary role; the two names share one left edge 6 units after the caption column',
  Text(buildCap)..' '..Text(wishlistCap)..' names '..Text(build)..' '..Text(wishlist))
 local switch,change=Rect(NexusPanel._switchBtn),Rect(NexusPanel._contextChange)
 -- Approved compact gaps: each button stands at its own line's top and is as
 -- tall as that line's 20-unit row, so the two rows 2 units apart do not
 -- overlap (formerly 106 x 22 at 30 and 55, around rows 25 units apart). The
 -- 106-unit width, the routes and the labels are unchanged.
 C.guard(switch and change and switch[2]==build[2] and change[2]==wishlist[2] and switch[3]-switch[1]==106 and switch[4]-switch[2]==20
  and change[3]-change[1]==106 and change[4]-change[2]==20 and G.Apart(switch,change),
  'N7: My Builds and Change are 106 x 20 at their lines\' tops (32 and 54), apart',Text(switch)..' '..Text(change))
 local card,tier,ash,gain=StatusCard()
 -- Approved panel cleanup: the Compact A card (48 units with its bar, where
 -- the original was 56): a 15-unit tier line beside the multiplier's own
 -- width (6 units apart, between the card's 8-unit side insets) and a
 -- 14-unit Soul Ash line across the card. The former fixed 104x16, 172x17
 -- and 70x14 boxes are gone. Approved compact insets: the card is the
 -- panel's width less its 8-unit insets (404 of 420; formerly 400 between
 -- 10-unit insets), so its text room is 388.
 local inner=card and card:GetWidth()-16
 C.guard(card and card:GetWidth()==NexusPanel:GetWidth()-16 and card:GetHeight()==48 and tier:GetHeight()==15
  and tier:GetWidth()+6+gain:GetWidth()==inner
  and ash:GetWidth()==inner and ash:GetHeight()==14 and gain:GetHeight()==15,
  'N7: the Compact A card is 48 units: a 15-unit tier line beside the multiplier and a 14-unit Soul Ash line',
  card and (tier:GetWidth()..'x'..tier:GetHeight()..' '..ash:GetWidth()..'x'..ash:GetHeight()..' '..gain:GetWidth()..'x'..gain:GetHeight()))
 -- No readable reference: the fixed sizes.
 local reference=GameFontHighlightSmall
 SetNative(16)
 GameFontHighlightSmall=nil
 P.Render(Play())
 C.guard(Owned('small')==10 and Owned('normal')==12 and Owned('large')==14,'N7: without a readable reference the owned fonts are 10 / 12 / 14',Owned('small'))
 GameFontHighlightSmall=reference
end)

----------------------------------------------------------------------------
-- R1: headings that are not fitted offer forms (no offer card is shown), on
-- the 420 px panel. The cell takes the room such a heading leaves under the
-- conservative text model too, so the line its row held before still holds.
----------------------------------------------------------------------------
local function Fixed(height,name,model)
 local tag='R1 native '..height..', '..name
 local wasDetails=P._playDetails
 SetNative(height)
 if not C.setup(Render(model)==true and #(P._lastModel.cards or {})==0,tag..': fixture: the panel renders a heading without offer cards') then return end
 local layout=NexusPanel._responsiveLayout
 local head,charges=NexusPanel._rollStatus,NexusPanel._chargesText
 -- Count disclosure (C1). The charges are counts, so this panel, whose
 -- Details is closed, has no charges row, hover or cell: the heading is as
 -- wide as the row it shares with nothing but the Auto disclosure (the roll
 -- width less 4 and less layout.headingReserve). At aca67cf4 the row stood
 -- here whatever Details was. The cell checks below are unchanged and are
 -- made with Details open, where the row stands; Details is then closed
 -- again.
 if not C.setup(type(layout)=='table' and layout.boxes and layout.boxes.roll and head:IsShown() and (head:GetText() or '')~='',
  tag..': fixture: the heading is shown, Details closed') then return end
 local closedHead,closedRoll,closedPanel=head:GetHeight(),layout.boxes.roll.h,NexusPanel:GetHeight()
 local none,noneDetail=NoCharges(layout.boxes.roll.w-4-(tonumber(layout.headingReserve) or 0))
 C.expect(none,tag..': with Details closed there is no charges row, hover or cell: the heading has its whole row',noneDetail)
 P._playDetails=true
 if not C.setup(Render(model)==true and #(P._lastModel.cards or {})==0 and P._playDetails==true,tag..': fixture: the same heading with Details open') then return end
 layout=NexusPanel._responsiveLayout
 if not C.setup(type(layout)=='table' and layout.boxes and layout.boxes.roll and head:IsShown() and charges:IsShown()
  and (head:GetText() or '')~='' and (charges:GetText() or '')~='',tag..': fixture: the heading and the charges row are shown') then return end
 -- Approved compact Auto ON (no permanent row solely for the explanation
 -- control): while Auto is ON the optional "Auto explained" disclosure
 -- stands at the right end of this heading row, so the row the heading and
 -- the charges cell share is the roll width less 4 and less the room the
 -- layout states for that control (layout.headingReserve; none with Auto
 -- OFF). The cell rule itself (Cell) is unchanged.
 local reserve=tonumber(layout.headingReserve) or 0
 local row=layout.boxes.roll.w-4-reserve
 local disclosure=NexusPanel._autoInfoBtn
 if reserve>0 then
  local dr,hr,cr=Rect(disclosure),Rect(head),Rect(charges)
  C.guard(model.auto==true and disclosure and disclosure:IsShown() and dr and hr and cr and G.Apart(dr,hr) and G.Apart(dr,cr)
   and disclosure:GetWidth()<=reserve,tag..': the row is shared only with the shown Auto disclosure, which overlaps neither the heading nor the charges',
   'reserve '..reserve..' disclosure '..Text(dr))
 else
  C.guard(not (disclosure and disclosure:IsShown() and model.auto~=true),tag..': with Auto OFF no disclosure takes heading room')
 end
 local cell=Cell(row,head,false)
 local conservative=Chars(head)*math.max(7.0,0.70*10*Scale())
 local detail='cell '..tostring(charges:GetWidth())..' want '..cell..'; heading "'..G.Visible(head:GetText())..'" box '..tostring(head:GetWidth())
  ..' natural '..string.format('%.1f',Natural(head))..' conservative '..string.format('%.1f',conservative)
  ..'; charges natural '..string.format('%.1f',Natural(charges))
 print('OBSERVED',tag,detail)
 ;(cell>72 and C.expect or C.guard)(charges:GetWidth()==cell and head:GetWidth()==row-cell-4,
  tag..': the charges cell is the layout-derived '..cell..' px and the heading keeps the rest of the row less the cell and its gap',detail)
 if Natural(charges)<=cell then
  C.expect(Natural(charges)<=charges:GetWidth()+0.01,tag..': the compact charges row is whole inline in its cell',detail)
 end
 if conservative<=row-76 then
  C.guard(conservative<=head:GetWidth()+0.01,tag..': the heading still holds its line under the conservative text model',detail)
 end
 C.guard(charges:GetWidth()>=72 and Near(Size(charges),Role('secondary')),tag..': the cell is never under 72 px and the charges keep their font',detail)
 -- Count disclosure (C1): once, with its hover, and only while Details is
 -- open. (Each render here goes through the Render helper, whose first model
 -- has Auto OFF and so releases the height an Auto ON block keeps between
 -- boards: the heights compared are those of a panel laid out afresh.)
 C.guard(ChargeRows()==1 and NexusPanel._chargesHover:IsShown(),tag..': with Details open the charges row is on the panel once, with its hover',
  ChargeRows())
 P._playDetails=wasDetails
 if not C.setup(Render(model)==true and P._playDetails~=true,tag..': fixture: Details closed again') then return end
 layout=NexusPanel._responsiveLayout
 local again,againDetail=NoCharges(layout.boxes.roll.w-4-(tonumber(layout.headingReserve) or 0))
 C.expect(again and head:GetHeight()==closedHead and layout.boxes.roll.h==closedRoll and NexusPanel:GetHeight()==closedPanel,
  tag..': closing Details takes the charges row, its hover and its cell away again: the heading row, the offer block and the panel are as they were',
  againDetail..'; heading row '..tostring(head:GetHeight())..' / '..tostring(closedHead)..', offer block '..tostring(layout.boxes.roll.h)
  ..' / '..tostring(closedRoll)..', panel '..tostring(NexusPanel:GetHeight())..' / '..tostring(closedPanel))
end
for _,height in ipairs({12,16,20}) do
 C.scenario('R1 headings without offer cards at native height '..height,function()
  KeepDetails(Fixed,height,'Auto OFF with a recommendation',Model({auto=false,recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2}))
  KeepDetails(Fixed,height,'Auto ON, paused',Model({auto=true,paused='combat',recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2}))
 end)
end

----------------------------------------------------------------------------
-- T1: the approved readable sizes ("Primary text target 12 UI units;
-- secondary floor 11. Preserve existing native-reference scaling and
-- other-window/shared fonts"). At a native small font of 10 the offer names
-- are 12 and no shown text of the main panel is under 11; at native 16 both
-- keep the native-reference scale (x1.6). The shared owned fonts other
-- windows use stay 10 / 12 / 14 x that scale. EXPECT fails before the change
-- by design: the panel's secondary texts were the shared 10-unit small font.
----------------------------------------------------------------------------
C.scenario('T1 main panel text is at least 11 units, names 12, at the native-reference scale; shared fonts unchanged',function()
 for _,height in ipairs({10,16}) do
  local tag='T1 native '..height
  SetNative(height)
  C.setup(Render(Play())==true,tag..': fixture: the Play panel renders an offer, charges and the difficulty card')
  local scale=Scale()
  local least,which
  for _,region in ipairs(G.Shown(NexusPanel)) do
   if region.kind=='FontString' and G.Visible(region:GetText() or '')~='' then
    local size=Size(region)
    if not least or size<least then least,which=size,G.Visible(region:GetText()) end
   end
  end
  C.expect(least~=nil and least>=11*scale-0.011,tag..': no shown main panel text is under the 11-unit floor x the native scale',
   tostring(least)..' "'..tostring(which)..'"')
  local card=NexusPanel._offerCards[1]
  C.expect(Near(Size(card.name),12*scale) and Near(Size(card.tag),11*scale),
   tag..': an offer name is primary (12) and its tag secondary (11), x the native scale',
   tostring(Size(card.name))..' / '..tostring(Size(card.tag)))
  -- Main-panel visual correction: the title is the 12-unit primary role (a
  -- quieter existing role). This check asked for its own 15-unit role, which
  -- is intentionally gone; no body text is smaller for it (the floor above).
  C.expect(Near(Size(NexusPanel._contextTitle),12*scale),tag..': the panel title is the 12-unit primary role, x the native scale',
   tostring(Size(NexusPanel._contextTitle)))
  C.expect(Near(Size(NexusPanel._rollStatus),11*scale) and Near(Size(NexusPanel._rollRec),11*scale)
   and Near(Size(NexusPanel._chargesText),11*scale),tag..': the offer heading, the recommendation and the charges are secondary (11)',
   tostring(Size(NexusPanel._rollStatus))..' / '..tostring(Size(NexusPanel._rollRec))..' / '..tostring(Size(NexusPanel._chargesText)))
  C.guard(Near(Owned('small'),10*scale) and Near(Owned('normal'),12*scale) and Near(Owned('large'),14*scale),
   tag..': the shared owned fonts of the other windows stay 10 / 12 / 14 x the native scale',
   tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large')))
 end
 C.guard(NATIVE.nativeSets==0,'T1: no game font object is set',NATIVE.nativeSets)
end)

----------------------------------------------------------------------------
-- N9, N10: the header's own text against a font that changes or grows.
----------------------------------------------------------------------------
-- N9. EXPECT (fails before the correction): the Build and Wishlist lines
-- wrap at their measured heights, and those heights were kept for the same
-- header words whatever the font. Rendering the SAME model again after the
-- native height changed (10 to 12.5: the 20-unit header row minimum is the
-- same at both) left the Wishlist line at the height measured for the
-- smaller font, so its last line was cut; back at 10 the larger height
-- stayed as an empty band. The model is rendered directly here: the Render
-- helper above first renders another model, which changes the header words
-- and so hid this.
-- Main-panel visual correction: the panel's width now follows the text scale
-- (525 units at 12.5 where it is 420 at 10), and the header's measurement is
-- keyed by that width too. So that the font is the only thing that changes
-- here, as this scenario's name says, the panel is held at its 420-unit
-- reference width at both native heights (a 640-unit screen at the chosen
-- 150% size bounds the width rule at 420: W1), and the checks are the ones
-- this scenario had: the larger font needs a taller line, the line is as
-- tall as its text there, and the header grows by what the line gained.
-- Without the hold the width change alone asks for the new measurement, and
-- a header that no longer followed the font would pass unseen. A second
-- case changes the names' own font alone (GUARD), and the wider panel is a
-- third, separate case at the end: its width is the EXPECT, and that the
-- line and the header are measured there too is a GUARD.
C.scenario('N9 the wrapped Wishlist line is measured again when only the font changes',function()
 local function Named()
  local m=Play()
  m.progress.wishlistName='Synthetic Play plan whose name is long enough to need more than one line'
  return m
 end
 local line=NexusPanel._contextWishlist
 local function Fit() return line:GetHeight(),math.max(20,math.ceil(line:GetStringHeight())) end
 local function Header() return NexusPanel._responsiveLayout.boxes.header.h end
 -- The header box from its own lines: line 1 (26 units, more by what a title
 -- taller than its 20-unit row needs), the Build line, 2 units, the Wishlist
 -- line and 4 units.
 local function Lines()
  return 26+(NexusPanel._contextTitle:GetHeight()-20)+NexusPanel._contextBuild:GetHeight()+2+line:GetHeight()+4
 end
 -- The screen and the chosen size this fixture sets to hold the width, put
 -- back below.
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local ok,err=pcall(function()
  UIParent:SetSize(640,4000)
  P.SetPanelScale(1.5)
  SetNative(10)
  C.setup(Render(Named())==true and NexusPanel:GetWidth()==420,'N9: fixture: a long Wishlist name at native 10, in the 420-unit panel',
   NexusPanel:GetWidth())
  local h10,need10=Fit()
  local box10=Header()
  C.setup(need10>20 and Near(h10,need10),'N9: fixture: the name wraps at native 10 and its line is as tall as its text',
   tostring(h10)..' for '..tostring(need10))
  SetNative(12.5)
  C.setup(P.Render(Named())==true and math.max(20,NexusPanel._responsiveLayout.normal)==20 and NexusPanel:GetWidth()==420,
   'N9: fixture: the same model at native 12.5 at the same 420-unit width, where the header row minimum is still 20',
   tostring(NexusPanel._responsiveLayout.normal)..', width '..tostring(NexusPanel:GetWidth()))
  local h12,need12=Fit()
  local box12=Header()
  print('OBSERVED','N9 native 10 -> 12.5 at 420 units','line '..tostring(h10)..' -> '..tostring(h12),
   'text needs '..tostring(need10)..' -> '..tostring(need12),'header '..tostring(box10)..' -> '..tostring(box12))
  C.setup(need12>need10,'N9: fixture: the larger font needs a taller line',need12)
  C.expect(Near(h12,need12),'N9: the Wishlist line is as tall as its text at the new size (no line is cut)',
   tostring(h12)..' for '..tostring(need12))
  C.expect(box12>=box10+(need12-need10)-0.01,'N9: and the header grows by what the line gained',
   tostring(box10)..' -> '..tostring(box12))
  SetNative(10)
  P.Render(Named())
  local back,needBack=Fit()
  C.expect(Near(back,needBack) and Near(back,h10) and Header()==box10,
   'N9: back at native 10 the line and the header return (no height is kept from the larger font)',
   tostring(back)..' for '..tostring(needBack)..', header '..tostring(Header()))
  -- The names' own font alone. Since the captions stand apart from the
  -- names, a changed native height also changes the caption's face, and that
  -- face is part of the header's own key (the caption's width places the
  -- names); so the case above no longer shows by itself that the lines'
  -- measurement is keyed by the NAMES' font. Here only the Build and
  -- Wishlist lines take a larger font, as a face that differs from the
  -- caption's would: the native height, the width, the words and the
  -- caption's font stay. GUARD: it held at aca67cf4, where the measurement
  -- was already keyed by the lines' font; dropping that font from the key
  -- fails here.
  local buildLine,shared=NexusPanel._contextBuild,line:GetFontObject()
  local size10=Size(line)
  buildLine:SetFont(PATH,15,'')
  line:SetFont(PATH,15,'')
  C.setup(P.Render(Named())==true and Near(Size(line),15) and Near(Size(buildLine),15) and NexusPanel:GetWidth()==420,
   'N9: fixture: only the Build and Wishlist lines take a 15-unit font, at native 10 in the 420-unit panel',Size(line))
  local hOwn,needOwn=Fit()
  C.guard(needOwn>need10 and Near(hOwn,needOwn) and Header()>=box10+(needOwn-need10)-0.01,
   'N9: the line and the header follow the names\' own font when nothing else changes',
   tostring(hOwn)..' for '..tostring(needOwn)..', header '..tostring(box10)..' -> '..tostring(Header()))
  buildLine:SetFontObject(shared)
  line:SetFontObject(shared)
  C.setup(P.Render(Named())==true and Near(Size(line),size10) and Near(Size(buildLine),size10),
   'N9: fixture: the two lines have their shared font object again',Size(line))
  local again,needAgain=Fit()
  C.guard(Near(again,needAgain) and Near(again,h10) and Header()==box10,
   'N9: and they return with it (no height is kept from the names\' larger font)',
   tostring(again)..' for '..tostring(needAgain)..', header '..tostring(Header()))
  -- The wider panel, apart from the font-only case above: at 100% on a
  -- 1920-unit screen the same model at native 12.5 is laid out 525 units
  -- wide (EXPECT: 420 before the correction), and its line and header are
  -- measured for that width and font (GUARD: they were for 420 units too).
  P.ResetPanelScale()
  UIParent:SetSize(1920,4000)
  SetNative(12.5)
  C.setup(P.Render(Named())==true,'N9: fixture: the same model at native 12.5 on a 1920-unit screen at 100%')
  local wide=NexusPanel:GetWidth()
  local hWide,needWide=Fit()
  print('OBSERVED','N9 native 12.5 on a 1920-unit screen','panel '..tostring(wide),
   'line '..tostring(hWide)..' for '..tostring(needWide),'header '..tostring(Header())..' for lines '..tostring(Lines()))
  C.expect(wide==525,'N9: with the room for it the panel is 525 units wide at native 12.5',wide)
  C.guard(Near(hWide,needWide) and Header()==Lines(),
   'N9: and there too the line is as tall as its text and the header is exactly its lines',
   tostring(hWide)..' for '..tostring(needWide)..', header '..tostring(Header())..' for lines '..tostring(Lines()))
 end)
 if scale0==nil then P.ResetPanelScale() else P.SetPanelScale(scale0) end
 UIParent:SetSize(w0,h0)
 SetNative(10)
 P.Render(Named())
 C.setup(ok,'N9: fixture: the scenario ran',err)
end)

-- N10 (independent Spec review, required finding 2). The title keeps one
-- fixed role (times the native reference) whatever it says. Its state cue
-- is the end of its line, so a title wider than its slot (150 units at 420)
-- wraps inside that slot at its measured height instead of being cut or drawn
-- smaller; header line 1 is as tall as the title needs, and the Build and
-- Wishlist rows, their buttons and the header box move down by exactly what
-- the title gained. Checked for "Nexus" and "Nexus paused" with every cue
-- (Preview, Empty, both, Unconfirmed, Not known) at 100% and 125%.
-- EXPECT fails before the correction (a wide title fell back to another
-- role in a fixed 20-unit line and was still cut at 125%); GUARD: the
-- line-1 slots and the grip do not move, the slot keeps its width, and a
-- title that needs one 20-unit line leaves the header as it was. Widths are
-- this fixture's stated model (0.55 em, 1.15 em lines), not native glyphs.
-- Main-panel visual correction: that one fixed role is the 12-unit primary
-- role (it was the title's own 15-unit role, which the size check here asked
-- for; the quieter role is intended and no body text is smaller for it).
-- The panel is also wider at 125% (525 units, so the slot is 255 and every
-- title fits one line there), so 125% is checked twice: at that width, and
-- in the 420-unit panel a 640-unit screen leaves at the 150% chosen size
-- (W1), where the 150-unit slot makes the titles wrap as before.
C.scenario('N10 the title is one fixed role and whole with every state cue: it wraps in its slot and the header grows',function()
 local title=NexusPanel._contextTitle
 local regions=G.RegionMethods()
 local hadNonSpace=rawget(regions,'SetNonSpaceWrap')
 -- The client's own switch for breaking inside a word longer than the line
 -- (a long localized cue); recorded here so the request can be observed.
 regions.SetNonSpaceWrap=function(self,on) rawset(self,'_nonSpaceWrap',on and true or false) end
 -- Word wrap, recorded the same way (the harness keeps no such state).
 local hadWrap=rawget(regions,'SetWordWrap')
 regions.SetWordWrap=function(self,on)
  rawset(self,'wordWrap',on and true or false)
  if hadWrap then return hadWrap(self,on) end
 end
 local api,paused=Nexus.SessionPause,false
 -- Boundary double: the session pause, as this check sets it (Status only).
 Nexus.SessionPause={Status=function() return {paused=paused,epoch=1} end,IsPaused=function() return paused end,
  Pause=function() return {paused=paused,epoch=1} end,Resume=function() return {paused=paused,epoch=1} end}
 -- The screen and the chosen size this fixture sets for the 420-unit pass,
 -- put back below.
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local ok,err=pcall(function()
  local EDITS={
   {'',nil},
   {' [Preview]',function(m) m.progress.isCommunityPreview=true end},
   {' [Empty]',function(m) m.assignment={emptySlot=true} end},
   {' [Preview; Empty]',function(m) m.progress.isCommunityPreview=true;m.assignment={emptySlot=true} end},
   {' [Unconfirmed]',function(m) m.progress.activeSlot=nil end},
   {' [Not known]',function(m) m.assignment={state='loading'} end},
  }
  local function Top(region) local r=Rect(region);return r and r[2] or nil end
  local wrapped=0
  -- {native height, held at the 420-unit reference width}.
  for _,case in ipairs({{10,false},{12.5,false},{12.5,true}}) do
   local native,held=case[1],case[2]
   if held then UIParent:SetSize(640,4000);P.SetPanelScale(1.5) end
   for _,isPaused in ipairs({false,true}) do
    for _,edit in ipairs(EDITS) do
     local text=(isPaused and 'Nexus paused' or 'Nexus')..edit[1]
     local tag='N10 native '..tostring(native)..(held and ' in the 420-unit panel' or '')..' "'..text..'"'
     SetNative(native)
     paused=isPaused
     local m=Play()
     if edit[2] then edit[2](m) end
     if C.setup(Render(m)==true and G.Visible(title:GetText() or '')==text,tag..': fixture: the title says this',title:GetText()) then
      local layout=NexusPanel._responsiveLayout
      local size,slot=Size(title),title:GetWidth()
      local rect=Rect(title)
      local needs=math.ceil(title:GetStringHeight())
      local rows=G.Rows(title:GetText() or '',slot,CHAR*size)
      local height=rect and (rect[4]-rect[2]) or -1
      -- The longest word of the line at this size: wrapping can keep the
      -- line whole only while each word fits the slot.
      local longest=0
      for word in G.Visible(title:GetText() or ''):gmatch('%S+') do longest=math.max(longest,G.Length(word)*CHAR*size) end
      local titleRow=math.max(20,needs)
      local gained=titleRow-20
      local build,wishlist=Rect(NexusPanel._contextBuild),Rect(NexusPanel._contextWishlist)
      local header=layout.boxes.header
      print('OBSERVED',tag,'font='..tostring(size),'slot='..tostring(slot),'line='..string.format('%.1f',Natural(title)),
       'rows='..tostring(rows),'box='..tostring(height),'needs='..tostring(needs),'header='..tostring(header.h),
       'build top='..tostring(build and build[2]))
      if rows>1 then wrapped=wrapped+1 end
      C.setup(longest<=slot+0.01,tag..': fixture: every word of the title fits the slot at the title size',longest)
      C.setup(not held or NexusPanel:GetWidth()==420,tag..': fixture: the panel is held at its 420-unit reference width',NexusPanel:GetWidth())
      C.expect(Near(size,Role('normal')),tag..': the title is drawn at the 12-unit primary role whatever it says, never fitted smaller',size)
      C.expect(height+0.5>=needs and (rows<=1 or rawget(title,'wordWrap')==true) and not (rows<=1 and LM.Shortened(title)),
       tag..': the whole title is shown: one line that fits, or wrapped in a box as tall as its lines',
       'box '..tostring(height)..' for '..tostring(needs)..', rows '..tostring(rows)..', wrap '..tostring(rawget(title,'wordWrap')))
      C.expect(math.abs(height-titleRow)<=0.01,tag..': the title box is its measured height (at least the 20-unit line), no taller',
       tostring(height)..' / '..tostring(titleRow))
      C.expect(build~=nil and wishlist~=nil and math.abs(build[2]-(32+gained))<=0.01 and build[2]>=rect[4]-0.01
       and wishlist[2]>=build[4]-0.01 and math.abs((header.y+header.h)-(wishlist[4]+4))<=0.01,
       tag..': the Build row starts under the whole title, the Wishlist row under it, and the header box closes 4 units under that',
       'title '..Text(rect)..' build '..Text(build)..' wishlist '..Text(wishlist)..' header y='..tostring(header.y)..' h='..tostring(header.h))
      C.expect(math.abs((Top(NexusPanel._switchBtn) or -1)-build[2])<=0.01 and math.abs((Top(NexusPanel._contextChange) or -1)-wishlist[2])<=0.01,
       tag..': My Builds and Change stay at the top of their own rows',
       tostring(Top(NexusPanel._switchBtn))..' / '..tostring(Top(NexusPanel._contextChange)))
      local line1=P.HeaderSlots()
      C.guard(slot==NexusPanel:GetWidth()-line1.reserved-line1.titleLeft and (NexusPanel:GetWidth()~=420 or slot==150)
       and rect~=nil and rect[1]==36 and rect[2]==8,
       tag..': the title keeps its slot (from x 36, y 8 to the Auto slot: 150 units in the 420-unit panel)',Text(rect))
      local grip=P.EnsureHeaderGrip()
      local gr=grip and Rect(grip) or nil
      C.guard(gr~=nil and gr[1]==8 and gr[2]==6 and gr[3]-gr[1]==24 and gr[4]-gr[2]==24,tag..': the 24 x 24 grip does not move',Text(gr))
      if gained==0 then
       C.guard(math.abs(build[2]-32)<=0.01,tag..': a title that needs one 20-unit line leaves the Build row at 32',build[2])
      end
     end
    end
   end
   if held then P.ResetPanelScale();UIParent:SetSize(w0,h0) end
  end
  C.setup(wrapped>=6,'N10: fixture: several of these titles need more than one line',wrapped)
  C.expect(rawget(title,'_nonSpaceWrap')==true,'N10: the title may also break inside a word longer than its slot (a long localized cue is not cut)',
   tostring(rawget(title,'_nonSpaceWrap')))
  local s=P.HeaderSlots()
  C.guard(s.top==7 and s.height==22 and s.reserved==234 and s.titleLeft==36 and s.gripWidth==24 and s.gripHeight==24,
   'N10: the header line 1 slots are unchanged')
  C.guard(NATIVE.nativeSets==0,'N10: no game font object is set',NATIVE.nativeSets)
 end)
 paused=false
 Nexus.SessionPause=api
 regions.SetNonSpaceWrap=hadNonSpace
 regions.SetWordWrap=hadWrap
 if scale0==nil then P.ResetPanelScale() else P.SetPanelScale(scale0) end
 UIParent:SetSize(w0,h0)
 SetNative(10)
 Render(Play())
 C.setup(ok,'N10: fixture: the title scenario ran',err)
end)

----------------------------------------------------------------------------
-- N11: the Orb controls strip attached under the panel is the panel's text.
----------------------------------------------------------------------------
-- Independent Spec review of 24a40301 (the attached strip is a surface the
-- main panel owns). Its words were the shared stock small font in a fixed
-- 252 x 52 box, cut at 36 characters. They are the panel's own secondary
-- role (11 units x the native reference) on that one label, they wrap at the
-- label's width, the label is as tall as they measure (at least its 52
-- units), and the strip and its row of controls move down by what the words
-- need beyond that. EXPECT fails before the correction; GUARD: no shared or
-- game font object changes, the paused target's name is whole, and where
-- the words fit the strip keeps its 100-unit height with the controls at 65.
-- The strip is reached through the real panel with time advanced (its own
-- scheduled read). Widths are this fixture's stated model, not native glyphs.
C.scenario('N11 the attached Orb strip draws its words at the panel\'s secondary role, wrapped; its controls move under them',function()
 local runtime=Nexus.OrbRuntime
 if not C.setup(type(runtime)=='table' and type(runtime.CompactStatus)=='function','N11: fixture: the Orb runtime read exists') then return end
 local compact=runtime.CompactStatus
 local NAME='Rank 2 Covenant of the Unbroken Synthetic Choir'
 -- A paused run whose target changed: the strip names the target and says
 -- the review instruction, its two longest lines.
 runtime.CompactStatus=function()
  return {state='PAUSED',spent=41,limit=97,reserved=0,running=false,pending=false,canResume=true,uncertain=0,
   unconfirmedResults=0,historyKnown=true,remaining=58,limitKnown=true,resumeTarget={kind='changed',name=NAME}}
 end
 -- Time is advanced below; the host's own schedule then refreshes the panel
 -- with `shown`, the model this scenario drew (Panel.Init keeps one table).
 local shown
 P.Init({RefreshDisplay=function() return shown and P.Render(shown) or false end})
 local stockBefore=Size(GameFontHighlightSmall)
 local ok,err=pcall(function()
  local grew=0
  for _,native in ipairs({10,12.5}) do
   local tag='N11 native '..tostring(native)
   SetNative(native)
   shown=Play()
   C.setup(Render(shown)==true,tag..': fixture: the Play panel renders')
   H.Advance(.3)
   local bar=NexusPanel._orbControls
   if C.setup(bar~=nil and bar:GetParent()==NexusPanel and bar:IsVisible() and bar.summary:IsVisible(),
    tag..': fixture: the attached strip is shown after its scheduled read') then
    local label=bar.summary
    local text=G.Visible(label:GetText() or '')
    local rect,strip=Rect(label),Rect(bar)
    local needs=math.ceil(label:GetStringHeight())
    local box=rect[4]-rect[2]
    local extra=math.max(0,needs-52)
    print('OBSERVED',tag,'font='..tostring(Size(label)),'label '..Text(rect),'needs='..tostring(needs),'strip '..Text(strip),
     'text='..text:gsub('\n',' / '))
    C.expect(Near(Size(label),Role('secondary')),tag..': the strip\'s words are the panel\'s secondary role (11 x the native scale)',Size(label))
    C.expect(box+0.5>=needs and math.abs(box-math.max(52,needs))<=0.01 and not text:find('...',1,true),
     tag..': the words are whole: wrapped in a box as tall as they measure, at least 52 units',tostring(box)..' for '..tostring(needs))
    -- (Before the correction the name was cut to fit one line, so this
    -- guard asks for its beginning only; the whole name is expected below.)
    C.guard(text:find("'Rank 2",1,true)~=nil and text:find('Paused - review it in the Orb window',1,true)~=nil,
     tag..': the strip names the paused target and says its instruction',text)
    C.expect(text:find("'"..NAME.."' (new)",1,true)~=nil,tag..': the target\'s name is whole, with its kind',text)
    C.expect(math.abs((strip[4]-strip[2])-(100+extra))<=0.01,tag..': the strip is its 100 units plus what the words need beyond 52',
     tostring(strip[4]-strip[2])..' / '..tostring(100+extra))
    local placed=true
    for _,b in ipairs({bar.pause,bar.resume,bar.stop,bar.details}) do
     local r=b:IsVisible() and Rect(b) or nil
     if not (r and math.abs(r[2]-(strip[2]+65+extra))<=0.01 and r[2]>=rect[4]-0.01 and G.Inside(r,strip,0.01)) then placed=false end
    end
    C.expect(placed,tag..': Pause, Resume, Stop and Details sit in one row under the whole words, inside the strip',
     'row wanted at '..tostring(strip[2]+65+extra)..', words end '..tostring(rect[4]))
    if extra==0 then
     C.guard(math.abs((strip[4]-strip[2])-100)<=0.01 and math.abs(box-52)<=0.01,tag..': words that fit leave the strip at 100 units and the label at 52')
    else
     grew=grew+1
    end
    C.guard(bar.pause:GetScript('OnClick')~=nil and bar.resume:GetScript('OnClick')~=nil and bar.stop:GetScript('OnClick')~=nil
     and bar.details:GetScript('OnClick')~=nil and not bar.pause:IsEnabled() and not bar.resume:IsEnabled() and bar.stop:IsEnabled(),
     tag..': the controls keep their handlers and gates (a changed target resumes only after review)')
   end
  end
  C.expect(grew>=1,'N11: at 125% the words need more than 52 units and the strip grew for them',grew)
  C.guard(Near(Size(GameFontHighlightSmall),NATIVE.height) and NATIVE.nativeSets==0,
   'N11: the shared stock small font is untouched and no game font object is set',tostring(Size(GameFontHighlightSmall))..' sets '..tostring(NATIVE.nativeSets))
 end)
 runtime.CompactStatus=compact
 shown=Play()
 SetNative(10)
 Render(shown)
 H.Advance(.3)
 -- No host callback from here on: Panel.Refresh renders its last model.
 P.Init({})
 C.setup(stockBefore~=nil and ok,'N11: fixture: the attached strip scenario ran',err)
end)

----------------------------------------------------------------------------
-- W1: the panel's width follows its text scale.
----------------------------------------------------------------------------
-- Main-panel visual correction (readability before the fixed 420 units).
-- The panel was 420 units wide at every text size, so at the reported native
-- 16 (160%) its names, statuses and reason had the room 262 units give at
-- the reference size, and wrapped or crowded. The width is one rule now
-- (LayoutMetrics.PanelWidth): the 420-unit reference width x the font scale
-- the owned fonts follow (1 to 2), no wider than the screen leaves at the
-- chosen panel size (its width less the fit's 24-unit margin, over that
-- size; a screen under the fit's own 640-unit floor bounds nothing), and
-- never under 420. It is read once per render from the chosen size, never
-- from the size a fit applied, so the same inputs give the same width and a
-- repeated render takes no layout pass; a choice of size that changes the
-- width lays the shown model out again at once.
-- EXPECT fails at aca67cf4 (no rule: 420 units at every size). GUARD: the
-- reference size keeps 420; no text is drawn smaller for the width; the fit
-- still bounds the applied size; nothing is saved; long names, statuses and
-- the reason stay whole at every width. The screen is UIParent's size as
-- this fixture sets it and widths are its stated font model, not native
-- glyphs.
C.scenario('W1 the panel width follows the text scale, bounded by the screen at the chosen size, once per render',function()
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local wasDetails=P._playDetails
 local saved=P.SavedLayoutRoot()
 C.setup(rawget(saved,'panelScale')==nil,'W1: fixture: no chosen panel size is saved',tostring(rawget(saved,'panelScale')))
 local x0,y0=rawget(saved,'panelX'),rawget(saved,'panelY')
 -- The rule itself: {font scale, screen width, chosen size, width}.
 local ruled,ruleNotes=type(LM.PanelWidth)=='function',{}
 if ruled then
  for _,case in ipairs({{1,1920,1,420},{1.25,1920,1,525},{1.6,1920,1,672},{2,1920,1,840},{3,1920,1,840},{0.5,1920,1,420},
   {1.6,800,1,672},{2,800,1,776},{2,640,1,616},{1.6,640,1.5,420},{1.6,1024,1.5,666},{2,1024,0.5,840},
   {2,600,1,840},{2,0,1,840},{2,math.huge,1,840},{0/0,1920,1,420},{2,800,0,776},{2,800,0/0,776}}) do
   local got=LM.PanelWidth(case[1],case[2],case[3])
   if got~=case[4] then
    ruled=false
    ruleNotes[#ruleNotes+1]=tostring(case[1])..' / '..tostring(case[2])..' / '..tostring(case[3])..' gives '..tostring(got)..', not '..case[4]
   end
  end
  if LM.PanelWidth(2,nil,1)~=840 or LM.PanelWidth(nil,1920,1)~=420 or LM.PanelWidth('x',1920,nil)~=420 then
   ruled=false;ruleNotes[#ruleNotes+1]='a missing or unreadable input is not the reference scale, no bound or 100%'
  end
 else
  ruleNotes[1]='LayoutMetrics has no PanelWidth'
 end
 C.expect(ruled,'W1: the rule: 420 x the font scale (1 to 2), no wider than (screen width - 24) / the chosen size on a screen of 640 units or more, never under 420',
  table.concat(ruleNotes,'; '))
 -- Names as long as localized ones (synthetic words, this file's ASCII).
 local LONGER={
  {text='[Guaranteed offer] Unerschuetterliche Resonanz des ungebrochenen Bundes der Wanderchoere (Uncommon) wanted',highlight=true},
  {text='Hohlglocke der verlorenen Stundengebete (Rare) wanted'},
  {text='[Guaranteed offer] Aschezehnt des wandernden Chores der Tiefe (Uncommon)'},
 }
 local ok,err=pcall(function()
  -- {native height, screen width, chosen size, the width the rule gives}:
  -- the reference size and under it, 125%, the reported 160%, 200% and
  -- above it on a wide screen; then screens that bound the width, the
  -- 420-unit floor (where only the fit can reduce the applied size) and a
  -- chosen 150%.
  for _,case in ipairs({{10,1920,1,420},{8,1920,1,420},{12.5,1920,1,525},{16,1920,1,672},{20,1920,1,840},{30,1920,1,840},
   {16,800,1,672},{20,800,1,776},{20,640,1,616},{16,640,1.5,420},{16,1024,1.5,666}}) do
   local native,screen,chosen,want=case[1],case[2],case[3],case[4]
   UIParent:SetSize(screen,4000)
   if chosen==1 then P.ResetPanelScale() else P.SetPanelScale(chosen) end
   SetNative(native)
   for pass,lines in ipairs({LONG,LONGER}) do
    local tag='W1 native '..tostring(native)..', a '..screen..'-unit screen, '..(chosen*100)..'%'..(pass==2 and ', longer names' or '')
    local m=Play(lines)
    if pass==2 then m.progress.wishlistName='Synthetic Play plan whose name is as long as a localized one and needs more than one line' end
    if C.setup(Render(m)==true,tag..': fixture: the Play panel renders') then
     local layout=NexusPanel._responsiveLayout
     local width,applied=NexusPanel:GetWidth(),NexusPanel:GetScale()
     local cards=NexusPanel._offerCards
     local area=Rect(NexusPanel._rollArea)
     local b=layout.boxes
     print('OBSERVED',tag,'panel='..tostring(width)..'x'..tostring(NexusPanel:GetHeight()),'applied size='..tostring(applied),
      'roll='..tostring(b.roll.w)..'x'..tostring(b.roll.h),'rows='..layout.small..'/'..layout.normal)
     -- EXPECT where the rule gives more than the reference width (420 at
     -- every size before the correction); the reference size keeps 420.
     ;(want>420 and C.expect or C.guard)(width==want and layout.width==want and width==WantWidth(),
      tag..': the panel is '..want..' units wide',tostring(width)..' / layout '..tostring(layout.width)..' / rule '..tostring(WantWidth()))
     C.guard(b.roll.x==8 and b.roll.w==width-16 and b.status.w==width-16 and b.footer.w==width-16
      and area~=nil and math.abs((area[3]-area[1])-(width-16))<=0.01,
      tag..': the difficulty card, the offer block and the footer span the panel between its 8-unit insets',
      tostring(b.roll.w)..' / '..tostring(b.status.w)..' / '..tostring(b.footer.w)..' in '..tostring(width))
     -- The applied size: a width the rule gave never makes the fit reduce
     -- the chosen size. Only the 420-unit floor can be wider than the screen
     -- leaves, and there the fit reduces the applied size as before.
     C.guard(type(applied)=='number' and width*applied<=screen-24+1,
      tag..': at its applied size the panel is no wider than the screen less the 24-unit margin',tostring(width)..' x '..tostring(applied))
     if want*chosen<=screen-24 then
      C.guard(Near(applied,chosen),tag..': the chosen size is applied whole (the width asks for no reduction)',applied)
     else
      C.guard(want==420 and Near(applied,(screen-24)/420),tag..': at the 420-unit floor the fit, not the width, reduces the applied size',applied)
     end
     -- No text is drawn smaller for the width.
     C.guard(Near(Size(cards[1].name),Role('normal')) and Near(Size(cards[1].tag),Role('secondary'))
      and Near(Size(NexusPanel._rollStatus),Role('secondary')) and Near(Size(NexusPanel._contextBuild),Role('normal')),
      tag..': the names and the secondary text keep their native-derived sizes',
      tostring(Size(cards[1].name))..' / '..tostring(Size(cards[1].tag))..' / '..tostring(Size(NexusPanel._rollStatus)))
     -- Whole: a box as tall as the lines the client measures for its text
     -- at the box's width. The one-line heading and charges row were lower
     -- than their own line before the correction (N2); the wrapped texts
     -- were whole and stay so.
     local notes={}
     local function Whole(name,text)
      if text and text:IsShown() and G.Visible(text:GetText() or '')~='' and text:GetHeight()+0.5<text:GetStringHeight() then
       notes[#notes+1]=name..' '..tostring(text:GetHeight())..' for '..tostring(text:GetStringHeight())
       return false
      end
      return true
     end
     -- Count disclosure (C1): both passes have Details closed, so the
     -- panel holds no charges row, hover or cell and the heading has its
     -- whole row. The check that stood here took the heading and the charges
     -- row together; the heading is asked here, and the two together where
     -- the row stands, with Details open (after the second pass, below).
     local lineRows=Whole('heading',NexusPanel._rollStatus)
     C.expect(lineRows,tag..': the offer heading is as tall as its measured line',table.concat(notes,'; '))
     local none,noneDetail=NoCharges(b.roll.w-4)
     C.expect(none,tag..': with Details closed there is no charges row, hover or cell: the heading has its whole row',noneDetail)
     notes={}
     local wrapped=true
     for i=1,3 do
      for _,key in ipairs({'name','quality','tag'}) do wrapped=Whole(i..'.'..key,cards[i][key]) and wrapped end
     end
     wrapped=Whole('reason',NexusPanel._rollRec) and wrapped
     wrapped=Whole('title',NexusPanel._contextTitle) and wrapped
     wrapped=Whole('Build',NexusPanel._contextBuild) and wrapped
     wrapped=Whole('Wishlist',NexusPanel._contextWishlist) and wrapped
     C.guard(wrapped,tag..': every offer name, quality, tag, the reason and the header lines are whole (wrapped, never cut)',table.concat(notes,'; '))
     local reasonRect=Rect(NexusPanel._rollRec)
     C.guard(G.Visible(NexusPanel._rollRec:GetText() or '')=='' or (reasonRect~=nil and area~=nil and G.Inside(reasonRect,area,0.01)),
      tag..': the reason stays inside the offer block',Text(reasonRect))
     OfferRows(tag,area,Role('secondary'),lines,C.guard)
     -- Once: the same inputs give the same width and no further layout pass.
     -- The settled render is a GUARD (the layout cache: it held at the fixed
     -- 420 units too). That the width it leaves is the rule's is the new
     -- behaviour wherever the rule gives more than 420 units, so it is an
     -- EXPECT there and a GUARD at the reference width.
     local computations=LM.Stats().computations
     P.Render(m);P.Render(m)
     C.guard(LM.Stats().computations==computations,tag..': a repeated render takes no layout pass',
      LM.Stats().computations-computations)
     ;(want>420 and C.expect or C.guard)(NexusPanel:GetWidth()==want and NexusPanel._responsiveLayout.width==want,
      tag..': and the repeated render leaves the panel at its '..want..' units',
      tostring(NexusPanel:GetWidth())..' / layout '..tostring(NexusPanel._responsiveLayout.width))
     if pass==2 then
      -- Count disclosure (C1): the same panel with Details open, where the
      -- charges row stands. The heading and the charges row are as tall as
      -- their measured lines (the check that stood in both passes above,
      -- which at aca67cf4 saw the row with Details closed), and the row is
      -- on the panel once, with its hover, after the heading and inside the
      -- offer block, at the same panel width (GUARD: Details has no part in
      -- the width, and the open panel is the one aca67cf4 showed).
      P._playDetails=true
      if C.setup(Render(m)==true and P._playDetails==true,tag..': fixture: the same panel with Details open') then
       local head,charges,hover=NexusPanel._rollStatus,NexusPanel._chargesText,NexusPanel._chargesHover
       notes={}
       local openRows=Whole('heading',head)
       openRows=Whole('charges',charges) and openRows
       C.expect(charges:IsShown() and openRows,tag..': with Details open the offer heading and the charges row are as tall as their measured lines',
        table.concat(notes,'; '))
       local hr,cr,openArea=Rect(head),Rect(charges),Rect(NexusPanel._rollArea)
       C.guard(ChargeRows()==1 and hover:IsShown() and hr~=nil and cr~=nil and openArea~=nil and hr[3]<=cr[1]+0.01
        and G.Inside(cr,openArea,0.01) and NexusPanel:GetWidth()==width,
        tag..': with Details open the charges row is on the panel once, with its hover, after the heading and inside the offer block; the panel keeps its width',
        Text(hr)..' '..Text(cr)..' in '..Text(openArea)..', panel '..tostring(NexusPanel:GetWidth()))
      end
      P._playDetails=wasDetails
     end
    end
   end
  end
  -- A choice of size that changes the width lays the panel out at once.
  UIParent:SetSize(1024,4000)
  P.ResetPanelScale()
  SetNative(16)
  if C.setup(Render(Play())==true,'W1: fixture: the Play panel at native 16 on a 1024-unit screen at 100%') then
   local before=NexusPanel:GetWidth()
   P.SetPanelScale(1.5)
   C.expect(before==672 and NexusPanel:GetWidth()==666 and NexusPanel._responsiveLayout.width==666 and Near(NexusPanel:GetScale(),1.5),
    'W1: 672 units there at 100%; choosing 150% lays the panel out at once at the 666 units that size leaves, at the whole chosen size',
    tostring(before)..' -> '..tostring(NexusPanel:GetWidth())..' at '..tostring(NexusPanel:GetScale()))
   P.ResetPanelScale()
   C.expect(NexusPanel:GetWidth()==672 and Near(NexusPanel:GetScale(),1),'W1: and back at 100% it is 672 units again',
    tostring(NexusPanel:GetWidth())..' at '..tostring(NexusPanel:GetScale()))
  end
 end)
 -- The chosen size (while the screen is still readable), the screen and the
 -- native height return; Details is as it was (C1: the cases open it).
 P._playDetails=wasDetails
 P.ResetPanelScale()
 UIParent:SetSize(w0,h0)
 SetNative(10)
 Render(Play())
 C.setup(ok,'W1: fixture: the width scenario ran',err)
 C.guard(rawget(saved,'panelScale')==nil and rawget(saved,'panelX')==x0 and rawget(saved,'panelY')==y0,
  'W1: following the width saves nothing: no size and no position',
  tostring(rawget(saved,'panelScale'))..' / '..tostring(rawget(saved,'panelX'))..' / '..tostring(rawget(saved,'panelY')))
 C.guard(NexusPanel:GetScale()==panelScale and (UIParent:GetScale() or 1)==1 and NATIVE.nativeSets==0,
  'W1: the panel is back at its size; no UI scale and no game font object was set',tostring(NexusPanel:GetScale())..' sets '..tostring(NATIVE.nativeSets))
end)

----------------------------------------------------------------------------
-- M1: the setup and completion views' texts are measured.
----------------------------------------------------------------------------
-- Independent review of the frozen first candidate (Spec advisory A1, made a
-- required readability correction): setup and completion are main-panel
-- states too. Their texts kept a fixed number of modelled lines whatever
-- they said: the setup title one large line and its hint two small lines,
-- the completion badge one normal line and its sentence two small lines. A
-- line is taller than its modelled row at a larger native size (and, in
-- this model, the title's line at every size), and a hint or a sentence
-- longer than two lines lost its end. Each is now wrapped in its row's width
-- at its measured height, never under the modelled rows it had; the setup
-- buttons, the footer and the panel follow. The completion sentence names
-- the Wishlist whole (it was shortened to 34 characters for a fixed 252-unit
-- box). Checked at native 10 and at the reported native 16, on a panel with
-- the room its text scale asks for and held at 420 units, with a short and a
-- long setup note and a short and a long Wishlist name.
-- What a text needs is worked out here from its words and its font in this
-- fixture's stated model; nothing is read from its box. A check is EXPECT
-- where the text needs more than its modelled rows (all it had at aca67cf4)
-- and GUARD where it fits them, which holds before and after.
C.scenario('M1 the setup and completion texts are measured: whole at native 16 and with long words',function()
 local NOTE='Synthetic setup note that is long enough to need several lines in the panel at every supported text size, '
  ..'so a hint held to two modelled lines would lose its end.'
 local NAME='Synthetic Wishlist with a name as long as a localized one that the completion sentence keeps whole'
 local function Setup(note)
  return {status='ready',level=40,auto=false,cards={},recommendation='',character='SyntheticHero',
   progress={total=0,missing={},shed={},toLock={},unknownTomes={}},assignment={state='unavailable',note=note}}
 end
 local function Complete(name)
  return {status='ready',level=40,auto=false,cards={},recommendation='',character='SyntheticHero',
   progress={wishlistName=name,total=6,owned=6,missing={},shed={},toLock={},unknownTomes={}}}
 end
 -- The shown text the layout placed on a box (these texts are the panel's
 -- own regions).
 local function TextAt(box)
  for _,region in ipairs(NexusPanel.regions or {}) do
   if region.kind=='FontString' and region:IsShown() and G.Visible(region:GetText() or '')~='' then
    local r=Rect(region)
    if r and math.abs(r[1]-box.x)<0.01 and math.abs(r[2]-box.y)<0.01 then return region end
   end
  end
  return nil
 end
 -- What a text needs in a row `width` wide: its lines there, each as tall as
 -- its font's line (0.55 em characters, 1.15 em lines).
 local function Needs(region,width)
  local size=Size(region)
  return math.max(1,G.Rows(region:GetText() or '',width,CHAR*size))*math.ceil(size*LINE)
 end
 -- One text on its box, in a row as wide as the block.
 local function Row(tag,what,box,modelled,row)
  local region=box and TextAt(box) or nil
  if not C.setup(region~=nil,tag..': fixture: the '..what..' is shown on its box') then return nil end
  local needs=Needs(region,row)
  local want=math.max(modelled,needs)
  local detail=what..': box '..tostring(box.w)..'x'..tostring(box.h)..', text '..tostring(region:GetHeight())..' for '
   ..tostring(region:GetStringHeight())..', needs '..tostring(needs)..' in '..tostring(row)..' ('..tostring(modelled)..' modelled)'
  print('OBSERVED',tag,detail)
  ;(needs>modelled and C.expect or C.guard)(box.w==row and box.h==want and region:GetHeight()==want
   and region:GetHeight()+0.5>=region:GetStringHeight(),
   tag..': the '..what..' is whole in its row: as tall as its wrapped text, never under its modelled rows',detail)
  return region
 end
 local effects=Effects()
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local ok,err=pcall(function()
  -- {native height, held at the 420-unit reference width}.
  for _,case in ipairs({{10,false},{16,false},{16,true}}) do
   local native,held=case[1],case[2]
   if held then UIParent:SetSize(640,4000);P.SetPanelScale(1.5) else P.ResetPanelScale();UIParent:SetSize(1920,4000) end
   SetNative(native)
   local where='M1 native '..tostring(native)..(held and ' in the 420-unit panel' or '')
   -- The setup view: its title, and a note as its hint.
   for _,note in ipairs({'Synthetic hint.',NOTE}) do
    local tag=where..', setup, '..(note==NOTE and 'a long note' or 'a short note')
    if C.setup(P.Render(Setup(note))==true,tag..': fixture: the setup view renders') then
     local layout=NexusPanel._responsiveLayout
     local b=layout.boxes
     local row=NexusPanel:GetWidth()-16
     if C.setup(b.setupTitle and b.setupHint and b.setupAssign and b.setupCreate and b.footer and (not held or NexusPanel:GetWidth()==420),
      tag..': fixture: the layout holds the title, the hint, both buttons and the footer',NexusPanel:GetWidth()) then
      Row(tag,'setup title',b.setupTitle,layout.large,row)
      local hint=Row(tag,'setup hint',b.setupHint,2*layout.small,row)
      C.setup(hint~=nil and G.Visible(hint:GetText() or '')==note,tag..': fixture: the hint is the note, whole',hint and hint:GetText())
      C.guard(b.setupHint.y==b.setupTitle.y+b.setupTitle.h+layout.gap and b.setupAssign.y==b.setupHint.y+b.setupHint.h+layout.gap
       and b.setupCreate.y==b.setupAssign.y+b.setupAssign.h+layout.gap and b.footer.y==b.setupCreate.y+b.setupCreate.h+layout.gap
       and NexusPanel:GetHeight()==layout.height and layout.height==b.footer.y+b.footer.h+6,
       tag..': the hint, both buttons and the footer follow one gap apart and the panel ends 6 units under the footer',
       tostring(b.setupHint.y)..' / '..tostring(b.setupAssign.y)..' / '..tostring(b.setupCreate.y)..' / '..tostring(b.footer.y)
       ..' in '..tostring(NexusPanel:GetHeight()))
     end
    end
   end
   -- The completion view without the difficulty card: its badge and the
   -- sentence that names the Wishlist.
   for _,name in ipairs({'Hollow Tide',NAME}) do
    local tag=where..', complete, '..(name==NAME and 'a long name' or 'a short name')
    if C.setup(P.Render(Complete(name))==true,tag..': fixture: the completion view renders') then
     local layout=NexusPanel._responsiveLayout
     local b=layout.boxes
     local row=NexusPanel:GetWidth()-16
     if C.setup(b.completeTitle and b.completeText and b.footer and (not held or NexusPanel:GetWidth()==420),
      tag..': fixture: the layout holds the badge, the sentence and the footer',NexusPanel:GetWidth()) then
      Row(tag,'completion badge',b.completeTitle,layout.normal,row)
      local sentence=Row(tag,'completion sentence',b.completeText,2*layout.small,row)
      local words=sentence and G.Visible(sentence:GetText() or '') or ''
      if name==NAME then
       -- EXPECT: the name was shortened to 34 characters.
       C.expect(words:find(NAME,1,true)~=nil,tag..': the sentence names the Wishlist whole',words)
      else
       C.guard(words:find(name,1,true)~=nil,tag..': the sentence names the Wishlist',words)
      end
      C.guard(b.completeText.y==b.completeTitle.y+b.completeTitle.h+layout.gap and b.footer.y>=b.completeText.y+b.completeText.h
       and NexusPanel:GetHeight()==layout.height,
       tag..': the sentence follows the badge one gap under it, the footer stands under the sentence and the panel is the layout height',
       tostring(b.completeTitle.y)..' / '..tostring(b.completeText.y)..' / '..tostring(b.footer.y)..' in '..tostring(NexusPanel:GetHeight()))
     end
    end
   end
  end
 end)
 if scale0==nil then P.ResetPanelScale() else P.SetPanelScale(scale0) end
 UIParent:SetSize(w0,h0)
 SetNative(10)
 Render(Play())
 C.setup(ok,'M1: fixture: the setup and completion scenario ran',err)
 C.guard(Effects()==effects,'M1: showing the setup and completion views took no game action, sent nothing and left Auto as it was',Effects())
 C.guard(NATIVE.nativeSets==0,'M1: no game font object is set',NATIVE.nativeSets)
end)

----------------------------------------------------------------------------
-- C1: the charges are counts; the heading is worded for the row it has.
----------------------------------------------------------------------------
-- Count disclosure (approved cleanup: "Counts stay hidden until Details is
-- opened"). The compact banish / reroll / freeze row beside the offer heading
-- is a count, so it is on the panel only while Details is open: N2, N7, R1
-- and W1 ask that of every panel they render, and play_panel_summary S32 asks
-- it with known and unknown charge facts. This scenario asks for the other
-- half of "no room is kept for it": the heading's WORDS are fitted to the row
-- the heading really has. The heading shows the longest of the Readout's
-- forms whose line fits: beside a charges row that is the row less the 72 px
-- minimum cell and its 4 px gap; with no charges row it is the whole row. So
-- at a text size where the longest form fits the row but not the row less
-- 76 px, the closed panel shows the longer form, whole on one line, and the
-- open panel shows the shorter form beside its charges, as it always did.
-- The panel is held at its 420-unit reference width (a 640-unit screen at
-- the chosen 150% size: W1, N9), where the heading row is 400 px at every
-- native height, and the first native height of the list at which the two
-- forms differ is used. Which form each state needs is worked out here from
-- the Readout's forms, the shown line's other words and this fixture's font
-- model (Form); nothing is read from the panel's own fitting.
-- EXPECT fails at aca67cf4 by design: there the row and its cell stood with
-- Details closed, so the closed panel showed the shorter form too. GUARD:
-- the open panel is the panel aca67cf4 always showed; opening and closing
-- Details takes no game action. Native glyph widths: NOT RUN.
C.scenario('C1 with Details closed the offer heading is worded for its whole row; beside the charges of an open Details it is the shorter form, as before',function()
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local before=Effects()
 local found=false
 local ok,err=pcall(KeepDetails,function()
  UIParent:SetSize(640,4000)
  P.SetPanelScale(1.5)
  local head,charges,hover=NexusPanel._rollStatus,NexusPanel._chargesText,NexusPanel._chargesHover
  for _,height in ipairs({10,10.5,11,11.5,12,12.5,13,13.5,14,14.5,15,15.5,16,17,18,19,20}) do
   SetNative(height)
   P._playDetails=false
   local row,shown,whole,beside
   if Render(Play())==true and NexusPanel:GetWidth()==420 then
    row=NexusPanel._responsiveLayout.boxes.roll.w-4
    shown,whole=Form(head,row,false,0)
    beside=select(2,Form(head,row,false))
   end
   if shown~=nil and whole<beside then
    found=true
    local tag='C1 native '..tostring(height)..' in the 420-unit panel'
    print('OBSERVED',tag,'form for the whole row / beside the cell = '..tostring(whole)..' / '..tostring(beside),
     'closed heading "'..G.Visible(head:GetText() or '')..'" natural '..string.format('%.1f',Natural(head))..' in '..tostring(head:GetWidth()))
    C.setup(row==400,tag..': fixture: the heading row is 400 px in the 420-unit panel',row)
    -- Details closed.
    local closedHead,closedRoll,closedPanel=head:GetHeight(),NexusPanel._responsiveLayout.boxes.roll.h,NexusPanel:GetHeight()
    local none,noneDetail=NoCharges(row)
    C.expect(none and shown==whole and Natural(head)<=head:GetWidth()+0.01 and Natural(head)>row-76,
     tag..': with Details closed the heading shows the longest form that fits its whole row, whole on one line; that form does not fit the row less 76 px',
     'form '..tostring(shown)..' want '..tostring(whole)..'; natural '..string.format('%.1f',Natural(head))..' in '..tostring(head:GetWidth())..'; '..noneDetail)
    -- Details open.
    P._playDetails=true
    C.setup(Render(Play())==true and P._playDetails==true and NexusPanel:GetWidth()==420,tag..': fixture: the same panel with Details open')
    local openForm,openWant=Form(head,row,false)
    local cell=Cell(row,head,true)
    local hr,cr,area=Rect(head),Rect(charges),Rect(NexusPanel._rollArea)
    print('OBSERVED',tag,'open heading "'..G.Visible(head:GetText() or '')..'" natural '..string.format('%.1f',Natural(head))..' in '..tostring(head:GetWidth()),
     'charges "'..tostring(charges:GetText())..'" cell '..tostring(charges:GetWidth())..' want '..cell)
    C.guard(charges:IsShown() and hover:IsShown() and ChargeRows()==1 and openForm~=nil and openForm==openWant and openWant==beside and openForm>whole,
     tag..': with Details open the charges row is on the panel once, with its hover, and the heading beside it is the shorter form fitted beside the 72 px minimum cell, as before',
     'form '..tostring(openForm)..' want '..tostring(openWant)..' ('..tostring(beside)..'); the whole row takes form '..tostring(whole))
    C.guard(charges:GetWidth()==cell and head:GetWidth()==row-cell-4 and hr~=nil and cr~=nil and area~=nil and hr[3]<=cr[1]+0.01
     and G.Inside(cr,area,0.01) and (Natural(head)>row-76 or Natural(head)<=head:GetWidth()+0.01),
     tag..': the charges cell is the layout-derived '..cell..' px; the heading keeps the rest of the row less the cell and its gap and ends before the cell, inside the offer block',
     Text(hr)..' '..Text(cr)..' in '..Text(area))
    -- Details closed again.
    P._playDetails=false
    C.setup(Render(Play())==true and P._playDetails~=true and NexusPanel:GetWidth()==420,tag..': fixture: Details closed again')
    local againForm=Form(head,row,false,0)
    local again,againDetail=NoCharges(row)
    C.expect(again and againForm==whole and Natural(head)<=head:GetWidth()+0.01 and head:GetHeight()==closedHead
     and NexusPanel._responsiveLayout.boxes.roll.h==closedRoll and NexusPanel:GetHeight()==closedPanel,
     tag..': closing Details takes the charges row, its hover and its cell away again and the longer form is back; the heading row, the offer block and the panel are as they were',
     'form '..tostring(againForm)..' want '..tostring(whole)..'; '..againDetail)
    break
   end
  end
 end)
 if scale0==nil then P.ResetPanelScale() else P.SetPanelScale(scale0) end
 UIParent:SetSize(w0,h0)
 SetNative(10)
 Render(Play())
 C.setup(ok,'C1: fixture: the scenario ran',err)
 C.setup(found,'C1: fixture: a native height at which the longest heading form fits the 400 px row and not the row less the 76 px a charges row takes')
 C.guard(Effects()==before,'C1: opening and closing Details takes no game action, sends nothing and leaves Auto as it was',Effects())
 C.guard(NATIVE.nativeSets==0,'C1: no game font object is set',NATIVE.nativeSets)
end)

----------------------------------------------------------------------------
-- N8: what must not change.
----------------------------------------------------------------------------
C.scenario('N8 display-only cards, collapsed Details, header slots and the grip are unchanged',function()
 SetNative(16)
 C.setup(Render(Play())==true,'N8: fixture: the Play panel at native 16')
 local cards=NexusPanel._offerCards
 local clickable,passive,slots=false,true,true
 for i=1,3 do
  if cards[i]:GetScript('OnClick') or cards[i]:GetScript('OnMouseUp') or cards[i]:GetScript('OnMouseDown') then clickable=true end
  if cards[i]._nexusPassiveDrag~=true then passive=false end
  local slot=cards[i]._nexusSlot
  if not (type(slot)=='table' and slot.icon~=nil and slot.interior==nil and slot.edges==nil and cards[i].edges==nil) then slots=false end
 end
 C.guard(not clickable and passive,'N8: a card has no click and stays a passive drag surface')
 C.guard(slots,'N8: each row keeps its one icon slot and no icon has an outline (offer-row spacing, REG-ROW)')
 -- Main-panel visual correction: the selected row is told by an outline on
 -- its own four edges around a dark fill. The guard above also said "no
 -- outline around the row"; for the selected row that is intentionally
 -- gone. An unselected row still has neither an outline nor a ground. The
 -- selected row here is the runtime's marked offer (row 1 of this board).
 local onlySelected,selection=true,{}
 for i=1,3 do
  local shown=0
  for _,edge in ipairs(cards[i].outline or {}) do if edge:IsShown() then shown=shown+1 end end
  local filled=cards[i].fill~=nil and cards[i].fill:IsShown()
  local selected=cards[i]._nexusMarked==true
  selection[#selection+1]=i..': '..tostring(selected)..' edges '..shown..' fill '..tostring(filled)
  if selected and not (shown==4 and filled) then onlySelected=false end
  if not selected and (shown~=0 or filled) then onlySelected=false end
 end
 C.expect(onlySelected and cards[1]._nexusMarked==true and cards[2]._nexusMarked==false and cards[3]._nexusMarked==false,
  'N8: only the selected row shows its four-edge outline and its fill; the other rows show neither',table.concat(selection,'; '))
 local layout=NexusPanel._responsiveLayout
 C.guard(P._playDetails~=true and layout.boxes.planNeeded==nil and layout.boxes.needed==nil,'N8: Details stays collapsed: no count or name rows are laid out')
 local s=P.HeaderSlots()
 C.guard(s.top==7 and s.height==22 and s.gap==8 and s.edge==10 and s.closeWidth==24 and s.options==42 and s.optionsWidth==92
  and s.auto==142 and s.autoWidth==84 and s.reserved==234 and s.titleLeft==36 and s.gripX==8 and s.gripWidth==24 and s.gripHeight==24,
  'N8: the header line 1 slots and the 24 x 24 grip are unchanged')
 local grip=P.EnsureHeaderGrip()
 C.guard(grip and grip:GetWidth()==24 and grip:GetHeight()==24 and grip._nexusPassiveDrag==true and grip:GetScript('OnClick')==nil,
  'N8: the grip keeps its size and stays a passive drag surface')
 C.guard(Effects()==baselineEffects,'N8: no render, hover or font change took a game action, sent anything or changed Auto',Effects())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(native-derived owned fonts, the main panel roles and the layout-derived charges cell at synthetic native heights 12 / 16 / 20; a stated font model; native NOT RUN)')
