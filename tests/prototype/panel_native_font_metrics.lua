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
-- The approved compact panel (design draft "Nexus compact panel": 420
-- reference pixels wide, difficulty band B with its bar and ticks, inline
-- Callboard). EXPECT, failing at eef1608f by design: the reference width is
-- 284 units (the draft's 420 pixels, where the panel installed before it
-- measured 621 at 420 units x the font scale), so every width is the former
-- one x 284 / 420 at unchanged font sizes (N2, N7, N9, W1); a length the
-- draft gives in pixels is that many x 284 / 420 x the font scale units,
-- placed from the draft's own coordinates (Design, DesignY, Span, Drawn);
-- header line 1 gives each control the width its words need, and the Build
-- and Wishlist rows, their captions and their one-column buttons stand
-- where the draft draws them (N2, N7, N8, N10); the difficulty band holds
-- the tier and Soul Ash on one line beside the multiplier, above its
-- Intensity bar (N2, N7); with Auto OFF the offer heading is "Your offers"
-- with the destination in a cell of its own (N2, N3, C1); an offer row is
-- the compact row, the name and at its right end the quality, a dot and the
-- status (a selected status after its star), in one of three arrangements
-- by what its words need and never cut (RowPlan, the OfferRows helper, N3,
-- N7, W1); the setup and completion views stand in the compact body (M1).
-- The assertions of the former look that these replace are marked where
-- they stood (the 420-unit reference width and the widths it gave, the grid
-- row and its literals, the Compact A card, the fixed line-1 slots and the
-- grip's 24 units at every scale, the header rows at 8 / 32 / 54, the 8-unit
-- insets and the layout's own gaps, the fitted Auto OFF heading); they are
-- replaced by the draft's own assertions, not relaxed. GUARD, unchanged: the
-- owned fonts (10 / 12 / 14 and the 11- and 12-unit roles x the native
-- scale; no game font is set and no scale changes), the charges cell rule,
-- the count disclosure, the hovers, the passive rows and grip, and one
-- layout pass per change. Where a guard's check also held a literal of the
-- former geometry, the check is split: the part that holds before and
-- after stays a GUARD and the draft's geometry is an EXPECT beside it.
-- The N3 placement guard is given content-sized rows, as a render gives
-- them, so it cannot hold on the grid of eef1608f.
-- The typography correction (text sizes that looked uneven on the installed
-- panel). EXPECT, failing at 50f78c94 by design: the words on the panel's
-- controls are one role, the 11-unit secondary font x the native scale, a
-- step under the 12-unit names and values. In this fixture that role is seen
-- where a control is sized from its own words: header line 1 and the Build
-- and Wishlist rows' button column (Line1, N7, N8, N10: every width they pin
-- is worked out again from the same words in the same font model at the
-- role's size, none is relaxed), and in the Auto control's own font object,
-- which is a copy of that role and not of the primary one (T1). The setup
-- view's hint stands in the panel's middle, 24 design pixels or more from
-- each side, as narrow as its lines stay even without another line, and is
-- measured and drawn at that one width (M1). GUARD, unchanged: every other
-- role and size, whole names, measured heights, the gaps around the hint
-- and that nothing takes a game action. Standards R1: the role is also asked
-- of the controls themselves. The font model installed below records the
-- font object a button is given for its normal, highlight and disabled
-- states, and T1 asks, at both native sizes, that each of the nine controls
-- (Options, My Builds, Change, the two setup actions, the three footer hubs
-- and Details) was given the owned secondary font and the Auto control its
-- own font object. EXPECT, failing at 50f78c94 by design: eight of the nine
-- were given the normal font there and Details none of the panel's own.
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

-- The font object a button is given for each of its three states (Standards
-- R1). The panel gives a control's label its font through the button's own
-- three setters, by the owned font's name or, for the Auto control, by that
-- control's own font object. Install records what each setter is given, on
-- the widget it is given to (its _buttonFonts: normal, highlight, disabled;
-- the last one given stands), and then does whatever this harness did for
-- that setter before: nothing, where it had none. Nothing else of the model
-- follows the record: no label takes its face from it and no width or
-- height is measured from it. RECORDER keeps the three recording functions,
-- so a check can state that the widget it reads is one whose setters are
-- the recorded ones.
local BUTTON_FONT={SetNormalFontObject='normal',SetHighlightFontObject='highlight',SetDisabledFontObject='disabled'}
local RECORDER={}

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
 for setter,state in pairs(BUTTON_FONT) do
  -- What the harness answers for this setter today, if anything: read as a
  -- widget reads it (a method table may answer through an index of its
  -- own), protected, and called after the record with what it was given.
  local ok,had=pcall(function() return m[setter] end)
  if not (ok and type(had)=='function') then had=nil end
  RECORDER[setter]=function(self,font,...)
   if type(self)=='table' then
    local given=rawget(self,'_buttonFonts')
    if type(given)~='table' then given={};rawset(self,'_buttonFonts',given) end
    given[state]=font
   end
   if had then return had(self,font,...) end
  end
  m[setter]=RECORDER[setter]
 end
 -- G1 (v22): a texture placed with SetAllPoints covers what it was given
 -- (its parent when given nothing). The harness has no SetAllPoints; it is
 -- recorded here on the region (_allPointsTo) and nothing else: it adds no
 -- anchor, so every rectangle the checks above resolve stays as it was.
 -- ClearAllPoints forgets the record, as it forgets every anchor.
 local clearAll=m.ClearAllPoints
 m.ClearAllPoints=function(self,...)
  if type(self)=='table' then rawset(self,'_allPointsTo',nil) end
  return clearAll(self,...)
 end
 local hadAll=rawget(m,'SetAllPoints')
 m.SetAllPoints=function(self,rel,...)
  if type(self)=='table' then
   if type(rel)=='string' then rel=_G[rel] end
   rawset(self,'_allPointsTo',type(rel)=='table' and rel or self:GetParent() or false)
  end
  if hadAll then return hadAll(self,rel,...) end
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
-- The approved compact panel (design draft "Nexus compact panel", difficulty
-- B with its bar and ticks, inline Callboard). The draft is drawn in
-- reference pixels and is 420 of them wide, where the panel installed before
-- it measured 621 under the same width rule (420 units x the font scale).
-- So the reference width is 420 x 420 / 621 = 284 units, and one design
-- pixel is 284 / 420 units x the font scale. Stated here from the draft:
-- nothing below reads a length from the layout engine or the panel's own
-- metrics. No font is made smaller for it (T1, W1).
local BASE=284
local function Unit() return BASE/420*Scale() end
-- A length the draft gives in reference pixels, in whole units (1 at least).
local function Design(px) return math.max(1,math.floor(px*Unit()+0.5)) end
-- A place the draft gives from the panel's top, in whole units; and a block
-- or gap it draws between two such places.
local function DesignY(px) return math.floor(px*Unit()+0.5) end
local function Span(from,to) return DesignY(to)-DesignY(from) end
-- A gap or block the draft draws `px` high further down, under blocks that
-- may have grown: where it stands decides whether it rounds down or up.
local function Drawn(px,units) return units==math.floor(px*Unit()) or units==math.ceil(px*Unit()) end
-- The body's side inset (the 1-pixel edge and 6), the drag grip (the draft's
-- 24 pixels, and never under 24 x 24 units) and header line 1's row (the
-- draft's 22 pixels, never under the grip less the pixel it stands out above
-- and below).
local function Inset() return Design(7) end
local function Grip() return math.max(24,Design(24)) end
local function TitleRow() return math.max(Span(5,27),Grip()-2*Design(1)) end
-- The panel's width for the native scale, as the rule is stated: the
-- reference width x the font scale (1 to 2), no wider than the screen
-- leaves at the chosen size (the screen's width less the 24-unit fit margin,
-- over the chosen size; a screen under 640 units bounds nothing, as for the
-- fit), and never under the reference width.
local function WantWidth()
 local want=math.floor(BASE*Scale()+0.5)
 local screen=tonumber(UIParent:GetWidth())
 if screen and screen>=640 and screen<math.huge then want=math.min(want,math.floor((screen-24)/P.PanelScale())) end
 return math.max(BASE,want)
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
-- Words on one line in a role of this fixture's font model.
local function Wide(words,kind) return G.Length(G.Visible(words))*CHAR*Role(kind) end
-- The room around the words of a button whose label is held inside the
-- button's end caps (Options; My Builds and Change): the draft's 14 pixels,
-- and never under 14 units, which are the label's two 6-unit end caps and 2
-- to spare (so such a label is never cut by its own button at a text scale
-- where 14 design pixels are fewer units: under about 1.5).
local function LabelRoom() return math.max(Design(14),14) end
-- Header line 1 as the draft sizes it, from the controls' own words: Close
-- 24 pixels, Options its shown label and its room (LabelRoom), the Auto
-- control the widest of its three labels and 16 (never under the 12 units
-- its label fit keeps clear), each held to three tenths of the panel, the
-- three 6 apart; the title from 6 after the grip to 6 before the Auto
-- control.
-- Typography correction: the words on a control are the panel's 11-unit
-- secondary role (CONTROL), a step under the names and values, so a control
-- is as wide as its words are in that role. EXPECT: these widths were worked
-- out with the words in the 12-unit 'normal' role, which the controls had.
local CONTROL='secondary'
local function Line1()
 local limit=math.floor(NexusPanel:GetWidth()*0.3)
 local widest=0
 for _,key in ipairs({'panel.button.auto_on','panel.button.auto_off','panel.button.auto_unknown'}) do
  widest=math.max(widest,Wide((Nexus.Localization.Text(key)),CONTROL))
 end
 local s={edge=Inset(),close=Design(24),gap=Design(6),grip=Grip(),height=Design(22)}
 s.options=math.min(limit,math.ceil(Wide(NexusPanel._menuBtn:GetText() or '',CONTROL))+LabelRoom())
 s.auto=math.min(limit,math.ceil(widest)+math.max(Design(16),12))
 s.reserved=s.edge+s.close+s.gap+s.options+s.gap+s.auto+s.gap
 s.titleLeft=s.edge+s.grip+s.gap
 return s
end
-- The compact offer heading while the player chooses (Auto OFF, offers
-- shown): "Your offers", and at the right end of its row the destination in
-- a cell of its own, after a dot while the charges stand before it. What the
-- row keeps for that cell: its words in the secondary role and the draft's
-- 10 pixels before them. `slot` is this fixture's Saved Build slot.
local function Destination(open,slot)
 return (open and '\194\183 ' or '')..(Nexus.Localization.Format('panel.label.slot_number',{slot=tostring(slot or 2)}))
end
local function DestinationRoom(open,slot) return math.ceil(Wide(Destination(open,slot),'secondary'))+Design(10) end
-- One offer row as the draft arranges it, worked out from the row's own
-- words in this fixture's font model; nothing is read from the panel's own
-- arrangement. The text column is the row less its 6-pixel insets, the
-- 24-pixel icon and the 8 after it. At the row's right end stands the
-- phrase: the quality, a dot (5 pixels either side of it) and the status, a
-- selected row's status after its 12-pixel star and 4. Three arrangements:
--   inline: the name, the draft's 10 pixels and the phrase fit the column on
--   one line (the draft's 28-pixel row);
--   under: otherwise the name has the column, wrapping there, and the phrase
--   stands on a line of its own under it (24 pixels more);
--   split: a phrase wider than the column stands as its two parts under the
--   name, the quality and under it the status, without the dot (24 pixels
--   for each), a part wider than the column (the status: than the column
--   less its star) wrapping there.
-- `need` is what the row's content needs in units (the 2-pixel pads above
-- and below; a line under the name is never under the draft's 24 pixels)
-- and `pixels` the draft's own height for the arrangement.
local function RowPlan(card,width)
 local function High(text,room)
  local _,size=text:GetFont()
  return math.max(1,G.Rows(text:GetText() or '',room,CHAR*size))*math.ceil(size*LINE)
 end
 local p={column=width-(Design(6)+Design(24)+Design(8))-Design(6)}
 p.qualityW=(card.quality:GetText() or '')~='' and math.ceil(Natural(card.quality)) or 0
 p.tagW=(card.tag:GetText() or '')~='' and math.ceil(Natural(card.tag)) or 0
 p.selected=card._nexusMarked==true or (card.fill~=nil and card.fill:IsShown())
 -- (The dot is one character of the secondary role in this model.)
 p.dotW=(p.qualityW>0 and p.tagW>0) and (2*Design(5)+math.ceil(Wide('\194\183','secondary'))) or 0
 p.starW=(p.tagW>0 and p.selected) and (Design(12)+Design(4)) or 0
 p.phrase=p.qualityW+p.dotW+p.starW+p.tagW
 p.inline=p.phrase==0 or math.ceil(Natural(card.name))+Design(10)+p.phrase<=p.column
 p.split=p.phrase>p.column
 local one=100000
 local qualityLine=p.qualityW>0 and High(card.quality,one) or 0
 local tagLine=p.tagW>0 and High(card.tag,one) or 0
 local under,lines=0,0
 if p.split then
  if p.qualityW>0 then under,lines=under+math.max(Design(24),High(card.quality,p.column)),lines+1 end
  if p.tagW>0 then under,lines=under+math.max(Design(24),High(card.tag,p.column-p.starW)),lines+1 end
 elseif not p.inline then
  under,lines=math.max(Design(24),qualityLine,tagLine),1
 end
 p.need=2*Design(2)+(p.inline and math.max(High(card.name,one),qualityLine,tagLine) or High(card.name,p.column))+under
 p.pixels=28+24*lines
 return p
end

-- Revision 2, R1. The charges cell for a shown heading, derived here from
-- the native scale, the heading row (the roll width less 4) and the heading's
-- own line; nothing is read from the panel. 72 px at scale 1; above it 72 px
-- x the scale, in the room the heading leaves after the 4 px gap, and never
-- under 72 px. A fitted offer heading needs its measured line. Any other
-- heading also needs the conservative model (0.70 em of the 10 px small size
-- x the scale, at least 7 px, per visible character), as its row held before.
-- Root's v9 ruling on the charges cell (SPEC-A2: "allocate enough measured
-- right-cell width for whole charges/slot on one line when physically
-- available; left text can wrap"). EXPECT: the rule that stood here was the
-- one above (Cell(row,head,fitted): 72 px x the scale, in the room the
-- heading's own line left, a heading that is not a fitted form also keeping
-- its line under the conservative model). The cell is now the row of
-- counts' own one-line width in its own font (`natural`, stated by each
-- caller from the row's words and this fixture's font model), in whole
-- units, never under 72 px, and no wider than the row leaves once the
-- heading keeps, after the 4 px gap, the 72 px a cell always had. Derived
-- here from those numbers; nothing is read from the panel.
local function Cell(row,natural)
 return math.max(72,math.min(math.ceil(natural),row-4-72))
end
-- The form a fitted offer heading must show: the longest of the Readout's
-- forms whose whole line fits the row less what the row keeps for a charges
-- row (`reserve`), else the shortest. Returns the index shown and the index
-- that rule gives.
-- Count disclosure (C1): `reserve` is the charges cell and its 4 px gap,
-- given by each caller for the row of counts beside the heading (v9: the
-- cell above; it was the 76 px of the 72 px minimum cell and its gap, the
-- default that still stands here for a caller that gives none); 0 for a
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
 local fonts,rows,inside,ordered,apart,whole,sixth,hover,held=true,true,true,true,true,true,true,true,true
 local statusWhole,nameWhole=true,true
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
  -- The approved compact row (RowPlan above states it): which of its three
  -- arrangements a row needs is worked out there from the row's words and
  -- this fixture's font model. The order this helper held before was the
  -- two-line grid (the quality under its name, the tag in a status column);
  -- that grid is intentionally gone, so its order is replaced by the compact
  -- row's here.
  local qr,gr=Rect(card.quality),Rect(card.tag)
  local tagText=card.tag:GetText() or ''
  if nr and cr then
   local plan=RowPlan(card,cr[3]-cr[1])
   local content,qualityW,tagW,starW=plan.column,plan.qualityW,plan.tagW,plan.starW
   local left,right=cr[1]+Design(6)+Design(24)+Design(8),cr[3]-Design(6)
   local dotShown=card.dot~=nil and card.dot:IsShown() and true or false
   local starShown=card.star~=nil and card.star:IsShown() and true or false
   local sr=starShown and Rect(card.star) or nil
   if not plan.split then
    -- The phrase on one line, ending at the row's right inset, its parts
    -- left to right: quality, dot, star, status.
    local last=tagW>0 and gr or qr
    if plan.phrase>0 and not (last and math.abs(last[3]-right)<=0.01) then
     ordered=false;notes[#notes+1]=i..' phrase ends at '..Text(last)..' in '..Text(cr)
    end
    if qualityW>0 and tagW>0 and not (qr and gr and qr[3]<=gr[1]+0.01 and math.abs(qr[2]-gr[2])<=0.01
     and dotShown and Near(Size(card.dot),small)) then
     ordered=false;notes[#notes+1]=i..' quality '..Text(qr)..' then tag '..Text(gr)
    end
    local first=qualityW>0 and qr or gr
    if plan.phrase>0 and plan.inline and not (first and first[1]>=nr[3]-0.01 and math.abs(first[2]-nr[2])<=0.01) then
     ordered=false;notes[#notes+1]=i..' phrase '..Text(first)..' beside name '..Text(nr)
    end
    if plan.phrase>0 and not plan.inline and not (first and first[2]>=nr[4]-0.01) then
     ordered=false;notes[#notes+1]=i..' phrase '..Text(first)..' under name '..Text(nr)
    end
   else
    -- The phrase as its two parts under the name, without the dot: each
    -- ends at the row's right inset; on one line it is as wide as its
    -- words, and a part wider than the column (the status: than the column
    -- less its star) starts at the column's left (the status after its
    -- star) and wraps there.
    if dotShown then ordered=false;notes[#notes+1]=i..' dot shown in a split phrase' end
    if qualityW>0 and not (qr and qr[2]>=nr[4]-0.01 and math.abs(qr[3]-right)<=0.01
     and ((qualityW<=content and card.quality:GetWidth()>=qualityW-0.01)
      or (qualityW>content and math.abs(qr[1]-left)<=0.01))) then
     ordered=false;notes[#notes+1]=i..' quality '..Text(qr)..' under name '..Text(nr)
    end
    local above=qualityW>0 and qr or nr
    if tagW>0 and not (gr and above and gr[2]>=above[4]-0.01 and math.abs(gr[3]-right)<=0.01
     and ((tagW<=content-starW and card.tag:GetWidth()>=tagW-0.01)
      or (tagW>content-starW and math.abs(gr[1]-(left+starW))<=0.01))) then
     ordered=false;notes[#notes+1]=i..' status '..Text(gr)..' under '..Text(above)
    end
   end
   -- The star: shown exactly for a selected status, in place of the
   -- code-owned mark before its words, and standing right before them.
   if starShown~=(starW>0) or (starW>0 and tagText:sub(1,2)=='> ')
    or (starW>0 and not (sr and gr and sr[3]<=gr[1]+0.01 and sr[1]>=gr[1]-starW-0.01 and sr[2]>=gr[2]-0.01 and sr[4]<=gr[4]+0.01)) then
    ordered=false;notes[#notes+1]=i..' star shown='..tostring(starShown)..' '..Text(sr)..' selected='..tostring(plan.selected)..' tag "'..tagText..'" '..Text(gr)
   end
   -- The two guards this helper held, as they were (they hold in the grid
   -- and in the compact row): the room the text and status columns share is
   -- from the name's left, after the icon square and its gap, to the last
   -- text's right; a tag no wider than half of it is whole, and the name
   -- keeps a sixth of it or its whole text.
   local rest=(edge or cr[3])-nr[1]
   if tagText~='' and Natural(card.tag)<=math.floor(rest/2) and card.tag:GetWidth()<math.ceil(Natural(card.tag))-0.01 then
    whole=false;notes[#notes+1]=i..'.tag box='..tostring(card.tag:GetWidth())..' natural='..tostring(Natural(card.tag))
   end
   -- A name shorter than a sixth is whole and gives its idle room to the status words (offer-row spacing).
   if card.name:GetWidth()<math.min(math.floor(rest/6),math.ceil(Natural(card.name)))-0.01 then sixth=false end
   -- The compact row gives more: a status no wider than the text column,
   -- less its star, is whole on one line (beside its quality, or on a line
   -- of its own in a split phrase).
   if tagW>0 and tagW<=content-starW and card.tag:GetWidth()<tagW-0.01 then
    statusWhole=false;notes[#notes+1]=i..'.status box='..tostring(card.tag:GetWidth())..' natural='..tostring(Natural(card.tag))
   end
   -- And the name is whole: on one line beside the phrase (a box at least
   -- its words), or across the whole text column when the phrase is under
   -- it.
   if plan.inline and card.name:GetWidth()<math.ceil(Natural(card.name))-0.01 then nameWhole=false end
   if not plan.inline and math.abs(card.name:GetWidth()-content)>0.01 then nameWhole=false end
   -- Nothing is cut: the row is as tall as its content needs (never under
   -- that, and the draft's own height for its arrangement when the content
   -- needs no more), and every text's box holds the lines it shows.
   if card:GetHeight()<plan.need-0.01 then held=false;notes[#notes+1]=i..' row '..tostring(card:GetHeight())..' needs '..plan.need end
   for _,key in ipairs({'name','quality','tag'}) do
    local text=card[key]
    if (text:GetText() or '')~='' and text:GetHeight()+0.5<text:GetStringHeight() then
     held=false;notes[#notes+1]=i..'.'..key..' box '..tostring(text:GetHeight())..' for '..tostring(text:GetStringHeight())
    end
   end
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
 -- EXPECT: the approved compact row (it fails at eef1608f, where a row was
 -- the name over its quality with the tag in a status column).
 C.expect(ordered,tag..': each row is the compact row: the name, and at its right end the quality, a dot and the status (the star before a selected status), on the name\'s line while they fit it, else under it, a phrase wider than the column as its two parts',detail)
 C.guard(whole,tag..': a tag no wider than half the row is whole',detail)
 C.guard(sixth,tag..': the name keeps at least a sixth of the row, or its whole text when that is shorter',detail)
 -- EXPECT (the compact row; at eef1608f a tag wider than its status column
 -- and a name wider than its own column were held to those columns).
 C.expect(statusWhole,tag..': a status no wider than the text column, less its star, is whole on one line',detail)
 C.expect(nameWhole,tag..': the name is whole: on one line beside the phrase, or across the text column with the phrase under it',detail)
 -- EXPECT: at eef1608f a row was the grid's two lines whatever its words
 -- needed there unless the layout was given measured rows.
 C.expect(held,tag..': no offer text is cut: every row is as tall as its content needs and every text box holds its lines',detail)
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
 C.expect(wantWidth>BASE and NexusPanel:GetWidth()==wantWidth and layout.width==wantWidth,
  tag..': the panel is as wide as its text scale asks ('..wantWidth..' units), not the reference '..BASE,NexusPanel:GetWidth())
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
 -- wide as its whole row. The approved compact heading: that row is the
 -- offer block's whole width (the heading and the rows start at the body's
 -- own inset; the former 2-unit insets are gone) less the destination cell
 -- at its right end (DestinationRoom; Auto is OFF here, so no disclosure
 -- shares the row). At aca67cf4 the charges row stood here whatever Details
 -- was. The checks of that row and its cell below are made with Details
 -- open, where the row stands, and Details is then closed again for the
 -- header and the difficulty band.
 local closedHead,closedRoll,closedPanel=head:GetHeight(),layout.boxes.roll.h,NexusPanel:GetHeight()
 local none,noneDetail=NoCharges((area[3]-area[1])-DestinationRoom(false))
 C.expect(none,tag..': with Details closed there is no charges row, hover or cell: the heading has its whole row',noneDetail)
 -- The compact heading and its destination cell, whole (EXPECT: at eef1608f
 -- the heading was the Readout's fitted form with the Auto state and the
 -- destination after it in one text).
 local slotCell=NexusPanel._offerSlot
 local slotRect,headClosed=slotCell and Rect(slotCell) or nil,Rect(head)
 C.expect(G.Visible(head:GetText() or '')==(Nexus.Localization.Text('panel.heading.your_offers'))
  and slotCell~=nil and slotCell:IsShown() and G.Visible(slotCell:GetText() or '')==Destination(false)
  and Near(Size(slotCell),small) and slotRect~=nil and headClosed~=nil and math.abs(slotRect[3]-area[3])<=0.01
  and headClosed[3]<=slotRect[1]-Design(10)+0.01 and slotCell:GetWidth()+0.01>=Natural(slotCell)
  and Natural(head)<=head:GetWidth()+0.01,
  tag..': the heading says "Your offers", whole, and the destination stands at the right end of its row in a cell of its own, whole',
  '"'..G.Visible(head:GetText() or '')..'" '..Text(headClosed)..' / "'..tostring(slotCell and slotCell:GetText())..'" '..Text(slotRect))
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
 -- (The row the heading and the cell share: the offer block's width less
 -- the destination cell, which now follows the charges after a dot.)
 -- v9 (Root's ruling SPEC-A2): the cell is the row of counts' own one-line
 -- width, in the room the row has for it (Cell); the heading keeps the rest
 -- and wraps there when it must. EXPECT: the cell was the scaled one in the
 -- room the fitted heading left (Cell(row,head,true)).
 local row=(area[3]-area[1])-DestinationRoom(true)
 local cell=Cell(row,Natural(charges))
 local cellDetail='cell '..tostring(charges:GetWidth())..' want '..cell..'; heading box '..tostring(head:GetWidth())..' want '..(row-cell-4)
  ..'; charges natural '..string.format('%.1f',Natural(charges))..'; heading natural '..string.format('%.1f',Natural(head))
 print('OBSERVED',tag,'heading natural='..string.format('%.1f',Natural(head)),'box='..tostring(head:GetWidth()),
  'derived cell='..cell)
 C.expect(charges:GetHeight()>=small-0.01 and charges:GetHeight()+0.5>=charges:GetStringHeight(),
  tag..': the charges cell is as tall as the font it holds and as its measured lines',
  tostring(charges:GetHeight())..' for '..tostring(charges:GetStringHeight()))
 -- The guard that stood here asked for the Readout's form fitted beside
 -- the 72 px minimum cell. With Auto OFF the approved heading has one form,
 -- "Your offers", in both Details states, and the destination cell says
 -- the slot after the charges; the fitted forms are asked where they still
 -- stand, with Auto ON (C1).
 local openSlot=NexusPanel._offerSlot
 local openSlotRect=openSlot and Rect(openSlot) or nil
 C.expect(G.Visible(head:GetText() or '')==(Nexus.Localization.Text('panel.heading.your_offers'))
  and openSlot~=nil and openSlot:IsShown() and G.Visible(openSlot:GetText() or '')==Destination(true)
  and openSlotRect~=nil and chargesRect~=nil and chargesRect[3]<=openSlotRect[1]+0.01 and math.abs(openSlotRect[3]-area[3])<=0.01,
  tag..': with Details open the heading still says "Your offers" and the destination follows the charges after a dot, at the row\'s right end',
  '"'..G.Visible(head:GetText() or '')..'" / "'..tostring(openSlot and openSlot:GetText())..'" '..Text(openSlotRect))
 -- Where the derived cell is wider than 72 px this fails before revision 2.
 ;(cell>72 and C.expect or C.guard)(charges:GetWidth()==cell and head:GetWidth()==row-cell-4,
  tag..': the charges cell is the layout-derived '..cell..' px and the heading keeps the rest of the row less the cell and its gap',cellDetail)
 -- v9: the row of counts has its own one-line width whenever the row can
 -- hold it beside the 72 px the heading keeps, and is then on one line,
 -- whole (EXPECT: above scale 1 the cell was the scaled one, and a row
 -- wider than it wrapped). By this fixture's arithmetic its short row of
 -- counts is narrower than that room at every height it sweeps, so the
 -- second branch is not expected to run here (NOT RUN by the author); it
 -- stays for a row of counts wider than the room, which wraps whole in the
 -- room it gets. A long row of counts is stated in terminology_consumers.
 if math.ceil(Natural(charges))<=row-76 then
  C.expect(cell==math.max(72,math.ceil(Natural(charges))) and Natural(charges)<=charges:GetWidth()+0.01
   and charges:GetHeight()+0.5>=charges:GetStringHeight() and charges:GetStringHeight()<=math.ceil(Size(charges)*LINE)+0.01,
   tag..': the charges row has its own one-line width in the row and is whole on one line in its cell',
   cellDetail..'; box '..tostring(charges:GetHeight())..' for text '..tostring(charges:GetStringHeight()))
 else
  -- No room for the row on one line beside the heading's 72 px: the row
  -- keeps the room it gets and wraps in it, in a box as tall as its lines
  -- need; it is not shortened (approved panel cleanup). The cell's width
  -- is checked above.
  C.expect(charges:GetWidth()==cell and Natural(charges)>charges:GetWidth()
   and charges:GetHeight()+0.5>=charges:GetStringHeight(),
   tag..': with no room on one line beside the heading the charges row wraps whole in its derived cell',
   cellDetail..'; box '..tostring(charges:GetHeight())..' for text '..tostring(charges:GetStringHeight()))
 end
 -- The heading beside the cell. GUARD: a heading that fitted beside the
 -- 72 px minimum was whole beside the cell (the cell took only the room the
 -- heading left). v9: the cell comes first, so the heading is whole on its
 -- line where its line fits the box it keeps, and otherwise wraps there in
 -- a box as tall as its lines; it is never shortened. (EXPECT for the
 -- second branch: at eef1608f a heading wider than its box was shortened by
 -- the client.)
 if Natural(head)<=row-cell-4 then
  C.guard(Natural(head)<=head:GetWidth()+0.01,tag..': a heading whose line fits beside the charges cell is whole on its line',cellDetail)
 else
  C.expect(head:GetHeight()+0.5>=head:GetStringHeight() and head:GetStringHeight()>math.ceil(Size(head)*LINE),
   tag..': a heading wider than the box it keeps beside the charges cell wraps there, whole, in a box as tall as its lines',
   cellDetail..'; box '..tostring(head:GetHeight())..' for text '..tostring(head:GetStringHeight()))
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
 local again,againDetail=NoCharges((area[3]-area[1])-DestinationRoom(false))
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
 -- The approved compact header: the title starts 6 design pixels after the
 -- grip, which stands at the body's inset, on line 1, 5 pixels under the
 -- panel's top (EXPECT: at eef1608f it stood at 36, 8, which this guard
 -- asked for).
 C.expect(rects[1] and rects[1][1]==Inset()+Grip()+Design(6) and rects[1][2]==DesignY(5),
  tag..': the title stands 6 design pixels after the grip on header line 1, 5 pixels under the top',Text(rects[1]))
 -- Independent Spec review, required finding 2 (no fixed-height text
 -- container): the title's box is line 1's row while the text needs no
 -- more (the draft's 22 pixels, never under the grip less the pixel it
 -- stands out above and below: TitleRow), and the text's own measured
 -- height when it needs more; the rows under it start lower by the
 -- difference (N10). It was a literal 20-unit line at eef1608f.
 local titleNeeds=math.max(TitleRow(),math.ceil(lines[1]:GetStringHeight()))
 C.expect(lines[1]:GetHeight()==titleNeeds,
  tag..': the title\'s box is as tall as its text needs, at least header line 1\'s row',tostring(lines[1]:GetHeight())..' / '..tostring(titleNeeds))
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
    and cr2 and cr2[1]==Inset() and math.abs(cr2[2]-rects[i+1][2])<=0.01 and cr2[3]<=rects[i+1][1]+0.01
    and cap:GetWidth()+0.5>=cap:GetStringWidth()
    and G.Visible(name:GetText() or '')~='' and G.Visible(name:GetText() or ''):sub(1,#label)~=label) then capOk=false end
  end
  C.expect(capOk and rects[2] and rects[3] and rects[2][1]==rects[3][1] and rects[2][1]>Inset()
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
 -- The difficulty band (the approved compact panel, presentation B): the
 -- tier and the multiplier are primary text and Soul Ash is the 11-unit
 -- secondary role, as on the card before it. The tier and the multiplier
 -- start at one top.
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
 -- The band's one text line (EXPECT: at eef1608f Soul Ash stood on a line of
 -- its own under the tier, which this guard asked for): the tier, then Soul
 -- Ash to its right on the same line, both left of the multiplier, with the
 -- Intensity bar under that line across the band (the draft's 4 pixels
 -- high, 3 above the band's inner edge). The band is the draft's 34 pixels
 -- while its line holds the text, and as tall as its text line needs with
 -- its insets and bar when that is more (in this model a primary line is
 -- 1.15 em).
 local line=math.max(tier:GetStringHeight(),ash:GetStringHeight())
 local around=2*Design(3)+Design(1)+Design(4)+Design(3)
 C.expect(cardRect and tierRect and ashRect and gainRect and G.Inside(tierRect,cardRect,0.01) and G.Inside(ashRect,cardRect,0.01)
  and G.Inside(gainRect,cardRect,0.01) and ashRect[1]>=tierRect[3]-0.01 and math.abs(ashRect[2]-tierRect[2])<=0.01
  and ashRect[3]<=gainRect[1]+0.01 and G.Apart(tierRect,gainRect)
  and bar and bar[2]>=math.max(tierRect[4],ashRect[4])-0.01 and (bar[4]-bar[2])==Design(4)
  and math.abs((cardRect[4]-bar[4])-(Design(3)+Design(3)))<=0.01
  and card:GetHeight()==layout.boxes.status.h
  and (card:GetHeight()==around+line or (around+line<=card:GetHeight() and Drawn(34,card:GetHeight()))),
  tag..': the band holds the tier and Soul Ash on one line beside the multiplier, above its Intensity bar; it is the draft\'s 34 pixels or as tall as its line needs',
  statusDetail..' bar '..Text(bar)..' line '..tostring(line)..' around '..tostring(around))

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
 local spec={width=272,fontScale=fontScale,uiScale=uiScale,revision=revision,activeRoll=true,
  statusVisible=true,cardRows=true}
 local layout=LM.Panel(spec)
 local box=layout.boxes.roll
 local area=NexusPanel._rollArea
 local lines={}
 for i,card in ipairs(LONG) do lines[i]=card.text end
 local rendered=P.RenderOfferCards(lines,R.MarkedCard(LONG),false,true,nil,nil)==true
 -- The approved compact rows are as tall as their content, so a render
 -- gives the layout each row's need and the draft's height for its
 -- arrangement (spec.offerRowsH, spec.offerRowsPx) before it places the
 -- rows. Here both are worked out from the rows' own words in this
 -- fixture's font model (RowPlan), at the offer block's width (the rows
 -- have no inner inset now: the placement is given 0 where it was given 2),
 -- and the real layout and placement then run with them. At eef1608f the
 -- rows were the grid's two lines whatever the words needed, and the layout
 -- was asked without them.
 local needs,drawn={},{}
 for i=1,3 do
  local plan=RowPlan(NexusPanel._offerCards[i],box.w)
  needs[i],drawn[i]=plan.need,plan.pixels
 end
 spec.offerRowsH,spec.offerRowsPx=needs,drawn
 layout=LM.Panel(spec)
 box=layout.boxes.roll
 -- The roll area takes the narrow box (the panel itself never asks for one
 -- this narrow: it is 284 units wide at least).
 area:ClearAllPoints();area:SetPoint('TOPLEFT',NexusPanel,'TOPLEFT',box.x,-box.y);area:SetSize(box.w,box.h)
 C.setup(rendered and P.PlaceOfferCards(layout,box,0)=='rows',
  tag..': fixture: the real card render and placement ran at the narrow box')
 -- The layout holds each row at its content's need, or at the draft's own
 -- height for its arrangement when the content needs no more.
 local tall,tallNotes=type(layout.offerRowHeights)=='table',{}
 for i=1,3 do
  local got=tall and layout.offerRowHeights[i] or nil
  tallNotes[#tallNotes+1]=tostring(got)..' (need '..needs[i]..', drawn '..drawn[i]..' px)'
  if not (got and got>=needs[i] and (got==needs[i] or Drawn(drawn[i],got))) then tall=false end
 end
 C.expect(tall,tag..': the layout gives each row its content\'s need, or the draft\'s height for its arrangement when that is more',
  table.concat(tallNotes,'; '))
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
 -- functions (the panel itself lays out at 284 units or wider): the Play
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
 -- The approved compact heading row: the offer block's whole width (no
 -- inner insets). With Auto OFF the heading is "Your offers" and the
 -- destination has a cell of its own at the row's right end, after a dot
 -- while a charges line stands before it, so the heading and the charges
 -- cell share the row less that cell (DestinationRoom). A preview heading
 -- (Auto unknown) keeps the Readout's fitted forms and says its destination
 -- itself: no cell, the whole row.
 -- v9 (Root's ruling SPEC-A2): the cell is the row of counts' own one-line
 -- width in the room the row has for it (Cell, from `chargeNatural`), and a
 -- fitted heading is the longest form that fits beside that cell. The panel
 -- holds no row of counts here, so the cell function is given the same row
 -- of counts the heading function is given (its third argument; EXPECT: it
 -- took the heading and read the form fitted beside the 72 px minimum).
 for _,case in ipairs({{'slot heading',false,2},{'preview heading',nil,0}}) do
  P.SetOfferHeading(head,{auto=case[2],_nexusChargeLine=chargeLine},case[3],layout)
  local compact=case[2]==false
  local row=box.w-(compact and DestinationRoom(true,case[3]) or 0)
  local cell=Cell(row,chargeNatural)
  local actual=type(P.ChargesCell)=='function' and P.ChargesCell(layout,head,chargeLine) or 72
  local shownForm,wantForm=Form(head,row,case[2],cell+4)
  local slotCell=NexusPanel._offerSlot
  local detail='cell '..tostring(actual)..' want '..cell..'; row '..row..'; heading "'..G.Visible(head:GetText() or '')..'" natural '
   ..string.format('%.1f',Natural(head))..'; charges natural '..string.format('%.1f',chargeNatural)
   ..'; destination "'..tostring(slotCell and slotCell:IsShown() and slotCell:GetText() or '')..'"'
  print('OBSERVED',tag,case[1],detail,'form='..tostring(shownForm)..'/'..tostring(wantForm))
  if compact then
   -- EXPECT: at eef1608f this heading was the Readout's form fitted beside
   -- the cell, with the Auto state and the slot after it in the same text.
   C.expect(G.Visible(head:GetText() or '')==(Nexus.Localization.Text('panel.heading.your_offers'))
    and slotCell~=nil and slotCell:IsShown() and G.Visible(slotCell:GetText() or '')==Destination(true,case[3]),
    tag..', '..case[1]..': the heading is "Your offers" and the destination cell says the slot after the charges',detail)
  else
   -- (GUARD while the cell is the 72 px minimum, where this is the form
   -- fitted beside it, as before; EXPECT beside a wider cell.)
   local asked=cell>72 and C.expect or C.guard
   asked(shownForm~=nil and shownForm==wantForm and not (slotCell and slotCell:IsShown()),
    tag..', '..case[1]..': the longest form that fits beside the charges cell is shown, with no destination cell',detail)
  end
  ;(cell>72 and C.expect or C.guard)(actual==cell,tag..', '..case[1]..': the charges cell is the layout-derived '..cell..' px',detail)
  -- (The guard that stood here also asked that a heading fitted beside the
  -- 72 px minimum stayed whole beside the cell. The cell no longer follows
  -- the heading: the form is fitted beside the cell itself, checked above,
  -- and what the cell must leave is the heading's 72 px.)
  C.guard(actual>=72 and actual+4<=row,tag..', '..case[1]..': the cell is never under 72 px and stays in the row',detail)
  C.expect((row-actual-4>=72 or actual==72) and (chargeNatural>row-76 or chargeNatural<=actual+0.01),
   tag..', '..case[1]..': the cell leaves the heading its 72 px and holds on one line a row of counts that fits the row beside them',detail)
  -- Count disclosure (C1): with Details closed the render gives no charges
  -- line, and the heading is worded for its whole row: the longest form
  -- whose line fits the row itself, never a shorter one than beside the
  -- cell. GUARD: the heading function already fitted a heading without a
  -- charges line to the whole row; what is new is that a render with
  -- Details closed gives it none (N2, N7, R1, W1, and C1 where the two
  -- forms differ on the panel itself).
  P.SetOfferHeading(head,{auto=case[2],_nexusChargeLine=''},case[3],layout)
  if compact then
   -- The same words whatever stands beside them; the destination cell has
   -- no dot with no charges before it.
   C.expect(G.Visible(head:GetText() or '')==(Nexus.Localization.Text('panel.heading.your_offers'))
    and slotCell~=nil and slotCell:IsShown() and G.Visible(slotCell:GetText() or '')==Destination(false,case[3]),
    tag..', '..case[1]..': with no charges line the heading is the same "Your offers" and the destination cell has no dot',
    '"'..G.Visible(head:GetText() or '')..'" / "'..tostring(slotCell and slotCell:GetText())..'"')
  else
   local wholeForm,wholeWant=Form(head,row,case[2],0)
   C.guard(wholeForm~=nil and shownForm~=nil and wholeForm==wholeWant and wholeForm<=shownForm,
    tag..', '..case[1]..': with no charges line the heading is the form fitted to its whole row, never shorter than beside the cell',
    'form '..tostring(wholeForm)..' want '..tostring(wholeWant)..'; beside the cell '..tostring(shownForm)..'; "'..G.Visible(head:GetText() or '')
    ..'" natural '..string.format('%.1f',Natural(head))..' in a row of '..row)
  end
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
 -- (The selected row shows its tag's words after its star, in place of the
 -- code-owned mark before them; an unselected tag is shown as it is.)
 C.setup(R.OFFER_PICK_TAG:sub(1,2)=='> ' and cards[1].tag:GetText()==R.OFFER_PICK_TAG:sub(3) and cards[1].star~=nil and cards[1].star:IsShown()
  and cards[3].tag:GetText()==R.OFFER_GUARANTEED_TAG,'N6: fixture: the pick and guaranteed tags are shown',
  tostring(cards[1].tag:GetText())..' / '..tostring(cards[3].tag:GetText()))
 C.expect(whole,'N6: each new tag gets its own width, not the earlier text\'s box',table.concat(notes,' | '))
end)
NATIVE.bounded=false

----------------------------------------------------------------------------
-- N7: a client whose small font is 10 keeps everything as it was.
----------------------------------------------------------------------------
C.scenario('N7 a native height of 10, or no readable reference, keeps 10 / 12 / 14, the reference width and the reference geometry',function()
 SetNative(10)
 C.setup(Render(Play())==true,'N7: fixture: the Play panel at native 10')
 local layout=NexusPanel._responsiveLayout
 local fontScale=LM.RuntimeMetrics()
 C.guard(Owned('small')==10 and Owned('normal')==12 and Owned('large')==14 and fontScale==1,
  'N7: the owned fonts are exactly 10 / 12 / 14 at font scale 1',tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large')))
 C.guard(layout.small==11 and layout.normal==14 and layout.large==16 and layout.gap==6,'N7: the layout rows are 11 / 14 / 16 with a 6 px gap')
 -- The width follows the text scale (W1): at the reference size it is the
 -- reference width. EXPECT: the approved compact panel's reference width is
 -- 284 units (its 420 reference pixels where the panel installed before it,
 -- 420 units wide by the same rule, measured 621); the guard that stood
 -- here asked for those 420 units. The fonts above are untouched by it.
 C.expect(NexusPanel:GetWidth()==284 and layout.width==284 and BASE==284,
  'N7: at the reference text size the panel is the approved reference width, 284 units',NexusPanel:GetWidth())
 local cards=NexusPanel._offerCards
 -- The approved compact row (RowPlan states it): a row is as tall as its
 -- content needs and never under the draft's own height for its
 -- arrangement, 28 pixels on one line and 24 more with the phrase under the
 -- name. Row 2 here ('Hollow Bell', 'Rare', 'wanted') is one line: the
 -- draft's 28 pixels, 18.9 units at the reference size, where its content
 -- needs 16 (the 14-unit primary line this model measures and the two
 -- 1-unit pads). The expectation that stood here held a row to the grid's
 -- two lines (31 units for one-line texts, never under a 29-unit model
 -- row); that grid is intentionally gone, so its literals are replaced by
 -- the compact row's, not relaxed.
 -- Approved panel cleanup, kept: the selected offer's complete reason is
 -- inside its own row and is not repeated under the rows. Row 1 is this
 -- fixture's selected offer, so under its lines it also holds the
 -- recommendation's reason: the draft's 18 pixels more, or the reason's own
 -- measured lines when they need more.
 local reason=NexusPanel._rollRec
 local rowRect,reasonRect=Rect(cards[1]),Rect(reason)
 print('OBSERVED','N7 row 1='..tostring(cards[1]:GetHeight())..' name='..tostring(cards[1].name:GetHeight())
  ..' quality='..tostring(cards[1].quality:GetHeight())..' tag='..tostring(cards[1].tag:GetHeight())
  ..' reason='..tostring(reason:GetHeight())..' "'..G.Visible(reason:GetText() or '')..'" row 2='..tostring(cards[2]:GetHeight())
  ..' row 3='..tostring(cards[3]:GetHeight()))
 local rowWidth=NexusPanel:GetWidth()-2*Inset()
 local compactRows,rowNotes=true,{}
 local plans={}
 for i=1,3 do
  local plan=RowPlan(cards[i],rowWidth)
  plans[i]=plan
  local need,pixels=plan.need,plan.pixels
  if i==1 then
   local _,size=reason:GetFont()
   local lines=math.max(1,G.Rows(reason:GetText() or '',plan.column,CHAR*size))*math.ceil(size*LINE)
   need,pixels=need+math.max(Design(18),lines),pixels+18
  end
  local got=cards[i]:GetHeight()
  rowNotes[#rowNotes+1]=i..': '..tostring(got)..' need '..need..' drawn '..pixels..' px'
  if not (cards[i]:GetWidth()==rowWidth and got>=need and (got==need or Drawn(pixels,got))) then compactRows=false end
 end
 C.expect(compactRows and plans[2].inline and plans[2].pixels==28 and plans[2].need==16
  and cards[2].name:GetStringHeight()==14 and Drawn(28,cards[2]:GetHeight()) and cards[2]:GetHeight()<29
  and not plans[1].inline and not plans[1].split,
  'N7: an offer row is the compact row across the offer block: as tall as its content needs, the draft\'s 28 pixels for one line (18.9 units here, under the former 29-unit model row) and 24 more with the phrase under the name',
  table.concat(rowNotes,'; '))
 local qualityRect=Rect(cards[1].quality)
 C.guard(reason:IsShown() and G.Visible(reason:GetText() or '')~='' and rowRect and reasonRect and G.Inside(reasonRect,rowRect,0.01)
  and reason:GetHeight()+0.5>=reason:GetStringHeight() and Size(cards[1].name)==12 and Size(cards[1].tag)==11,
  'N7: the selected row holds its whole reason; the name is 12 units and the tag 11',
  tostring(cards[1]:GetHeight())..' / '..tostring(cards[2]:GetHeight()))
 -- GUARD: before the grid the reason already stood under the first line's
 -- quality inside its row, and the row held no more than its texts and the
 -- layout gap; the grid kept both, and so does the compact row, whose
 -- quality stands in the phrase under this long name.
 C.guard(reasonRect and qualityRect and reasonRect[2]>=qualityRect[4]-0.01
  and cards[1]:GetHeight()<=cards[1].name:GetHeight()+cards[1].quality:GetHeight()+reason:GetHeight()+layout.gap,
  'N7: the selected row holds its reason under its quality, with no more than its texts and the layout gap (no reserved band)',
  Text(reasonRect)..' under '..Text(qualityRect)..' in a row of '..tostring(cards[1]:GetHeight()))
 -- Count disclosure (C1). The guard that stood here asked for the 72 px
 -- charges cell, and for the heading 76 px short of its row, on this panel,
 -- whose Details is closed. The charges are counts: with Details closed
 -- there is no row and no cell, and the heading has its whole row (EXPECT;
 -- at aca67cf4 the row stood here whatever Details was). The approved
 -- compact heading row is the offer block's whole width, 274 units of the
 -- 284-unit panel between its 5-unit insets (it was 400 px of the 420-unit
 -- panel), less the destination cell at its right end (DestinationRoom).
 -- The reference geometry of the charges cell is unchanged and is asked for
 -- where the row stands, with Details open (GUARD: the two literals that
 -- stood here, in the row the destination cell now leaves); Details is then
 -- closed again for the checks below, which are the reference panel's.
 local closedRow=274-DestinationRoom(false)
 local none,noneDetail=NoCharges(closedRow)
 C.expect(none and rowWidth==274,'N7: with Details closed there is no charges row or cell: the heading has the whole 274-unit row less the destination cell',noneDetail)
 local opened,cellW,headW,rollW,rowShown,rowCount
 KeepDetails(function()
  P._playDetails=true
  opened=Render(Play())==true
  cellW,headW,rollW=NexusPanel._chargesText:GetWidth(),NexusPanel._rollStatus:GetWidth(),NexusPanel._responsiveLayout.boxes.roll.w
  rowShown,rowCount=NexusPanel._chargesText:IsShown(),ChargeRows()
 end)
 C.setup(opened and Render(Play())==true and P._playDetails~=true,'N7: fixture: the same panel with Details open, then closed again')
 C.guard(rowShown and rowCount==1 and cellW==72,
  'N7: with Details open the charges row is on the panel once and its cell is 72 px',
  tostring(cellW)..' / '..tostring(headW)..' of '..tostring(rollW)..', shown '..tostring(rowShown)..' x'..tostring(rowCount))
 -- (EXPECT: the heading kept the 400-unit row less 76; it keeps the
 -- 274-unit row less the destination cell and those 76.)
 C.expect(rollW==274 and headW==rollW-DestinationRoom(true)-76,
  'N7: and the heading keeps the rest of the 274-unit row less the destination cell and 76',
  tostring(headW)..' of '..tostring(rollW))
 local back,backDetail=NoCharges(closedRow)
 C.expect(back,'N7: and with Details closed again the row and its cell are gone',backDetail)
 local title,build,wishlist=Rect(NexusPanel._contextTitle),Rect(NexusPanel._contextBuild),Rect(NexusPanel._contextWishlist)
 -- The approved compact header at the reference size, as the draft draws
 -- it: the title 5 pixels under the panel's top in line 1's row (22 units:
 -- the 24-unit grip less the unit it stands out above and below, where the
 -- draft's 22 pixels are 15), the Build line 2 pixels under that row and the
 -- Wishlist line 2 pixels under the Build line's, each in the draft's
 -- 20-pixel row or as tall as its own text needs (approved panel cleanup:
 -- full names, wrapped, never shortened). Here that is 3 / 27 / 42: the
 -- 12-unit primary line measures 14 units in this model, a unit more than
 -- the 13 the draft's row is at this place. EXPECT: the guard that stood
 -- here pinned the former header (8 / 32 / 54 with 20-unit rows).
 -- Each line's label is a caption in a column of its own at the body's
 -- inset and the two names share one left edge after it (the next check).
 -- This fixture's Build name fits one line beside its caption: the SETUP
 -- states that from the words and the fixture's own font model (nothing is
 -- read from the row's box), so a Build row that grows at the reference
 -- size fails this check instead of moving what it expects. The names'
 -- column is the panel less its insets, the caption column (the wider
 -- caption and 6 pixels), the 6 pixels before the buttons and the button
 -- column (the wider of the two labels and their room, LabelRoom: 14
 -- pixels and never under 14 units; at most two fifths of the panel).
 -- (Typography correction: the two labels are worded in the controls' role,
 -- CONTROL, where they were in the 'normal' role.)
 local buildLine,wishlistLine=NexusPanel._contextBuild,NexusPanel._contextWishlist
 local captionColumn=0
 for _,caption in ipairs({NexusPanel._contextBuildCaption,NexusPanel._contextWishlistCaption}) do
  if caption:IsShown() then captionColumn=math.max(captionColumn,math.ceil(Natural(caption))+Design(6)) end
 end
 local buttonColumn=math.min(math.floor(NexusPanel:GetWidth()*0.4),
  math.ceil(math.max(Wide(NexusPanel._switchBtn:GetText() or '',CONTROL),Wide(NexusPanel._contextChange:GetText() or '',CONTROL)))+LabelRoom())
 local nameColumn=NexusPanel:GetWidth()-2*Inset()-captionColumn-Design(6)-buttonColumn
 C.setup(Natural(buildLine)<=nameColumn and captionColumn>Design(6),
  'N7: fixture: the Build line\'s words fit one line of the names\' column',
  string.format('%.1f',Natural(buildLine))..' in '..tostring(nameColumn))
 C.expect(title and build and wishlist and title[2]==DesignY(5) and title[2]==3
  and NexusPanel._contextTitle:GetHeight()==TitleRow() and TitleRow()==22
  and build[2]==title[4]+Span(27,29) and build[2]==27
  and buildLine:GetHeight()==math.max(Span(29,49),math.ceil(buildLine:GetStringHeight())) and buildLine:GetHeight()==14
  and wishlist[2]==build[4]+Span(49,51) and wishlist[2]==42
  and wishlistLine:GetHeight()==math.max(Span(51,71),math.ceil(wishlistLine:GetStringHeight()))
  and buildLine:GetWidth()==nameColumn and wishlistLine:GetWidth()==nameColumn,
  'N7: the header lines are at 3 / 27 / 42: the title in line 1\'s 22-unit row, the Build line 2 pixels under it in its row, the Wishlist line 2 pixels under that, in its row or as tall as its wrapped text',
  Text(title)..' '..Text(build)..' '..Text(wishlist))
 local buildCap,wishlistCap=Rect(NexusPanel._contextBuildCaption),Rect(NexusPanel._contextWishlistCaption)
 -- (EXPECT: the captions stood at x 12 with the names 6 units after their
 -- column; the compact header has them at the body's inset, 5 units here,
 -- with the draft's 6 pixels after the column.)
 C.expect(buildCap and wishlistCap and build and wishlist and buildCap[1]==Inset() and wishlistCap[1]==Inset() and Inset()==5
  and buildCap[2]==build[2] and wishlistCap[2]==wishlist[2] and build[1]==wishlist[1]
  and build[1]==Inset()+captionColumn and Size(NexusPanel._contextBuildCaption)==11
  and Size(NexusPanel._contextWishlistCaption)==11,
  'N7: the Build and Wishlist captions stand at the body\'s inset in the 11-unit secondary role; the two names share one left edge 6 design pixels after the caption column',
  Text(buildCap)..' '..Text(wishlistCap)..' names '..Text(build)..' '..Text(wishlist))
 local switch,change=Rect(NexusPanel._switchBtn),Rect(NexusPanel._contextChange)
 -- Each button stands at its own line's top, at the panel's right inset, 6
 -- design pixels after the names' column, in the draft's 20-pixel height
 -- (never taller than its row), so the two rows 2 pixels apart do not
 -- overlap. EXPECT: they were 106 x 20 units; the compact buttons are one
 -- column as wide as the wider label needs (My Builds here: 55 units of
 -- words and 14 of room, LabelRoom: the draft's 14 pixels are 9 units at
 -- this size, under the 14 its label's end caps need). The routes and the
 -- labels are unchanged (N8).
 -- (Typography correction, EXPECT: the column was 74 units, for the 60
 -- units those nine characters are in the 12-unit primary role; in the
 -- 11-unit control role they are 54.45, so 55, in this model.)
 C.expect(switch and change and switch[2]==build[2] and change[2]==wishlist[2]
  and switch[3]-switch[1]==buttonColumn and change[3]-change[1]==buttonColumn and buttonColumn==69
  and switch[3]==NexusPanel:GetWidth()-Inset() and change[3]==switch[3] and switch[1]==build[3]+Design(6)
  and switch[4]-switch[2]==math.min(Design(20),buildLine:GetHeight())
  and change[4]-change[2]==math.min(Design(20),wishlistLine:GetHeight()) and G.Apart(switch,change),
  'N7: My Builds and Change are one 69-unit column at the right inset, each at its line\'s top in the draft\'s 20-pixel height, apart',Text(switch)..' '..Text(change))
 local card,tier,ash,gain=StatusCard()
 -- The difficulty band (the approved compact panel, presentation B) at the
 -- reference size: the panel's width less its insets; the tier and Soul Ash
 -- on one line with the multiplier in its 70-unit cell at the band's right
 -- end, between the band's 8-pixel side insets and 10 pixels apart; under
 -- that line the Intensity bar across the band between the same insets, the
 -- draft's 4 pixels high and 3 above the band's inner edge. The band is as
 -- tall as its line needs with its insets and bar, or the draft's 34 pixels
 -- when the line needs no more. EXPECT: the Compact A card that stood here
 -- (48 units: a 15-unit tier line beside the multiplier over a 14-unit Soul
 -- Ash line) is intentionally gone; its literals are replaced by the
 -- band's.
 local cardRect,tierRect,ashRect,gainRect=card and Rect(card),tier and Rect(tier),ash and Rect(ash),gain and Rect(gain)
 local barRect=card and Rect(card.intensityBar)
 local bandLine=card and math.max(tier:GetStringHeight(),ash:GetStringHeight()) or 0
 local around=2*Design(3)+Design(1)+Design(4)+Design(3)
 C.expect(card and cardRect and tierRect and ashRect and gainRect and barRect
  and card:GetWidth()==NexusPanel:GetWidth()-2*Inset() and cardRect[1]==Inset()
  and tierRect[1]==cardRect[1]+Design(8) and gainRect[3]==cardRect[3]-Design(8) and gain:GetWidth()==70
  and math.abs(ashRect[2]-tierRect[2])<=0.01 and math.abs(gainRect[2]-tierRect[2])<=0.01
  and ashRect[1]>=tierRect[3]-0.01 and ashRect[3]==gainRect[1]-Design(10)
  and tier:GetWidth()>=Natural(tier)-0.01 and ash:GetWidth()>=Natural(ash)-0.01 and gain:GetWidth()>=Natural(gain)-0.01
  and barRect[1]==cardRect[1]+Design(8) and barRect[3]==cardRect[3]-Design(8) and barRect[4]-barRect[2]==Design(4)
  and cardRect[4]-barRect[4]==2*Design(3) and barRect[2]>=math.max(tierRect[4],ashRect[4])-0.01
  and bandLine==14 and (card:GetHeight()==around+bandLine or (card:GetHeight()>around+bandLine and Drawn(34,card:GetHeight())))
  and card:GetHeight()==layout.boxes.status.h,
  'N7: the difficulty band holds the tier and Soul Ash on one line beside the 70-unit multiplier cell, above its Intensity bar; it is the draft\'s 34 pixels or as tall as its line needs',
  card and ('card '..Text(cardRect)..' tier '..Text(tierRect)..' ash '..Text(ashRect)..' gain '..Text(gainRect)..' bar '..Text(barRect)))
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
-- the panel at the width its text scale gives it. The cell takes the room
-- such a heading leaves under the conservative text model too, so the line
-- its row held before still holds. These headings say their destination
-- themselves, so no destination cell stands beside them.
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
 -- width less layout.headingReserve; the approved compact offer block has
 -- no inner insets, so the 4 units that were taken off here are gone). At
 -- aca67cf4 the row stood here whatever Details was. The cell checks below
 -- are unchanged and are made with Details open, where the row stands;
 -- Details is then closed again.
 if not C.setup(type(layout)=='table' and layout.boxes and layout.boxes.roll and head:IsShown() and (head:GetText() or '')~='',
  tag..': fixture: the heading is shown, Details closed') then return end
 local closedHead,closedRoll,closedPanel=head:GetHeight(),layout.boxes.roll.h,NexusPanel:GetHeight()
 local slotCell=NexusPanel._offerSlot
 local none,noneDetail=NoCharges(layout.boxes.roll.w-(tonumber(layout.headingReserve) or 0))
 C.expect(none and layout.boxes.roll.w==NexusPanel:GetWidth()-2*Inset() and not (slotCell and slotCell:IsShown()),
  tag..': with Details closed there is no charges row, hover or cell: the heading has its whole row',noneDetail)
 P._playDetails=true
 if not C.setup(Render(model)==true and #(P._lastModel.cards or {})==0 and P._playDetails==true,tag..': fixture: the same heading with Details open') then return end
 layout=NexusPanel._responsiveLayout
 if not C.setup(type(layout)=='table' and layout.boxes and layout.boxes.roll and head:IsShown() and charges:IsShown()
  and (head:GetText() or '')~='' and (charges:GetText() or '')~='',tag..': fixture: the heading and the charges row are shown') then return end
 -- Approved compact Auto ON (no permanent row solely for the explanation
 -- control): while Auto is ON the optional "Auto explained" disclosure
 -- stands at the right end of this heading row, so the row the heading and
 -- the charges cell share is the roll width less the room the layout states
 -- for that control (layout.headingReserve; none with Auto OFF).
 -- v9 (Root's ruling SPEC-A2): the cell is the row of counts' own one-line
 -- width in the room the row has for it (Cell); the heading keeps the rest
 -- of the row and wraps there when its line is wider. EXPECT: the cell was
 -- Cell(row,head,false), in the room the heading's own line and its line
 -- under the conservative model left.
 local reserve=tonumber(layout.headingReserve) or 0
 local row=layout.boxes.roll.w-reserve
 local disclosure=NexusPanel._autoInfoBtn
 if reserve>0 then
  local dr,hr,cr=Rect(disclosure),Rect(head),Rect(charges)
  C.guard(model.auto==true and disclosure and disclosure:IsShown() and dr and hr and cr and G.Apart(dr,hr) and G.Apart(dr,cr)
   and disclosure:GetWidth()<=reserve,tag..': the row is shared only with the shown Auto disclosure, which overlaps neither the heading nor the charges',
   'reserve '..reserve..' disclosure '..Text(dr))
 else
  C.guard(not (disclosure and disclosure:IsShown() and model.auto~=true),tag..': with Auto OFF no disclosure takes heading room')
 end
 local cell=Cell(row,Natural(charges))
 local conservative=Chars(head)*math.max(7.0,0.70*10*Scale())
 local detail='cell '..tostring(charges:GetWidth())..' want '..cell..'; heading "'..G.Visible(head:GetText())..'" box '..tostring(head:GetWidth())
  ..' natural '..string.format('%.1f',Natural(head))..' conservative '..string.format('%.1f',conservative)
  ..'; charges natural '..string.format('%.1f',Natural(charges))
 print('OBSERVED',tag,detail)
 ;(cell>72 and C.expect or C.guard)(charges:GetWidth()==cell and head:GetWidth()==row-cell-4,
  tag..': the charges cell is the layout-derived '..cell..' px and the heading keeps the rest of the row less the cell and its gap',detail)
 if Natural(charges)<=cell then
  C.expect(Natural(charges)<=charges:GetWidth()+0.01 and charges:GetStringHeight()<=math.ceil(Size(charges)*LINE)+0.01,
   tag..': the compact charges row is whole inline in its cell, on one line',detail)
 end
 -- The guard that stood here asked, for every cell, that a heading whose
 -- line under the conservative model fits beside the 72 px minimum kept
 -- that line. That was the rule's own promise while the cell took only the
 -- room the heading left. It stands unchanged where the cell is the 72 px
 -- minimum. Beside a wider cell Root's ruling retires it (the right cell
 -- comes first, the left text may wrap); what is asked there instead is
 -- that the heading is whole: on its line where that fits the box it
 -- keeps, else wrapped in a box as tall as its lines.
 if cell==72 and conservative<=row-76 then
  C.guard(conservative<=head:GetWidth()+0.01,tag..': beside the 72 px minimum cell the heading still holds its line under the conservative text model',detail)
 end
 if Natural(head)<=row-cell-4 then
  C.guard(Natural(head)<=head:GetWidth()+0.01,tag..': a heading whose line fits beside the charges cell is whole on its line',detail)
 else
  C.expect(head:GetHeight()+0.5>=head:GetStringHeight() and head:GetStringHeight()>math.ceil(Size(head)*LINE),
   tag..': a heading wider than the box it keeps beside the charges cell wraps there, whole, in a box as tall as its lines',
   detail..'; box '..tostring(head:GetHeight())..' for text '..tostring(head:GetStringHeight()))
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
 local again,againDetail=NoCharges(layout.boxes.roll.w-(tonumber(layout.headingReserve) or 0))
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
  -- Typography correction: the Auto control draws its label in a font
  -- object of its own, so that no shared font object is ever sized for it.
  -- That object is a copy of the controls' role, the 11-unit secondary font
  -- x the native scale: its fit must not put the label back in the 12-unit
  -- primary role. EXPECT fails at 50f78c94, where it was a copy of the
  -- primary font. (The object is read by the client-wide name the panel
  -- gives it; the shared fonts' guard below still holds beside it.)
  local autoFont=_G.NexusAutoButtonFont
  C.expect(autoFont~=nil and Near(Size(autoFont),11*scale),
   tag..': the Auto control\'s own font is the 11-unit control role, x the native scale, not the primary one',
   autoFont and tostring(Size(autoFont)) or 'no such font object')
  -- Standards R1: the role on the controls themselves. The widths above and
  -- in N7, N8 and N10 only show which font a control is MEASURED in; a
  -- control put back in the normal role would still pass them, its label
  -- then drawn wider than it was measured. So the font each control is
  -- GIVEN is asked here, on the widget, for its normal, highlight and
  -- disabled states (the three setters this fixture records: Install).
  -- The nine controls are reached as the panel's own widgets: the fields it
  -- keeps for Options, My Builds, Change and Details; its own list of the
  -- three footer hubs (P.FooterHubs); and, for the two setup actions, which
  -- it keeps no field for, the one button among its children that carries
  -- the action's reviewed label.
  -- EXPECT, failing at 50f78c94 by design (there eight of the nine were
  -- given the 12-unit normal font and Details none of the panel's own):
  -- each of the nine was given the owned secondary font object, which is 11
  -- units x the native scale at this native height and is not the primary
  -- one. The Auto control, given that role first, was then given its own
  -- font object for all three states (GUARD of its fit: the object was a
  -- copy of the primary font before, and is asked for its size above).
  local STATES={'normal','highlight','disabled'}
  local secondary,primary=_G[LM.FontObject('secondary')],_G[LM.FontObject('normal')]
  local function PanelButton(key)
   local label,found=(Nexus.Localization.Text(key)),nil
   for _,child in ipairs(NexusPanel.children or {}) do
    if type(child)=='table' and child.kind=='Button' and type(child.GetText)=='function' and child:GetText()==label then
     -- (Two buttons with one label would not name one control.)
     if found then return nil end
     found=child
    end
   end
   return found
  end
  -- The font a widget was last given for a state, as a font object (the
  -- panel names an owned font; a name is read as the object it names).
  local function Given(button,state)
   local given=type(button)=='table' and rawget(button,'_buttonFonts') or nil
   local font=type(given)=='table' and given[state] or nil
   if type(font)=='string' and _G[font]~=nil then font=_G[font] end
   return font
  end
  local function Named(font)
   if font==nil then return 'no font given' end
   if type(font)~='table' then return tostring(font) end
   local name=(font==secondary and 'the secondary font') or (font==primary and 'the normal font')
    or (font==autoFont and 'the Auto control\'s own font') or 'another font'
   return name..(type(font.GetFont)=='function' and (' at '..tostring(Size(font))) or '')
  end
  local hubs=type(P.FooterHubs)=='function' and P.FooterHubs() or {}
  local play=NexusPanel._play
  local controls={
   {'Options',NexusPanel._menuBtn},{'My Builds',NexusPanel._switchBtn},{'Change',NexusPanel._contextChange},
   {'Assign Wishlist',PanelButton('panel.button.assign_wishlist')},{'Create Wishlist',PanelButton('panel.button.create_wishlist')},
   {'the Wishlist hub',hubs[1]},{'the Builds hub',hubs[2]},{'the Orbs hub',hubs[3]},
   {'Details',type(play)=='table' and play.details or nil},
  }
  local auto=NexusPanel._autoBtn
  local apart,recorded,seen,lost=true,type(auto)=='table',{},{}
  for _,control in ipairs(controls) do
   local button=control[2]
   if type(button)~='table' or seen[button] or button==auto then
    apart=false;lost[#lost+1]=control[1]
   else
    seen[button]=true
    for setter in pairs(BUTTON_FONT) do
     if not rawequal(button[setter],RECORDER[setter]) then recorded=false end
    end
   end
  end
  if type(auto)=='table' then
   for setter in pairs(BUTTON_FONT) do
    if not rawequal(auto[setter],RECORDER[setter]) then recorded=false end
   end
  end
  if C.setup(#controls==9 and apart and recorded and hubs[3]==NexusPanel._orbsHubBtn
   and type(secondary)=='table' and type(primary)=='table' and secondary~=primary,
   tag..': fixture: the nine controls are nine widgets of the panel beside the Auto control, their font setters are the ones this fixture records, and the owned secondary and normal fonts are two objects',
   'not found, or found twice: '..table.concat(lost,', ')..'; setters recorded: '..tostring(recorded)) then
   local roles,notes=true,{}
   for _,control in ipairs(controls) do
    for _,state in ipairs(STATES) do
     local font=Given(control[2],state)
     if not (font~=nil and font==secondary and font~=primary and Near(Size(font),11*scale)) then
      roles=false;notes[#notes+1]=control[1]..', '..state..': '..Named(font)
     end
    end
   end
   C.expect(roles,
    tag..': Options, My Builds, Change, both setup actions, the three footer hubs and Details were each given the owned secondary font, 11 units x the native scale, for their normal, highlight and disabled states',
    table.concat(notes,'; '))
   local own,ownNotes=autoFont~=nil,{}
   for _,state in ipairs(STATES) do
    local font=Given(auto,state)
    if not (font~=nil and font==autoFont) then own=false;ownNotes[#ownNotes+1]=state..': '..Named(font) end
   end
   C.guard(own,tag..': the Auto control was given its own font object for its normal, highlight and disabled states',
    table.concat(ownNotes,'; '))
  end
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
-- native height changed left the Wishlist line at the height measured for
-- the smaller font, so its last line was cut; back at the smaller height the
-- larger one stayed as an empty band. The model is rendered directly here:
-- the Render helper above first renders another model, which changes the
-- header words and so hid this.
-- Main-panel visual correction: the panel's width now follows the text
-- scale, and the header's measurement is keyed by that width too. So that
-- the font is the only thing that changes here, as this scenario's name
-- says, the panel is held at one width at both native heights: on a
-- 640-unit screen at the chosen 150% size the width rule is bounded at 410
-- units (W1), and the approved 284-unit reference width asks for more than
-- that at native 16 (454) and at native 20 (568). The pair was 10 and 12.5,
-- which the same screen bounded at the former 420-unit reference width;
-- under the approved reference width those two ask for 284 and 355, below
-- the bound, so the pair is now two heights the bound holds. The checks are
-- the ones this scenario had: the larger font needs a taller line, the line
-- is as tall as its text there, and the header grows by what the line
-- gained. Without the hold the width change alone asks for the new
-- measurement, and a header that no longer followed the font would pass
-- unseen. A second case changes the names' own font alone (GUARD), and the
-- wider panel is a third, separate case at the end: its width is the
-- EXPECT, and that the line and the header are measured there too is a
-- GUARD.
C.scenario('N9 the wrapped Wishlist line is measured again when only the font changes',function()
 local function Named()
  local m=Play()
  m.progress.wishlistName='Synthetic Play plan whose name is long enough to need more than one line'
  return m
 end
 local line=NexusPanel._contextWishlist
 -- (The Wishlist row: the draft's 20 pixels where it stands, or its text's
 -- measured lines when they need more.)
 local function Fit() return line:GetHeight(),math.max(Span(51,71),math.ceil(line:GetStringHeight())) end
 local function Header() return NexusPanel._responsiveLayout.boxes.header.h end
 -- The header box from its own lines, as the draft spaces them: the title's
 -- row, 2 pixels, the Build line, 2 pixels, the Wishlist line and the 5
 -- pixels under it. (It was line 1's 26 units, the Build line, 2 units, the
 -- Wishlist line and 4 units.)
 local function Lines()
  return NexusPanel._contextTitle:GetHeight()+Span(27,29)+NexusPanel._contextBuild:GetHeight()+Span(49,51)+line:GetHeight()+Span(71,76)
 end
 -- The screen and the chosen size this fixture sets to hold the width, put
 -- back below.
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local ok,err=pcall(function()
  UIParent:SetSize(640,4000)
  P.SetPanelScale(1.5)
  SetNative(16)
  C.setup(Render(Named())==true and NexusPanel:GetWidth()==410,'N9: fixture: a long Wishlist name at native 16, in the panel held at 410 units',
   NexusPanel:GetWidth())
  local h10,need10=Fit()
  local box10=Header()
  C.setup(need10>Span(51,71) and Near(h10,need10) and math.ceil(line:GetStringHeight())==need10,
   'N9: fixture: the name wraps at native 16 and its line is as tall as its text',
   tostring(h10)..' for '..tostring(need10))
  SetNative(20)
  C.setup(P.Render(Named())==true and NexusPanel:GetWidth()==410,
   'N9: fixture: the same model at native 20 at the same 410-unit width',
   'width '..tostring(NexusPanel:GetWidth()))
  local h12,need12=Fit()
  local box12=Header()
  print('OBSERVED','N9 native 16 -> 20 at 410 units','line '..tostring(h10)..' -> '..tostring(h12),
   'text needs '..tostring(need10)..' -> '..tostring(need12),'header '..tostring(box10)..' -> '..tostring(box12))
  C.setup(need12>need10,'N9: fixture: the larger font needs a taller line',need12)
  C.expect(Near(h12,need12),'N9: the Wishlist line is as tall as its text at the new size (no line is cut)',
   tostring(h12)..' for '..tostring(need12))
  C.expect(box12>=box10+(need12-need10)-0.01,'N9: and the header grows by what the line gained',
   tostring(box10)..' -> '..tostring(box12))
  SetNative(16)
  P.Render(Named())
  local back,needBack=Fit()
  C.expect(Near(back,needBack) and Near(back,h10) and Header()==box10,
   'N9: back at native 16 the line and the header return (no height is kept from the larger font)',
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
  buildLine:SetFont(PATH,24,'')
  line:SetFont(PATH,24,'')
  C.setup(P.Render(Named())==true and Near(Size(line),24) and Near(Size(buildLine),24) and size10<24 and NexusPanel:GetWidth()==410,
   'N9: fixture: only the Build and Wishlist lines take a 24-unit font, at native 16 in the 410-unit panel',Size(line))
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
  -- The panel at the width its text scale asks for, apart from the
  -- font-only case above: at 100% on a 1920-unit screen the same model at
  -- native 12.5 is laid out 355 units wide (the approved 284-unit reference
  -- width x 1.25; it was 525, the former 420 x 1.25), and its line and
  -- header are measured for that width and font (GUARD).
  P.ResetPanelScale()
  UIParent:SetSize(1920,4000)
  SetNative(12.5)
  C.setup(P.Render(Named())==true,'N9: fixture: the same model at native 12.5 on a 1920-unit screen at 100%')
  local wide=NexusPanel:GetWidth()
  local hWide,needWide=Fit()
  print('OBSERVED','N9 native 12.5 on a 1920-unit screen','panel '..tostring(wide),
   'line '..tostring(hWide)..' for '..tostring(needWide),'header '..tostring(Header())..' for lines '..tostring(Lines()))
  C.expect(wide==355,'N9: with the room for it the panel is 355 units wide at native 12.5',wide)
  -- (That the line is as tall as its text is the GUARD it was. That the
  -- header is exactly its lines is asked with the draft's spacing now, so
  -- it is an EXPECT: at eef1608f the header was its lines with the former
  -- 26 / 2 / 4-unit spacing.)
  C.guard(Near(hWide,needWide),'N9: and there too the line is as tall as its text',
   tostring(hWide)..' for '..tostring(needWide))
  C.expect(Header()==Lines(),'N9: and the header is exactly its lines, as the draft spaces them',
   'header '..tostring(Header())..' for lines '..tostring(Lines()))
 end)
 if scale0==nil then P.ResetPanelScale() else P.SetPanelScale(scale0) end
 UIParent:SetSize(w0,h0)
 SetNative(10)
 P.Render(Named())
 C.setup(ok,'N9: fixture: the scenario ran',err)
end)

-- N10 (independent Spec review, required finding 2). The title keeps one
-- fixed role (times the native reference) whatever it says. Its state cue
-- is the end of its line, so a title wider than its slot wraps inside that
-- slot at its measured height instead of being cut or drawn smaller; header
-- line 1 is as tall as the title needs, and the Build and Wishlist rows,
-- their buttons and the header box move down by exactly what the title
-- gained. Checked for "Nexus" and "Nexus paused" with every cue (Preview,
-- Empty, both, Unconfirmed, Not known) at 100%, at 125% and at 200%.
-- EXPECT fails before the correction (a wide title fell back to another
-- role in a fixed 20-unit line and was still cut at 125%); GUARD: the grip
-- does not move, the slot keeps its width, and a title that needs no more
-- than line 1's row leaves the header as it was. Widths are this fixture's
-- stated model (0.55 em, 1.15 em lines), not native glyphs.
-- Main-panel visual correction: that one fixed role is the 12-unit primary
-- role (it was the title's own 15-unit role, which the size check here asked
-- for; the quieter role is intended and no body text is smaller for it).
-- The approved compact header: line 1 is the draft's (Line1 above states
-- it): the grip at the body's inset, the title 6 pixels after it, and at
-- the right the Auto control, Options and Close, each as wide as its own
-- words need, so the title's slot is what they leave: 100 units of the
-- 284-unit panel at the reference size (it was 150 of 420 with fixed
-- slots; and 92 of 284 while the controls' words were the 12-unit primary
-- role: the typography correction words them in the 11-unit control role,
-- so the controls are narrower by what their words lost and the title has
-- the rest). The line-1 literals this scenario pinned (the title at 36, 8; the
-- grip at 8, 6; the Build row at 32; the 4 units under the Wishlist row)
-- are the former header's and are replaced by the draft's places here, each
-- marked where it stood. The third pass was native 12.5 in the 420-unit
-- panel a 640-unit screen left at the 150% chosen size; that screen now
-- leaves 410 units, more than the 355 native 12.5 asks for, so the bounded
-- pass is native 20 on an 850-unit screen at 150% (550 units where the
-- text scale asks for 568: W1).
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
 -- The screen and the chosen size this fixture sets for the bounded pass,
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
  -- {native height, bounded by the screen at the chosen size}.
  for _,case in ipairs({{10,false},{12.5,false},{20,true}}) do
   local native,held=case[1],case[2]
   if held then UIParent:SetSize(850,4000);P.SetPanelScale(1.5) end
   for _,isPaused in ipairs({false,true}) do
    for _,edit in ipairs(EDITS) do
     local text=(isPaused and 'Nexus paused' or 'Nexus')..edit[1]
     local tag='N10 native '..tostring(native)..(held and ' in the 550-unit panel' or '')..' "'..text..'"'
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
      -- Line 1's row (TitleRow: the draft's 22 pixels, never under the
      -- grip less the pixel it stands out above and below), or the title's
      -- own lines when they need more. (It was a 20-unit line.)
      local titleRow=math.max(TitleRow(),needs)
      local gained=titleRow-TitleRow()
      local build,wishlist=Rect(NexusPanel._contextBuild),Rect(NexusPanel._contextWishlist)
      local header=layout.boxes.header
      print('OBSERVED',tag,'font='..tostring(size),'slot='..tostring(slot),'line='..string.format('%.1f',Natural(title)),
       'rows='..tostring(rows),'box='..tostring(height),'needs='..tostring(needs),'header='..tostring(header.h),
       'build top='..tostring(build and build[2]))
      if rows>1 then wrapped=wrapped+1 end
      C.setup(longest<=slot+0.01,tag..': fixture: every word of the title fits the slot at the title size',longest)
      C.setup(NexusPanel:GetWidth()==(held and 550 or math.floor(BASE*Scale()+0.5)),
       tag..': fixture: the panel is as wide as its text scale asks, or the 550 units the screen leaves',NexusPanel:GetWidth())
      C.expect(Near(size,Role('normal')),tag..': the title is drawn at the 12-unit primary role whatever it says, never fitted smaller',size)
      C.expect(height+0.5>=needs and (rows<=1 or rawget(title,'wordWrap')==true) and not (rows<=1 and LM.Shortened(title)),
       tag..': the whole title is shown: one line that fits, or wrapped in a box as tall as its lines',
       'box '..tostring(height)..' for '..tostring(needs)..', rows '..tostring(rows)..', wrap '..tostring(rawget(title,'wordWrap')))
      C.expect(math.abs(height-titleRow)<=0.01,tag..': the title box is its measured height (at least line 1\'s row), no taller',
       tostring(height)..' / '..tostring(titleRow))
      -- The draft's header under the title: 2 pixels, the Build row, 2
      -- pixels, the Wishlist row and 5 pixels to the header's end. (The
      -- literals that stood here were the former header's: the Build row at
      -- 32 and more by what the title gained, and 4 units under the
      -- Wishlist row.)
      C.expect(build~=nil and wishlist~=nil and rect[2]==DesignY(5) and build[2]==DesignY(5)+TitleRow()+gained+Span(27,29)
       and build[2]==rect[4]+Span(27,29) and wishlist[2]==build[4]+Span(49,51)
       and header.y==DesignY(5) and (header.y+header.h)==wishlist[4]+Span(71,76),
       tag..': the Build row starts 2 pixels under the whole title, the Wishlist row 2 pixels under it, and the header box closes 5 pixels under that',
       'title '..Text(rect)..' build '..Text(build)..' wishlist '..Text(wishlist)..' header y='..tostring(header.y)..' h='..tostring(header.h))
      C.expect(math.abs((Top(NexusPanel._switchBtn) or -1)-build[2])<=0.01 and math.abs((Top(NexusPanel._contextChange) or -1)-wishlist[2])<=0.01,
       tag..': My Builds and Change stay at the top of their own rows',
       tostring(Top(NexusPanel._switchBtn))..' / '..tostring(Top(NexusPanel._contextChange)))
      -- The slot as the draft's line 1 leaves it (Line1: from this
      -- fixture's own words and font model), which the panel's own slots
      -- must give too. EXPECT: the slot was from x 36, y 8 to the fixed
      -- Auto slot, 150 units of the 420-unit panel.
      -- (Typography correction, EXPECT: 92 units in the 284-unit panel
      -- while the controls' words were the primary role; 100 with them in
      -- the control role: 284 less the 151 reserved and the title's 33.)
      local line1,drawn=P.HeaderSlots(),Line1()
      C.expect(slot==NexusPanel:GetWidth()-drawn.reserved-drawn.titleLeft and (NexusPanel:GetWidth()~=284 or slot==100)
       and line1.reserved==drawn.reserved and line1.titleLeft==drawn.titleLeft
       and rect~=nil and rect[1]==drawn.titleLeft and rect[2]==DesignY(5),
       tag..': the title keeps its slot (from 6 pixels after the grip, 5 pixels under the top, to the Auto control: 100 units in the 284-unit panel)',
       Text(rect)..' slot '..tostring(slot)..' reserved '..tostring(line1.reserved)..' / '..tostring(drawn.reserved))
      -- The grip: at the body's inset, the draft's 24 pixels and never
      -- under 24 x 24 units, centred on line 1's row for its controls (the
      -- draft's 22 pixels, never under the grip less the pixel it stands
      -- out above and below). It does not move with what the title says.
      -- EXPECT: it stood at 8, 6 in the former header.
      local grip=P.EnsureHeaderGrip()
      local gr=grip and Rect(grip) or nil
      local controls=math.max(Design(22),Grip()-2*Design(1))
      C.expect(gr~=nil and gr[1]==Inset() and gr[2]==DesignY(5)-math.floor((Grip()-controls)/2)
       and gr[3]-gr[1]==Grip() and gr[4]-gr[2]==Grip() and Grip()>=24 and (native~=10 or (gr[1]==5 and gr[2]==2 and Grip()==24)),
       tag..': the grip stands at the body\'s inset on line 1, at least 24 x 24 units, and does not move',Text(gr))
      if gained==0 then
       C.expect(build[2]==DesignY(5)+TitleRow()+Span(27,29) and (native~=10 or build[2]==27),
        tag..': a title that needs no more than line 1\'s row leaves the Build row where the draft draws it',build[2])
      end
     end
    end
   end
   if held then P.ResetPanelScale();UIParent:SetSize(w0,h0) end
  end
  C.setup(wrapped>=6,'N10: fixture: several of these titles need more than one line',wrapped)
  C.expect(rawget(title,'_nonSpaceWrap')==true,'N10: the title may also break inside a word longer than its slot (a long localized cue is not cut)',
   tostring(rawget(title,'_nonSpaceWrap')))
  -- The line-1 slots at the reference size. EXPECT: the guard that stood
  -- here pinned the former fixed slots (top 7, height 22, 234 units
  -- reserved, the title from 36). The compact slots are the draft's at this
  -- text scale: the controls 15 units high (its 22 pixels) in the middle of
  -- line 1's 22-unit row, 151 units reserved for Close (16), Options (its
  -- 43 units of words and the 14 of room its label's end caps need: the
  -- draft's 14 pixels are 9 units here) and the Auto control (its widest
  -- label's 49 units and the 12 its label fit keeps clear), 4 units apart
  -- and after the 5-unit inset; the title from 33 (the inset, the 24-unit
  -- grip, 4).
  -- (Typography correction, EXPECT: 159 units were reserved while the
  -- controls' words were the 12-unit primary role, 47 units for "Options"
  -- and 53 for the widest Auto label; in the 11-unit control role those
  -- seven and eight characters are 42.35 and 48.4 units in this model, so
  -- 43 and 49.)
  SetNative(10)
  local s=C.setup(Render(Play())==true,'N10: fixture: the Play panel at native 10 again') and P.HeaderSlots() or {}
  local drawn=Line1()
  C.expect(s.reserved==drawn.reserved and s.reserved==151 and s.titleLeft==drawn.titleLeft and s.titleLeft==33
   and s.height==Design(22) and s.height==15 and s.top==DesignY(5)+math.floor((22-15)/2) and s.top==6
   and s.gripWidth==24 and s.gripHeight==24,
   'N10: at the reference size the header line 1 slots are the compact draft\'s: the controls\' own widths, 151 units reserved, the title from 33',
   tostring(s.top)..' '..tostring(s.height)..' '..tostring(s.reserved)..' '..tostring(s.titleLeft)..' '..tostring(s.gripWidth)..'x'..tostring(s.gripHeight))
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
    -- Start/Stop surfaces (2026-11-19, 9106 field report): this paused run of
    -- the earlier runtime is history here; its Pause, Resume and Stop are not
    -- offered. Details moves with the row as before.
    local placed=true
    for _,b in ipairs({bar.details}) do
     local r=b:IsVisible() and Rect(b) or nil
     if not (r and math.abs(r[2]-(strip[2]+65+extra))<=0.01 and r[2]>=rect[4]-0.01 and G.Inside(r,strip,0.01)) then placed=false end
    end
    C.expect(placed,tag..': Details sits in the control row under the whole words, inside the strip',
     'row wanted at '..tostring(strip[2]+65+extra)..', words end '..tostring(rect[4]))
    if extra==0 then
     C.guard(math.abs((strip[4]-strip[2])-100)<=0.01 and math.abs(box-52)<=0.01,tag..': words that fit leave the strip at 100 units and the label at 52')
    else
     grew=grew+1
    end
    C.guard(bar.details:GetScript('OnClick')~=nil and bar.details:IsEnabled()
     and not bar.pause:IsShown() and not bar.resume:IsShown() and not bar.stop:IsShown() and not bar.primary:IsShown(),
     tag..': no Pause, Resume or Stop is offered for the paused earlier run; Details keeps its handler')
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
-- (LayoutMetrics.PanelWidth): the reference width x the font scale the
-- owned fonts follow (1 to 2), no wider than the screen leaves at the
-- chosen panel size (its width less the fit's 24-unit margin, over that
-- size; a screen under the fit's own 640-unit floor bounds nothing), and
-- never under the reference width. It is read once per render from the
-- chosen size, never from the size a fit applied, so the same inputs give
-- the same width and a repeated render takes no layout pass; a choice of
-- size that changes the width lays the shown model out again at once.
-- The approved compact panel: the rule is unchanged and its reference width
-- is 284 units where it was 420 (the draft's 420 reference pixels, where
-- the installed panel measured 621 at 420 units x the font scale). So every
-- width below is the former one x 284 / 420, and the screens and chosen
-- sizes that bound the rule are chosen again for those widths: the widest
-- panel is 568 units, which every screen the rule reads (640 units or more)
-- holds at 100%, so the bounded cases are at the chosen 150%; and 284 units
-- x the largest chosen size (150%) is 426, which the narrowest such screen
-- holds too, so the reference width is never wider than the screen leaves
-- and the fit never has to reduce the applied size for the width.
-- EXPECT fails at eef1608f (the 420-unit reference width). GUARD: no text
-- is drawn smaller for the width; the fit still bounds the applied size;
-- nothing is saved; long names, statuses and the reason stay whole at every
-- width. The screen is UIParent's size as this fixture sets it and widths
-- are its stated font model, not native glyphs.
C.scenario('W1 the panel width follows the text scale, bounded by the screen at the chosen size, once per render',function()
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local wasDetails=P._playDetails
 local saved=P.SavedLayoutRoot()
 C.setup(rawget(saved,'panelScale')==nil,'W1: fixture: no chosen panel size is saved',tostring(rawget(saved,'panelScale')))
 local x0,y0=rawget(saved,'panelX'),rawget(saved,'panelY')
 -- The rule itself: {font scale, screen width, chosen size, width}.
 local ruled,ruleNotes=type(LM.PanelWidth)=='function',{}
 if ruled then
  -- (Unbounded: 284 x the scale, held to 1..2. Bounded at the chosen 150%:
  -- 517 units of an 800-unit screen and 410 of a 640-unit one; a 1024-unit
  -- screen leaves 666 there, more than any width asked for. A 600-unit
  -- screen bounds nothing, though 576 / 1.5 would be under the 568 asked
  -- for. The floor: never under 284, whatever size is given. An unreadable
  -- scale is the reference scale, and an unreadable chosen size or screen
  -- makes no bound of its own.)
  -- (The three original inputs whose chosen size was changed above to reach
  -- a bound stand beside them again, at their own 100%: an 800-, a 640- and
  -- a 600-unit screen at twice the reference text. Each holds the 568 units
  -- asked for there, where the former 840 were bounded at 776 and 616 and
  -- left alone on the 600-unit screen.)
  for _,case in ipairs({{1,1920,1,284},{1.25,1920,1,355},{1.6,1920,1,454},{2,1920,1,568},{3,1920,1,568},{0.5,1920,1,284},
   {1.6,800,1,454},{2,800,1.5,517},{2,640,1.5,410},{1.6,640,1.5,410},{1.6,1024,1.5,454},{2,1024,1.5,568},{2,1024,0.5,568},
   {2,600,1.5,568},{2,0,1,568},{2,math.huge,1,568},{0/0,1920,1,284},{2,800,0,568},{2,800,0/0,568},
   {2,640,3,284},{1,640,1.5,284},
   {2,800,1,568},{2,640,1,568},{2,600,1,568}}) do
   local got=LM.PanelWidth(case[1],case[2],case[3])
   if got~=case[4] then
    ruled=false
    ruleNotes[#ruleNotes+1]=tostring(case[1])..' / '..tostring(case[2])..' / '..tostring(case[3])..' gives '..tostring(got)..', not '..case[4]
   end
  end
  if LM.PanelWidth(2,nil,1)~=568 or LM.PanelWidth(nil,1920,1)~=284 or LM.PanelWidth('x',1920,nil)~=284 then
   ruled=false;ruleNotes[#ruleNotes+1]='a missing or unreadable input is not the reference scale, no bound or 100%'
  end
 else
  ruleNotes[1]='LayoutMetrics has no PanelWidth'
 end
 C.expect(ruled,'W1: the rule: 284 x the font scale (1 to 2), no wider than (screen width - 24) / the chosen size on a screen of 640 units or more, never under 284',
  table.concat(ruleNotes,'; '))
 -- The reference width is the approved one, stated from the draft and the
 -- measured panel it replaces, and the widest and the reference panel fit
 -- every screen the rule reads at 100% and at the largest chosen size.
 C.expect(BASE==math.floor(420*420/621+0.5) and 2*BASE<=640-24 and BASE*1.5<=640-24,
  'W1: the reference width is 420 x 420 / 621 = 284 units; twice that, and 284 at 150%, fit a 640-unit screen less its margin',BASE)
 -- Names as long as localized ones (synthetic words, this file's ASCII).
 local LONGER={
  {text='[Guaranteed offer] Unerschuetterliche Resonanz des ungebrochenen Bundes der Wanderchoere (Uncommon) wanted',highlight=true},
  {text='Hohlglocke der verlorenen Stundengebete (Rare) wanted'},
  {text='[Guaranteed offer] Aschezehnt des wandernden Chores der Tiefe (Uncommon)'},
 }
 local ok,err=pcall(function()
  -- {native height, screen width, chosen size, the width the rule gives}:
  -- the reference size and under it, 125%, the reported 160%, 200% and
  -- above it on a wide screen; then a narrower screen that still holds the
  -- width, screens that bound it at the chosen 150% (800 and 640 units at
  -- native 20, 640 units at the reported 160%) and a chosen 150% the screen
  -- holds whole.
  -- (Native 20 on the 800- and the 640-unit screen at 100% are the original
  -- inputs of the two bounded cases; they stand beside them again. Those
  -- screens bounded the former 840 units at 776 and 616; they hold the
  -- approved 568 whole, so there the rule gives the whole width.)
  for _,case in ipairs({{10,1920,1,284},{8,1920,1,284},{12.5,1920,1,355},{16,1920,1,454},{20,1920,1,568},{30,1920,1,568},
   {16,800,1,454},{20,800,1,568},{20,800,1.5,517},{20,640,1,568},{20,640,1.5,410},{16,640,1.5,410},{16,1024,1.5,454}}) do
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
     -- EXPECT at every size: each width is the approved reference width's
     -- (at eef1608f the rule gave the former 420-unit one's: 420 at the
     -- reference size, which the guard here asked for, and 525 to 840 above
     -- it).
     C.expect(width==want and layout.width==want and width==WantWidth(),
      tag..': the panel is '..want..' units wide',tostring(width)..' / layout '..tostring(layout.width)..' / rule '..tostring(WantWidth()))
     -- (EXPECT: the insets were 8 units at every size; the compact body's
     -- are the draft's 7 pixels at this text scale.)
     C.expect(b.roll.x==Inset() and b.roll.w==width-2*Inset() and b.status.w==width-2*Inset() and b.footer.w==width-2*Inset()
      and area~=nil and math.abs((area[3]-area[1])-(width-2*Inset()))<=0.01,
      tag..': the difficulty band, the offer block and the footer span the panel between its insets, the draft\'s 7 pixels',
      tostring(b.roll.w)..' / '..tostring(b.status.w)..' / '..tostring(b.footer.w)..' in '..tostring(width))
     -- The applied size: a width the rule gave never makes the fit reduce
     -- the chosen size. Only the reference width's floor could be wider
     -- than the screen leaves, and it never is on a screen the rule reads
     -- (stated above), so every case here applies the chosen size whole;
     -- the two guards are stated on the panel's own width, as they held
     -- before.
     C.guard(type(applied)=='number' and width*applied<=screen-24+1,
      tag..': at its applied size the panel is no wider than the screen less the 24-unit margin',tostring(width)..' x '..tostring(applied))
     if width*chosen<=screen-24 then
      C.guard(Near(applied,chosen),tag..': the chosen size is applied whole (the width asks for no reduction)',applied)
     else
      C.guard(Near(applied,(screen-24)/width),tag..': where the panel at its chosen size is wider than the screen leaves, the fit, not the width, reduces the applied size',applied)
     end
     -- EXPECT: no width the rule gives asks the fit for a reduction now (at
     -- eef1608f the 420-unit floor did, on a 640-unit screen at 150%).
     C.expect(want*chosen<=screen-24 and width*chosen<=screen-24 and Near(applied,chosen),
      tag..': the width the rule gives fits the screen at the chosen size, which is applied whole',tostring(width)..' x '..tostring(chosen)..' on '..tostring(screen))
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
     -- (Its whole row: the offer block's width less the destination cell
     -- at its right end; the 4 units of inner insets are gone.)
     local none,noneDetail=NoCharges(b.roll.w-DestinationRoom(false))
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
     -- 420 units too). That the width it leaves is the approved reference
     -- width's is an EXPECT at every size.
     local computations=LM.Stats().computations
     P.Render(m);P.Render(m)
     C.guard(LM.Stats().computations==computations,tag..': a repeated render takes no layout pass',
      LM.Stats().computations-computations)
     C.expect(NexusPanel:GetWidth()==want and NexusPanel._responsiveLayout.width==want,
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
  -- The original screen and text size of the check below, kept: native 16 on
  -- a 1024-unit screen. There the former panel was 672 units at 100% and the
  -- 666 that screen leaves at 150%. The approved panel is 454 units, which
  -- that screen holds at 150% too (681 of its 1000), so the choice of size
  -- changes nothing about the width here and the chosen size is applied
  -- whole: a width the screen does not bound is not touched by the choice.
  UIParent:SetSize(1024,4000)
  P.ResetPanelScale()
  SetNative(16)
  if C.setup(Render(Play())==true,'W1: fixture: the Play panel at native 16 on a 1024-unit screen at 100%') then
   local before=NexusPanel:GetWidth()
   P.SetPanelScale(1.5)
   C.expect(before==454 and NexusPanel:GetWidth()==454 and NexusPanel._responsiveLayout.width==454 and Near(NexusPanel:GetScale(),1.5),
    'W1: 454 units there at 100%; that screen holds them at the chosen 150% too, so the panel stays 454 units wide at the whole chosen size',
    tostring(before)..' -> '..tostring(NexusPanel:GetWidth())..' at '..tostring(NexusPanel:GetScale()))
   P.ResetPanelScale()
   C.expect(NexusPanel:GetWidth()==454 and Near(NexusPanel:GetScale(),1),'W1: and back at 100% it is 454 units still',
    tostring(NexusPanel:GetWidth())..' at '..tostring(NexusPanel:GetScale()))
  end
  -- A choice of size that changes the width lays the panel out at once.
  -- (Beside the original case above, which no longer reaches a bound: native
  -- 20 on an 800-unit screen, where 150% leaves 517 of the 568.)
  UIParent:SetSize(800,4000)
  P.ResetPanelScale()
  SetNative(20)
  if C.setup(Render(Play())==true,'W1: fixture: the Play panel at native 20 on an 800-unit screen at 100%') then
   local before=NexusPanel:GetWidth()
   P.SetPanelScale(1.5)
   C.expect(before==568 and NexusPanel:GetWidth()==517 and NexusPanel._responsiveLayout.width==517 and Near(NexusPanel:GetScale(),1.5),
    'W1: 568 units there at 100%; choosing 150% lays the panel out at once at the 517 units that size leaves, at the whole chosen size',
    tostring(before)..' -> '..tostring(NexusPanel:GetWidth())..' at '..tostring(NexusPanel:GetScale()))
   P.ResetPanelScale()
   C.expect(NexusPanel:GetWidth()==568 and Near(NexusPanel:GetScale(),1),'W1: and back at 100% it is 568 units again',
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
-- the room its text scale asks for and held at the 410 units a 640-unit
-- screen leaves at the chosen 150% (it was held at the former 420-unit
-- reference width), with a short and a long setup note and a short and a
-- long Wishlist name.
-- What a text needs is worked out here from its words and its font in this
-- fixture's stated model; nothing is read from its box. A check is EXPECT
-- where the text needs more than its modelled rows (all it had at aca67cf4)
-- and GUARD where it fits them, which holds before and after.
-- The approved compact panel draws neither view; both keep their texts,
-- their modelled rows and their order, in the compact body: between its
-- insets (the draft's 7 pixels; they were 8 units), one block gap apart
-- (the draft's 5 pixels; it was the layout's 6-unit gap x the scale), with
-- the footer the draft's 12 pixels under the last block and the panel
-- ending 6 pixels under the footer.
-- Typography correction: the setup hint alone no longer spans the body. It
-- stands in the panel's middle in a row of its own, 24 design pixels or
-- more from each side and as narrow as its lines stay even (stated where it
-- is asked, below). It is still measured, whole and at its place in the
-- order, and the gaps over and under it are the same.
C.scenario('M1 the setup and completion texts are measured: whole at native 16 and with long words',function()
 local NOTE='Synthetic setup note that is long enough to need several lines in the panel at every supported text size, '
  ..'so a hint held to two modelled lines would lose its end.'
 local NAME='Synthetic Wishlist with a name as long as a localized one that the completion sentence keeps whole'
 -- Typography correction: a hint that is one long word, as a compound of a
 -- localized language can be (synthetic, this file's ASCII; 29 characters:
 -- wider than half the hint's room and narrower than the room at each size
 -- below, which the fixture check there states).
 local WORD='Wunschlistenzuweisungsvorgang'
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
 -- One text on its box, in a row as wide as the block. With `left` (the
 -- setup hint, which no longer spans the block) the row is the text's own:
 -- `row` wide from `left`.
 local function Row(tag,what,box,modelled,row,left)
  local region=box and TextAt(box) or nil
  if not C.setup(region~=nil,tag..': fixture: the '..what..' is shown on its box') then return nil end
  local needs=Needs(region,row)
  local want=math.max(modelled,needs)
  local detail=what..': box '..tostring(box.w)..'x'..tostring(box.h)..' at '..tostring(box.x)..', text '..tostring(region:GetHeight())..' for '
   ..tostring(region:GetStringHeight())..', needs '..tostring(needs)..' in '..tostring(row)..' ('..tostring(modelled)..' modelled)'
  print('OBSERVED',tag,detail)
  if left==nil then
   -- (The row's width is the compact body's, between the draft's insets:
   -- an EXPECT, as it was the panel less 16 units. The height check is what
   -- it was.)
   C.expect(box.w==row and box.x==Inset(),tag..': the '..what..' spans the body between its insets',detail)
  else
   -- (Typography correction, EXPECT: its own row, and the text is drawn at
   -- the width it is measured for below: its region is that row wide.)
   C.expect(box.w==row and box.x==left and region:GetWidth()==row,
    tag..': the '..what..' has a row of its own, '..tostring(row)..' units wide from '..tostring(left)..', and is drawn at that width',detail)
  end
  ;(needs>modelled and C.expect or C.guard)(box.h==want and region:GetHeight()==want
   and region:GetHeight()+0.5>=region:GetStringHeight(),
   tag..': the '..what..' is whole in its row: as tall as its wrapped text, never under its modelled rows',detail)
  return region
 end
 local effects=Effects()
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local ok,err=pcall(function()
  -- {native height, held at the 410 units the screen leaves}.
  for _,case in ipairs({{10,false},{16,false},{16,true}}) do
   local native,held=case[1],case[2]
   if held then UIParent:SetSize(640,4000);P.SetPanelScale(1.5) else P.ResetPanelScale();UIParent:SetSize(1920,4000) end
   SetNative(native)
   local where='M1 native '..tostring(native)..(held and ' in the 410-unit panel' or '')
   -- Two blocks, or a block and the footer, the draft's `px` apart.
   local function Apart(above,below,px) return Drawn(px,below.y-(above.y+above.h)) end
   -- The setup view: its title, and a note as its hint.
   for _,note in ipairs({'Synthetic hint.',NOTE,WORD}) do
    local tag=where..', setup, '..(note==NOTE and 'a long note' or (note==WORD and 'one long word' or 'a short note'))
    if C.setup(P.Render(Setup(note))==true,tag..': fixture: the setup view renders') then
     local layout=NexusPanel._responsiveLayout
     local b=layout.boxes
     local row=NexusPanel:GetWidth()-2*Inset()
     if C.setup(b.setupTitle and b.setupHint and b.setupAssign and b.setupCreate and b.footer and (not held or NexusPanel:GetWidth()==410),
      tag..': fixture: the layout holds the title, the hint, both buttons and the footer',NexusPanel:GetWidth()) then
      Row(tag,'setup title',b.setupTitle,layout.large,row)
      -- Typography correction. EXPECT: the hint spanned the body between its
      -- insets, so a sentence could run from edge to edge over a short last
      -- line. Its room is now the panel less 24 design pixels at each side,
      -- and in that room it stands in the panel's middle as narrow as its
      -- lines stay even: the narrowest width at which its words need no more
      -- lines than across the whole room, never under half the room and
      -- never under its longest word (a hint with a word as wide as the room
      -- keeps the whole room). That width is counted here from the note's
      -- words in the secondary role in this fixture's model (G.Rows, as
      -- Needs counts; a word's width as N10 counts it); nothing is read from
      -- the box. What the hint needs is then asked at that width, which is
      -- also the width its text is drawn at (Row).
      local wide=NexusPanel:GetWidth()
      local room=wide-2*Design(24)
      local hintSize=Role('secondary')
      local function HintLines(width) return math.max(1,G.Rows(note,width,CHAR*hintSize)) end
      local across=HintLines(room)
      local longest=0
      for word in note:gmatch('%S+') do longest=math.max(longest,G.Length(word)*CHAR*hintSize) end
      local even=room
      for width=math.max(math.ceil(room/2),math.ceil(longest)),room do
       if HintLines(width)<=across then even=width;break end
      end
      local hintLeft=math.floor((wide-even)/2+0.5)
      C.setup(room>=2 and even>=math.ceil(room/2) and even<=room and hintLeft>=Design(24) and wide-(hintLeft+even)>=Design(24)
       and longest<=room and (note~=WORD or math.ceil(longest)>math.ceil(room/2)),
       tag..': fixture: the hint\'s room is the panel less 24 design pixels at each side, and its even width stands inside it',
       tostring(even)..' of '..tostring(room)..' from '..tostring(hintLeft)..' in '..tostring(wide)..', '..tostring(across)
       ..' line(s), longest word '..string.format('%.1f',longest))
      local hint=Row(tag,'setup hint',b.setupHint,2*layout.small,even,hintLeft)
      C.setup(hint~=nil and G.Visible(hint:GetText() or '')==note and Near(Size(hint),hintSize),
       tag..': fixture: the hint is the note, whole, in the secondary role',hint and hint:GetText())
      -- No word is cut for even lines: the hint's row is at least as wide
      -- as its longest word. GUARD: it held while the hint spanned the body
      -- and must hold in the hint's own row. The one-word note is what asks
      -- it there: its word is wider than half the room, so a row held to
      -- its lines alone would be narrower than the word.
      C.guard(longest<=b.setupHint.w+0.01,
       tag..': no word of the hint is wider than its row',string.format('%.1f',longest)..' in '..tostring(b.setupHint.w))
      -- EXPECT: the order is as it was; the distances are the draft's (the
      -- guard that stood here asked for the layout's own gap between each
      -- pair and 6 units under the footer). (The hint's left edge was the
      -- body's inset and is its own row's now, asked above. The gaps over
      -- and under the hint, the buttons, the footer and the panel's end are
      -- as they were.)
      C.expect(b.setupTitle.x==Inset()
       and Apart(b.setupTitle,b.setupHint,5) and Apart(b.setupHint,b.setupAssign,5)
       and Apart(b.setupAssign,b.setupCreate,5) and Apart(b.setupCreate,b.footer,12)
       and NexusPanel:GetHeight()==layout.height and Drawn(6,layout.height-(b.footer.y+b.footer.h)),
       tag..': the hint and both buttons follow one 5-pixel block gap apart, the footer 12 pixels under them, and the panel ends 6 pixels under the footer',
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
     local row=NexusPanel:GetWidth()-2*Inset()
     if C.setup(b.completeTitle and b.completeText and b.footer and (not held or NexusPanel:GetWidth()==410),
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
      -- (EXPECT: the gap under the badge was the layout's own; it is the
      -- draft's block gap. The footer stands under the sentence as before.)
      C.expect(b.completeTitle.x==Inset() and Apart(b.completeTitle,b.completeText,5) and b.footer.y>=b.completeText.y+b.completeText.h
       and NexusPanel:GetHeight()==layout.height and Drawn(6,layout.height-(b.footer.y+b.footer.h)),
       tag..': the sentence follows the badge one 5-pixel block gap under it, the footer stands under the sentence and the panel is the layout height',
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
-- The approved compact panel: with Auto OFF the heading over the offers is
-- one form, "Your offers", with the destination in a cell of its own at the
-- row's right end, so there is nothing to fit and it is whole in both
-- Details states (asked at the end of this scenario, and in N2 and N3). The
-- fitted forms stand where the heading still says its state and its
-- destination itself: with Auto ON, which is the heading this scenario now
-- renders (it rendered the Auto OFF one). There the row the heading has is
-- the offer block's width less what stands beside it in that state: the
-- "Auto explained" control while it shares the row (layout.headingReserve,
-- as in R1; it shares the row only while it and a charges row's 76 units
-- take no more than half the block, so with the charges it has a row of its
-- own), and the 76 units of a charges row while Details is open. Each state
-- is asked for the longest form that fits the row it has, at the first
-- native height of the list at which the two states need different forms,
-- so a heading that kept the other state's wording fails. On this
-- fixture's reference panel the control shares the row with Details closed
-- and leaves it with Details open, so the open panel has the wider row and
-- the longer form.
-- The panel is on a 640-unit screen at the chosen 150% size (W1, N9). Which
-- form each state needs is worked out here from the Readout's forms, the
-- shown line's other words and this fixture's font model (Form); nothing is
-- read from the panel's own fitting.
-- EXPECT fails at aca67cf4 by design: there the row and its cell stood with
-- Details closed, so the closed panel was worded for a row that kept the
-- cell's room. GUARD: the charges cell and its place with Details open;
-- opening and closing Details takes no game action. Native glyph widths:
-- NOT RUN.
-- v9 (Root's ruling SPEC-A2): beside a charges row the heading has the row
-- less the charges cell that row of counts has (Cell: its own one-line
-- width, never under 72 px) and the 4 px gap, where the text above says the
-- 76 px of the minimum cell and its gap; at a text size where the row of
-- counts is no wider than 72 px the two are the same.
C.scenario('C1 the offer heading is worded for the row it has: its whole row with Details closed, the row beside the charges with Details open',function()
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local scale0=rawget(P.SavedLayoutRoot(),'panelScale')
 local before=Effects()
 local found=false
 local ok,err=pcall(KeepDetails,function()
  UIParent:SetSize(640,4000)
  P.SetPanelScale(1.5)
  local head,charges,hover=NexusPanel._rollStatus,NexusPanel._chargesText,NexusPanel._chargesHover
  -- The same board with Auto ON: the heading that is still a fitted form.
  local function Play() return Model({auto=true,cards=LONG,recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2}) end
  local forms=R.OfferHeadingForms(true)
  -- One Details state of that panel: the row its heading has (the offer
  -- block less the Auto control's room while it shares the row), the form
  -- shown and the form that row needs (with Details open the row also
  -- keeps a charges row's 76 units).
  local function State(open)
   P._playDetails=open
   if not (Render(Play())==true and NexusPanel:GetWidth()==WantWidth()) then return nil end
   local layout=NexusPanel._responsiveLayout
   local st={reserve=tonumber(layout.headingReserve) or 0,block=layout.boxes.roll.w,roll=layout.boxes.roll.h,panel=NexusPanel:GetHeight()}
   st.row=st.block-st.reserve
   -- (v9: beside the charges cell this row's own row of counts has, Cell;
   -- it was the 76 px of the 72 px minimum cell and its gap.)
   st.cell=open and Cell(st.row,Natural(charges)) or nil
   st.shown,st.want=Form(head,st.row,true,open and (st.cell+4) or 0)
   st.words=G.Visible(head:GetText() or '')
   st.natural,st.width,st.height,st.lines=Natural(head),head:GetWidth(),head:GetHeight(),math.ceil(head:GetStringHeight())
   -- Whole: on one line in its box, or (the shortest form in a row it does
   -- not fit) wrapped in a box as tall as its lines.
   st.whole=st.natural<=st.width+0.01 or (st.want==#forms and st.height+0.5>=st.lines)
   return st
  end
  for _,height in ipairs({10,10.5,11,11.5,12,12.5,13,13.5,14,14.5,15,15.5,16,17,18,19,20}) do
   SetNative(height)
   local closed=State(false)
   local open=closed and closed.shown~=nil and State(true) or nil
   if open and open.shown~=nil and closed.want~=open.want then
    found=true
    local tag='C1 native '..tostring(height)..' in the '..tostring(NexusPanel:GetWidth())..'-unit panel, Auto ON'
    print('OBSERVED',tag,'closed "'..closed.words..'" form '..tostring(closed.shown)..' want '..tostring(closed.want)..' in a row of '..tostring(closed.row),
     'open "'..open.words..'" form '..tostring(open.shown)..' want '..tostring(open.want)..' in a row of '..tostring(open.row)
      ..' less the '..tostring(open.cell)..'-unit charges cell and its gap')
    C.setup(closed.block==NexusPanel:GetWidth()-2*Inset() and open.block==closed.block,
     tag..': fixture: the offer block spans the panel between its insets in both Details states',closed.block)
    -- Details open (the panel as it stands now).
    local cell=open.cell
    local hr,cr,area=Rect(head),Rect(charges),Rect(NexusPanel._rollArea)
    C.guard(charges:IsShown() and hover:IsShown() and ChargeRows()==1,
     tag..': with Details open the charges row is on the panel once, with its hover',ChargeRows())
    -- (EXPECT: the row the heading has beside the charges is the compact
    -- block's, and the Auto control leaves it there. v9: the form is the
    -- longest that fits beside the charges cell this row of counts has; it
    -- was fitted beside the 72 px minimum cell.)
    C.expect(open.shown==open.want and open.whole,
     tag..': with Details open the heading shows the longest form that fits its row beside the charges cell',
     'form '..tostring(open.shown)..' want '..tostring(open.want)..'; natural '..string.format('%.1f',open.natural)..' in '..tostring(open.width))
    ;(cell>72 and C.expect or C.guard)(charges:GetWidth()==cell and head:GetWidth()==open.row-cell-4 and hr~=nil and cr~=nil and area~=nil and hr[3]<=cr[1]+0.01
     and G.Inside(cr,area,0.01),
     tag..': the charges cell is the layout-derived '..cell..' px; the heading keeps the rest of the row less the cell and its gap and ends before the cell, inside the offer block',
     Text(hr)..' '..Text(cr)..' in '..Text(area))
    -- Details closed again.
    local again=State(false)
    local none,noneDetail=NoCharges(closed.row)
    C.expect(again~=nil and none and again.shown==closed.want and again.whole and closed.shown==closed.want and closed.whole,
     tag..': with Details closed there is no charges row, hover or cell, and the heading shows the longest form that fits its whole row',
     'form '..tostring(again and again.shown)..' want '..tostring(closed.want)..'; natural '..string.format('%.1f',again and again.natural or -1)
     ..' in '..tostring(again and again.width)..'; '..noneDetail)
    C.expect(again~=nil and again.words==closed.words and again.height==closed.height and again.roll==closed.roll and again.panel==closed.panel,
     tag..': closing Details gives back the heading, the heading row, the offer block and the panel as they were',
     tostring(again and again.height)..' / '..tostring(closed.height)..', offer block '..tostring(again and again.roll)..' / '..tostring(closed.roll)
     ..', panel '..tostring(again and again.panel)..' / '..tostring(closed.panel))
    -- Auto OFF on the same panel, at the same text size: the approved
    -- compact heading is one form in both Details states, whole on its
    -- line, with the destination in its own cell (after a dot while the
    -- charges stand before it). EXPECT: at eef1608f this heading was a
    -- fitted form, shorter beside the charges.
    local off=Model({auto=false,cards=LONG,recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2})
    local words=(Nexus.Localization.Text('panel.heading.your_offers'))
    local states={}
    for _,opened in ipairs({false,true,false}) do
     P._playDetails=opened
     local rendered=Render(off)==true
     local slotCell=NexusPanel._offerSlot
     states[#states+1]=rendered and G.Visible(head:GetText() or '')==words and Natural(head)<=head:GetWidth()+0.01
      and math.ceil(head:GetStringHeight())<=head:GetHeight()
      and slotCell~=nil and slotCell:IsShown() and G.Visible(slotCell:GetText() or '')==Destination(opened)
      and charges:IsShown()==opened and ChargeRows()==(opened and 1 or 0)
    end
    C.expect(#states==3 and states[1] and states[2] and states[3],
     tag:gsub(', Auto ON$','')..', Auto OFF: the heading is the one compact form, "Your offers", whole with Details closed, open and closed again; the destination cell follows the charges',
     tostring(states[1])..' / '..tostring(states[2])..' / '..tostring(states[3]))
    P._playDetails=false
    break
   end
  end
 end)
 if scale0==nil then P.ResetPanelScale() else P.SetPanelScale(scale0) end
 UIParent:SetSize(w0,h0)
 SetNative(10)
 Render(Play())
 C.setup(ok,'C1: fixture: the scenario ran',err)
 C.setup(found,'C1: fixture: a native height at which the heading needs one form with Details closed and another with Details open')
 C.guard(Effects()==before,'C1: opening and closing Details takes no game action, sends nothing and leaves Auto as it was',Effects())
 C.guard(NATIVE.nativeSets==0,'C1: no game font object is set',NATIVE.nativeSets)
end)

----------------------------------------------------------------------------
-- N8: what must not change.
----------------------------------------------------------------------------
C.scenario('N8 display-only cards, collapsed Details and the passive grip are unchanged; the header slots are the compact draft\'s',function()
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
 -- The line-1 slots. EXPECT: the guard that stood here pinned the former
 -- fixed slots at every text size (top 7, height 22, gap 8, edge 10, Close
 -- 24, Options 92 from 42, Auto 84 from 142, 234 reserved, the title from
 -- 36, the grip 24 x 24 at 8). The approved compact header's are the
 -- draft's at this text scale (Line1 states them from the controls' own
 -- words): at native 16 the inset is 8 units, Close 26, the gaps 6, Options
 -- 83 (its 68 units of words and the draft's 14 pixels), the Auto control
 -- 95 (its widest label's 78 units and 16 pixels), so 230 units are
 -- reserved and the title starts at 40, after the 26-unit grip (the draft's
 -- 24 pixels; never under 24 units). The controls are the draft's 22 pixels
 -- high in the middle of line 1's row.
 -- (Typography correction, EXPECT: Options was 89 and the Auto control 102,
 -- with 243 units reserved, while their words were the 12-unit primary role
 -- x 1.6: 74 and 85 units. In the 11-unit control role x 1.6 the same seven
 -- and eight characters are 67.76 and 77.44 units in this model, so 68 and
 -- 78. The room around them, the gaps, Close, the inset and the grip are
 -- unchanged.)
 local s,drawn=P.HeaderSlots(),Line1()
 local controls=math.max(Design(22),Grip()-2*Design(1))
 C.expect(s.top==DesignY(5)+math.floor((controls-Design(22))/2) and s.height==Design(22) and s.gap==Design(6) and s.gap==6
  and s.edge==Inset() and s.edge==8 and s.closeWidth==Design(24) and s.closeWidth==26
  and s.options==drawn.edge+drawn.close+drawn.gap and s.optionsWidth==drawn.options and s.optionsWidth==83
  and s.auto==s.options+s.optionsWidth+drawn.gap and s.autoWidth==drawn.auto and s.autoWidth==95
  and s.reserved==drawn.reserved and s.reserved==230 and s.titleLeft==drawn.titleLeft and s.titleLeft==40
  and s.gripX==Inset() and s.gripWidth==Grip() and s.gripHeight==Grip() and Grip()==26,
  'N8: the header line 1 slots are the compact draft\'s at this text scale: each control as wide as its words need, 230 units reserved, the title from 40',
  tostring(s.top)..' '..tostring(s.height)..' '..tostring(s.gap)..' '..tostring(s.edge)..' '..tostring(s.closeWidth)..' '..tostring(s.options)..'+'
  ..tostring(s.optionsWidth)..' '..tostring(s.auto)..'+'..tostring(s.autoWidth)..' '..tostring(s.reserved)..' '..tostring(s.titleLeft)..' '..tostring(s.gripWidth))
 local grip=P.EnsureHeaderGrip()
 -- The grip's size (EXPECT: it was 24 x 24 units at every text size; it is
 -- the draft's 24 pixels at this scale and never under 24 x 24 units, so
 -- the Shift-drag target is never smaller than it was), and what it is
 -- (GUARD, unchanged): a passive drag surface with no click of its own.
 C.expect(grip and grip:GetWidth()==Grip() and grip:GetHeight()==Grip() and grip:GetWidth()>=24 and grip:GetHeight()>=24,
  'N8: the grip is the draft\'s 24 pixels, never under 24 x 24 units',grip and (tostring(grip:GetWidth())..'x'..tostring(grip:GetHeight())))
 C.guard(grip and grip._nexusPassiveDrag==true and grip:GetScript('OnClick')==nil,
  'N8: the grip stays a passive drag surface')
 C.guard(Effects()==baselineEffects,'N8: no render, hover or font change took a game action, sent anything or changed Auto',Effects())
end)

----------------------------------------------------------------------------
-- G1 (v22, owner brief): the drag grip's drawn box. The Shift-drag target is
-- the grip button itself, the slot the header gives it: at least 24 x 24
-- units (the maintainer's 2026-11-08 choice; N8 and the header checks above
-- pin it, unchanged). What the grip draws (its border, its fill and its
-- hover highlight) is a separate thing: the draft's grip is 24 design pixels,
-- which at native 10 is 16 units, while the target floor is 24. EXPECT
-- (failing on f727 by design, where the border and the highlight cover the
-- whole target): the drawn box is max(15, the draft's 24 pixels) units
-- square, never over 20 units, centred in the target: 16 at native 10, 19 at
-- 12, 20 at 14 and 20 at 16 (targets 24, 24, 24 and 26). 15 is the least box
-- that holds the fixed 9 x 13 dot cluster with a one-unit edge round it.
-- The 20-unit cap (Root's choice within the owner's request for a smaller
-- grip, 2026-11-13): at native 16 the draft's 24 pixels are 26 units, the
-- whole 26-unit target, so without a cap the player who reported a large
-- grip would see no smaller box. The cap is on the drawn box only; the
-- target, the header slots, the dots' centring and the passive Shift drag
-- and release are unchanged. GUARD: the
-- target, the passive Shift drag (no click of its own; drag start and stop
-- kept), the fill inside the border box and the six 3 x 3 dots, a 9 x 13
-- cluster, inside the drawn box; no game action. Measured on the created
-- button and its own textures: the button's and the dots' anchors resolve
-- as everywhere here; a texture placed with SetAllPoints covers the frame it
-- was given (Install records it, as the client places it). Native pixels:
-- units x the effective scale are nominal pixels only; NOT RUN. Native 10 is
-- this model's smallest scale (Scale never goes under 1), so the 15-unit
-- floor itself is not reached here.
----------------------------------------------------------------------------
C.scenario('G1 the grip keeps its at-least-24-unit Shift-drag target and draws a compact box centred in it, the six dots inside',function()
 -- The rectangle a texture covers: its own anchors, or what SetAllPoints gave it.
 local function ArtRect(texture)
  if type(texture)~='table' then return nil end
  if type(texture.GetNumPoints)=='function' and texture:GetNumPoints()>0 then return Rect(texture) end
  local to=rawget(texture,'_allPointsTo')
  if type(to)=='table' then return Rect(to) end
  return nil
 end
 local before=Effects()
 for _,height in ipairs({10,12,14,16}) do
  local tag='G1 native '..height
  SetNative(height)
  C.setup(Render(Play())==true,tag..': fixture: the Play panel renders')
  local grip=P.EnsureHeaderGrip()
  local hit=grip and Rect(grip) or nil
  if C.setup(hit~=nil and grip.edge~=nil and grip.fill~=nil and grip.hover~=nil and type(grip.dots)=='table' and #grip.dots==6,
   tag..': fixture: the created grip with its border, fill and hover textures and its six dots') then
   local target=Grip()
   C.guard(hit[3]-hit[1]==target and hit[4]-hit[2]==target and target>=24,
    tag..': the Shift-drag target is unchanged: the grip slot, at least 24 x 24 units',G.Text(hit))
   C.guard(grip._nexusPassiveDrag==true and grip:GetScript('OnClick')==nil
    and grip:GetScript('OnDragStart')~=nil and grip:GetScript('OnDragStop')~=nil,
    tag..': the grip stays a passive Shift-drag surface with no click of its own')
   local want=math.min(20,math.max(15,Design(24)))
   local cx,cy=(hit[1]+hit[3])/2,(hit[2]+hit[4])/2
   local function Box(r)
    return r~=nil and Near(r[3]-r[1],want) and Near(r[4]-r[2],want)
     and math.abs((r[1]+r[3])/2-cx)<=0.5 and math.abs((r[2]+r[4])/2-cy)<=0.5 and G.Inside(r,hit)
   end
   local edge,glow,fill=ArtRect(grip.edge),ArtRect(grip.hover),ArtRect(grip.fill)
   C.expect(Box(edge),tag..': the drawn border box is max(15, the draft\'s 24 pixels), at most 20, = '..want
    ..' units square, centred in the '..target..'-unit target',edge and (G.Text(edge)..' in '..G.Text(hit)) or 'unresolved')
   C.expect(Box(glow),tag..': the hover highlight is that same drawn box, not the whole target',
    glow and (G.Text(glow)..' in '..G.Text(hit)) or 'unresolved')
   C.guard(fill~=nil and edge~=nil and G.Inside(fill,edge) and fill[3]>fill[1] and fill[4]>fill[2],
    tag..': the fill lies inside the border box',(fill and G.Text(fill) or 'unresolved')..' / '..(edge and G.Text(edge) or 'unresolved'))
   local inside,l,t,r,b=edge~=nil,nil,nil,nil,nil
   for _,dot in ipairs(grip.dots) do
    local d=Rect(dot)
    if not (d and edge and G.Inside(d,edge)) then inside=false end
    if d then l,t=math.min(l or d[1],d[1]),math.min(t or d[2],d[2]);r,b=math.max(r or d[3],d[3]),math.max(b or d[4],d[4]) end
   end
   C.guard(inside and l~=nil and r-l==9 and b-t==13,
    tag..': the six 3 x 3 dots, a 9 x 13 cluster, lie inside the drawn box',
    (l and string.format('[%.0f,%.0f %.0fx%.0f]',l,t,r-l,b-t) or 'unresolved')..' / '..(edge and G.Text(edge) or 'unresolved'))
  end
 end
 C.guard(Effects()==before,'G1: no render took a game action, sent anything or changed Auto',Effects())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(native-derived owned fonts, the main panel roles and the layout-derived charges cell at synthetic native heights 12 / 16 / 20; a stated font model; native NOT RUN)')
