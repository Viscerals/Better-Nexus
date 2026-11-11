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
-- at the 420 px panel and at a 272 px roll box; a native height that changes
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
local function Form(head,row,auto)
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
  if (G.Length(form)+rest)*CHAR*Size(head)<=row-76 then want=i;break end
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
    if edge and tr and tr[1]<edge-0.01 then ordered=false end
    edge=tr and tr[3] or edge
   end
  end
  local nr=Rect(card.name)
  if nr and cr then
   -- The room of the three texts: from the name's left, after the icon square and its gap, to the last text's right.
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
 C.guard(inside and ordered and apart,tag..': the rows are compact, in order, apart and inside the roll area',detail)
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
-- N2: every role at native heights 12, 16 and 20 on the 420 px panel.
----------------------------------------------------------------------------
local function Roles(height)
 local tag='N2 native '..height
 SetNative(height)
 C.setup(Render(Play())==true,tag..': fixture: the Play panel renders with charges, the difficulty card and long names')
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
 C.guard(NexusPanel:GetWidth()==420 and NexusPanel:GetHeight()==layout.height,tag..': the panel keeps its 420 px width and the layout height')

 -- Offer rows, heading and body.
 local area=Rect(NexusPanel._rollArea)
 OfferRows(tag,area,small,LONG,C.expect)
 local head,body=NexusPanel._rollStatus,NexusPanel._rollRec
 C.expect(Near(Size(head),small) and head:GetHeight()>=small-0.01 and Near(Size(body),small),
  tag..': the offer heading and the recommendation body are drawn at the small size in rows that tall',
  tostring(Size(head))..' in '..tostring(head:GetHeight())..'; body '..tostring(Size(body)))
 local bodyRect=Rect(body)
 C.guard(bodyRect and G.Inside(bodyRect,area,0.01),tag..': the body stays inside the roll area',Text(bodyRect))

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
 C.expect(charges:GetHeight()>=small-0.01,tag..': the charges cell is as tall as the font it holds',charges:GetHeight())
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

 -- Header lines (owned normal font).
 local lines={NexusPanel._contextTitle,NexusPanel._contextBuild,NexusPanel._contextWishlist}
 local headerFonts,headerRows,headerApart,headerInside=true,true,true,true
 local headerBox=layout.boxes.header
 local headerRect={headerBox.x,headerBox.y,headerBox.x+headerBox.w,headerBox.y+headerBox.h}
 local rects,notes={}, {}
 for i,line in ipairs(lines) do
  rects[i]=Rect(line)
  notes[#notes+1]=Text(rects[i])..' font='..tostring(Size(line))
  -- Approved panel cleanup: the title has its own 15-unit role; the Build
  -- and Wishlist lines stay primary text.
  if not Near(Size(line),i==1 and Role('title') or normal) then headerFonts=false end
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
 C.guard(rects[1] and rects[1][1]==36 and rects[1][2]==8 and lines[1]:GetHeight()==20,
  tag..': the title keeps header line 1\'s literal 20 px row at 36, 8',Text(rects[1]))
 C.guard(headerApart and headerInside,tag..': the header lines are apart and inside the header the layout reserves',headerDetail)
 local switch,change=Rect(NexusPanel._switchBtn),Rect(NexusPanel._contextChange)
 C.guard(switch and change and G.Apart(switch,change) and rects[2] and rects[3]
  and switch[2]<=rects[2][2] and switch[4]>=rects[2][2] and change[2]<=rects[3][2] and change[4]>=rects[3][2],
  tag..': My Builds and Change stay beside their own lines, apart',Text(switch)..' '..Text(change))

 -- Difficulty card (owned normal and small fonts in its own boxes).
 local card,tier,ash,gain=StatusCard()
 if not C.setup(card and tier and ash and gain and card:IsShown(),tag..': fixture: the difficulty card and its three texts are found') then return end
 local cardRect,tierRect,ashRect,gainRect=Rect(card),Rect(tier),Rect(ash),Rect(gain)
 local statusDetail='card '..Text(cardRect)..' tier '..Text(tierRect)..' font='..tostring(Size(tier))
  ..' ash '..Text(ashRect)..' font='..tostring(Size(ash))..' gain '..Text(gainRect)..' font='..tostring(Size(gain))
 print('OBSERVED',tag,statusDetail)
 C.expect(Near(Size(tier),normal) and Near(Size(ash),normal) and Near(Size(gain),normal),
  tag..': the difficulty card\'s tier, Soul Ash and multiplier use the normal (primary) size',statusDetail)
 ;(height>=16 and C.expect or C.guard)(tier:GetHeight()>=normal-0.01 and ash:GetHeight()>=normal-0.01 and gain:GetHeight()>=normal-0.01,
  tag..': each difficulty card text box is at least as tall as its font',statusDetail)
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
 C.scenario('N2 roles at native height '..height,function() Roles(height) end)
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
 -- The roll area takes the narrow box (the panel itself always asks for 420).
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
 -- functions (the panel itself always lays out at 420 px): the Play
 -- fixture's slot heading, then a preview heading with its shorter forms.
 -- Before revision 2 the panel has no cell resolver: its cell is 72 px.
 local head,charges=NexusPanel._rollStatus,NexusPanel._chargesText
 local row=box.w-4
 for _,case in ipairs({{'slot heading',false,2},{'preview heading',nil,0}}) do
  P.SetOfferHeading(head,{auto=case[2],_nexusChargeLine=charges:GetText()},case[3],layout)
  local cell=Cell(row,head,true)
  local actual=type(P.ChargesCell)=='function' and P.ChargesCell(layout,head) or 72
  local shownForm,wantForm=Form(head,row,case[2])
  local detail='cell '..tostring(actual)..' want '..cell..'; row '..row..'; heading "'..G.Visible(head:GetText() or '')..'" natural '
   ..string.format('%.1f',Natural(head))..'; charges natural '..string.format('%.1f',Natural(charges))
  print('OBSERVED',tag,case[1],detail,'form='..tostring(shownForm)..'/'..tostring(wantForm))
  C.guard(shownForm~=nil and shownForm==wantForm,tag..', '..case[1]..': the form fitted beside the 72 px minimum cell is shown, as before',detail)
  ;(cell>72 and C.expect or C.guard)(actual==cell,tag..', '..case[1]..': the charges cell is the layout-derived '..cell..' px',detail)
  C.guard(actual>=72 and actual+4<=row and (Natural(head)>row-76 or Natural(head)<=row-actual-4+0.01),
   tag..', '..case[1]..': the cell is never under 72 px, stays in the row and leaves a fitted heading whole',detail)
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
C.scenario('N7 a native height of 10, or no readable reference, keeps 10 / 12 / 14 and the former geometry',function()
 SetNative(10)
 C.setup(Render(Play())==true,'N7: fixture: the Play panel at native 10')
 local layout=NexusPanel._responsiveLayout
 local fontScale=LM.RuntimeMetrics()
 C.guard(Owned('small')==10 and Owned('normal')==12 and Owned('large')==14 and fontScale==1,
  'N7: the owned fonts are exactly 10 / 12 / 14 at font scale 1',tostring(Owned('small'))..'/'..tostring(Owned('normal'))..'/'..tostring(Owned('large')))
 C.guard(layout.small==11 and layout.normal==14 and layout.large==16 and layout.gap==6,'N7: the layout rows are 11 / 14 / 16 with a 6 px gap')
 local cards=NexusPanel._offerCards
 -- Approved panel cleanup (full offer names, wrapped, no line cap): a row
 -- whose name fits its column keeps the 15 px model row (row 2); a name
 -- longer than its column wraps and its row is as tall as the wrapped name
 -- (row 1's long name takes two 14 px lines of the 12 px font here: 28).
 -- Approved panel cleanup (the selected offer's complete reason within its
 -- own row, not repeated under the rows): row 1 is this fixture's selected
 -- offer, so under its wrapped texts (the tallest of name, quality and tag)
 -- it also holds the recommendation's reason, and is as tall as both. The
 -- former literal 28 was the wrapped name alone, with the reason below the
 -- three rows.
 local reason=NexusPanel._rollRec
 local texts=math.max(cards[1].name:GetHeight(),cards[1].quality:GetHeight(),cards[1].tag:GetHeight())
 local rowRect,reasonRect=Rect(cards[1]),Rect(reason)
 print('OBSERVED','N7 row 1='..tostring(cards[1]:GetHeight())..' name='..tostring(cards[1].name:GetHeight())
  ..' quality='..tostring(cards[1].quality:GetHeight())..' tag='..tostring(cards[1].tag:GetHeight())
  ..' reason='..tostring(reason:GetHeight())..' "'..G.Visible(reason:GetText() or '')..'" row 2='..tostring(cards[2]:GetHeight()))
 C.guard(cards[2]:GetHeight()==15 and cards[2].name:GetHeight()==15 and cards[1].name:GetHeight()==28
  and reason:IsShown() and G.Visible(reason:GetText() or '')~='' and rowRect and reasonRect and G.Inside(reasonRect,rowRect,0.01)
  -- The row is its texts and its reason, with no more than the layout's
  -- gap between and around them (no reserved empty band).
  and reason:GetHeight()+0.5>=reason:GetStringHeight()
  and cards[1]:GetHeight()>=texts+reason:GetHeight() and cards[1]:GetHeight()<=texts+reason:GetHeight()+layout.gap
  and Size(cards[1].name)==12 and Size(cards[1].tag)==11,
  'N7: an offer row is 15 px for the 12 px name and 11 px tag (its 11 px line with a 2 px row gap above and below), as tall as a wrapped name needs, and the selected row also holds its reason',
  tostring(cards[1]:GetHeight())..' / '..tostring(cards[2]:GetHeight()))
 C.guard(NexusPanel._chargesText:GetWidth()==72 and NexusPanel._rollStatus:GetWidth()==layout.boxes.roll.w-4-76,
  'N7: the charges cell is 72 px and the heading keeps the rest less 76',NexusPanel._chargesText:GetWidth())
 local title,build,wishlist=Rect(NexusPanel._contextTitle),Rect(NexusPanel._contextBuild),Rect(NexusPanel._contextWishlist)
 -- Approved compact insets and gaps: the Wishlist line follows the Build
 -- line's own row after a 2-unit gap (32 + 20 + 2 = 54; formerly a fixed 57,
 -- 5 units under it).
 C.guard(title and build and wishlist and title[2]==8 and build[2]==32 and wishlist[2]==build[4]+2 and wishlist[2]==54
  and NexusPanel._contextTitle:GetHeight()==20 and NexusPanel._contextBuild:GetHeight()==20
  -- Approved panel cleanup (full Build and Wishlist names, wrapped): a line
  -- whose text fits keeps its 20 px row (the Build line here); this
  -- fixture's Wishlist line is longer than its 286 px and is as tall as its
  -- wrapped text instead of being shortened.
  and NexusPanel._contextWishlist:GetHeight()>=20
  and NexusPanel._contextWishlist:GetHeight()+0.5>=NexusPanel._contextWishlist:GetStringHeight()
  and build[1]==12 and wishlist[1]==12,'N7: the header lines are at 8 / 32 / 54, in 20 px rows or as tall as their wrapped text',
  Text(title)..' '..Text(build)..' '..Text(wishlist))
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
 SetNative(height)
 if not C.setup(Render(model)==true and #(P._lastModel.cards or {})==0,tag..': fixture: the panel renders a heading without offer cards') then return end
 local layout=NexusPanel._responsiveLayout
 local head,charges=NexusPanel._rollStatus,NexusPanel._chargesText
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
end
for _,height in ipairs({12,16,20}) do
 C.scenario('R1 headings without offer cards at native height '..height,function()
  Fixed(height,'Auto OFF with a recommendation',Model({auto=false,recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2}))
  Fixed(height,'Auto ON, paused',Model({auto=true,paused='combat',recommendation='Take a needed Echo',charges=CHARGES,serverStatus=SERVER,slot=2}))
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
  C.expect(Near(Size(NexusPanel._contextTitle),15*scale),tag..': the panel title is its own 15-unit role, x the native scale',
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
C.scenario('N9 the wrapped Wishlist line is measured again when only the font changes',function()
 local function Named()
  local m=Play()
  m.progress.wishlistName='Synthetic Play plan whose name is long enough to need more than one line'
  return m
 end
 local line=NexusPanel._contextWishlist
 local function Fit() return line:GetHeight(),math.max(20,math.ceil(line:GetStringHeight())) end
 local function Header() return NexusPanel._responsiveLayout.boxes.header.h end
 SetNative(10)
 C.setup(Render(Named())==true,'N9: fixture: a long Wishlist name at native 10')
 local h10,need10=Fit()
 local box10=Header()
 C.setup(need10>20 and Near(h10,need10),'N9: fixture: the name wraps at native 10 and its line is as tall as its text',
  tostring(h10)..' for '..tostring(need10))
 SetNative(12.5)
 C.setup(P.Render(Named())==true and math.max(20,NexusPanel._responsiveLayout.normal)==20,
  'N9: fixture: the same model at native 12.5, where the header row minimum is still 20',NexusPanel._responsiveLayout.normal)
 local h12,need12=Fit()
 local box12=Header()
 print('OBSERVED','N9 native 10 -> 12.5','line '..tostring(h10)..' -> '..tostring(h12),
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
end)

-- N10. EXPECT (fails before the correction): the title became the 15-unit
-- role in the same one-line slot (150 units at 420), and its state cue is
-- the end of that line, so a cue that fitted at the former primary size was
-- cut by the client. A title whose line is wider than its slot at the title
-- role is drawn at the primary role instead (the size it had before), never
-- smaller. GUARD: the plain title, and a cue title that fits, keep the
-- 15-unit role. Widths are this fixture's stated model (0.55 em).
C.scenario('N10 a title with a state cue is not cut by the larger title font',function()
 local title=NexusPanel._contextTitle
 local function Title(native,text,edit)
  SetNative(native)
  local m=Play()
  if edit then edit(m) end
  C.setup(Render(m)==true and G.Visible(title:GetText() or '')==text,
   'N10: fixture: native '..tostring(native)..' shows "'..text..'"',title:GetText())
  local size,cut=Size(title),LM.Shortened(title)
  print('OBSERVED','N10 native '..tostring(native),'"'..text..'"','font='..tostring(size),'slot='..tostring(title:GetWidth()),
   'line='..tostring(Natural(title)),'cut='..tostring(cut))
  return size,cut
 end
 local function Preview(m) m.progress.isCommunityPreview=true end
 local function PreviewEmpty(m) m.progress.isCommunityPreview=true;m.assignment={emptySlot=true} end
 local function Unconfirmed(m) m.progress.activeSlot=nil end

 local size,cut=Title(10,'Nexus')
 C.guard(Near(size,Role('title')) and not cut,'N10: the plain title keeps its 15-unit role',size)
 size,cut=Title(10,'Nexus [Preview]',Preview)
 C.guard(Near(size,Role('title')) and not cut,'N10: a cue title that fits its slot keeps the 15-unit role',size)
 size,cut=Title(10,'Nexus [Unconfirmed]',Unconfirmed)
 C.expect(not cut and Near(size,Role('normal')),
  'N10: native 10: the Unconfirmed cue is whole, at the primary size it fitted at before',tostring(size)..' cut='..tostring(cut))
 size,cut=Title(10,'Nexus [Preview; Empty]',PreviewEmpty)
 C.expect(not cut and Near(size,Role('normal')),
  'N10: native 10: the Preview and Empty cues are whole, at the primary size',tostring(size)..' cut='..tostring(cut))
 size,cut=Title(12.5,'Nexus [Preview]',Preview)
 C.expect(not cut and Near(size,Role('normal')),
  'N10: native 12.5: the Preview cue is whole, at the primary size',tostring(size)..' cut='..tostring(cut))
 -- Wider than the slot even at the primary size (as before the title role
 -- existed): it is at least not drawn larger than that, and never smaller.
 size=Title(12.5,'Nexus [Unconfirmed]',Unconfirmed)
 C.expect(Near(size,Role('normal')),'N10: native 12.5: a cue too wide for the slot is drawn at the primary size, not larger or smaller',size)
 size,cut=Title(12.5,'Nexus')
 C.guard(Near(size,Role('title')) and not cut,'N10: the plain title returns to its 15-unit role after a cue title',size)
 C.guard(NATIVE.nativeSets==0,'N10: no game font object is set',NATIVE.nativeSets)
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
 C.guard(slots,'N8: each row keeps its one icon slot and has no outline around it or the row (offer-row spacing, REG-ROW)')
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
