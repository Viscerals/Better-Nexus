-- Play panel after the Claude Design full UI ("Main panel (Play)"): the
-- current offer first, as three cards side by side with the marked card set
-- apart; a heading that says whose choice it is; the waiting state while
-- current Echo data is missing; and the Auto ON line. Categories
-- (view_regression_support): EXPECT is behaviour added by this change (it
-- fails before it by design: no Readout.OfferCard, no card widgets); GUARD
-- already held and must keep holding; SETUP is the fixture. Oracles: the real
-- Readout builders, the real HUD's card widgets and roll texts, their anchors
-- and sizes, and the game-action, send and Auto counters. Real TOC boot;
-- synthetic host services and models only. Native pixels, font coverage,
-- label fit at large font scales and tooltip drawing are NOT RUN.
-- Main-panel visual correction (P2): an offer row is a fixed grid (its
-- icon, its name over its quality, its tag in a status column at the right)
-- and the selected row is told by an accent outline around a dark fill. The
-- former P2 band assertion (three one-line rows of small + 2 row gaps) is
-- replaced by the grid's; the rows stay display only.
-- The approved compact panel (design draft "Nexus compact panel"): that grid
-- is replaced in turn by the compact row: the icon, the name, and at the
-- row's right end the quality, a dot and the status on the name's line while
-- they fit it, else on a line under it; a selected status stands after a
-- star, which takes the place of the code-owned mark before its words (the
-- mark and the words stay whole on the row's hover). With Auto OFF the
-- heading over the offers is "Your offers", with the destination in a cell
-- of its own at the row's right end; that Auto is OFF is the Auto control's
-- own word in the header. EXPECT, failing at eef1608f by design (P2, P4,
-- P7, P9); the grid's assertions and the fitted Auto OFF heading's are
-- replaced by these, each marked where it stood, not relaxed. The draft is
-- drawn in reference pixels, 420 of them across the panel that is 284 units
-- wide at the reference text size, so one of its pixels is 284 / 420 unit
-- here.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('play_offer_cards')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local R,P=Nexus.Readout,Nexus.Panel

local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local CARDS={
 {text='Cinder Lattice (Epic) wanted',highlight=true},
 {text='Hollow Bell (Rare)'},
 {text='[Guaranteed offer] Ashen Tithe (Uncommon)'},
}
local function Model(o)
 o=o or {}
 return {status='ready',level=40,auto=o.auto,paused=o.paused,cards=o.cards or {},recommendation=o.recommendation or '',
  progress={wishlistName='Synthetic Play plan',total=6,owned=1,missing={},shed={},toLock={},unknownTomes={}}}
end
local function Heading() return tostring(NexusPanel._rollStatus:GetText() or '') end
local function Body() return tostring(NexusPanel._rollRec:GetText() or '') end
-- What the player reads: the text without colour escapes (|cAARRGGBB, |r),
-- whose hex digits are not shown. Nothing else is removed.
local function Visible(s) return (tostring(s or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
-- A length the approved draft gives in reference pixels, in whole units at
-- the reference text size (1 at least); and whether `units` is such a length
-- where it stands (a block's own place decides whether it rounds down or up).
local UNIT=284/420
local function Design(px) return math.max(1,math.floor(px*UNIT+0.5)) end
local function Drawn(px,units) return units==math.floor(px*UNIT) or units==math.ceil(px*UNIT) end
-- A selected row's tag as the compact row shows it: Readout's tag is the
-- code-owned mark "> " and its words; the row shows the star and the words.
-- The whole tag stays on the row for its hover.
local function Starred(card,tag)
 return type(tag)=='string' and tag:sub(1,2)=='> ' and #tag>2 and card.tag:GetText()==tag:sub(3)
  and card.star~=nil and card.star:IsShown() and card._nexusTag==tag
end
-- The compact offer heading with Auto OFF: "Your offers", the destination in
-- the cell at the row's right end (`slot` words, after a dot while charges
-- stand before it) and the Auto state on the header's Auto control.
local function ChoiceHeading(destination)
 local head,cell,auto=NexusPanel._rollStatus,NexusPanel._offerSlot,NexusPanel._autoBtn
 return Visible(head:GetText())==(Nexus.Localization.Text('panel.heading.your_offers'))
  and cell~=nil and cell:IsShown() and Visible(cell:GetText())==destination
  and auto~=nil and auto:IsShown() and Visible(auto:GetText())==(Nexus.Localization.Text('panel.button.auto_off'))
end

C.scenario('P1 Readout reads a card from its CardLine only; unknown is never blank',function()
 C.expect(R and type(R.OfferCard)=='function' and type(R.OfferHeading)=='function'
  and type(R.WaitingForOffer)=='function','P1: Readout offers the Play offer builders')
 if not (R and type(R.OfferCard)=='function') then return end
 local a=R.OfferCard('Cinder Lattice (Epic) wanted',true,false)
 C.expect(a.name=='Cinder Lattice' and a.quality=='Epic' and a.tag==R.OFFER_PICK_TAG and a.marked,
  'P1: the marked card with Auto OFF is the Wishlist pick',a.name..'|'..a.quality..'|'..a.tag)
 local b=R.OfferCard('Cinder Lattice (Epic) wanted',true,true)
 C.expect(b.tag==R.OFFER_RECOMMENDED_TAG,'P1: with Auto ON the marked card is only recommended, never "Auto will pick"',b.tag)
 local c=R.OfferCard('Hollow Bell (Rare) wanted',false,false)
 C.expect(c.name=='Hollow Bell' and c.quality=='Rare' and c.tag=='wanted' and not c.marked,
  'P1: an unmarked card keeps its own annotation',c.tag)
 -- The guarantee is said once, on the line that has room for it.
 local g=R.OfferCard('[Guaranteed offer] Ashen Tithe (Uncommon)',false,false)
 C.expect(g.name=='Ashen Tithe' and g.quality=='Uncommon' and g.guaranteed and g.tag==''
  and g.shown==R.OFFER_GUARANTEED_TAG,'P1: an unmarked guaranteed offer says so on its tag line',g.quality..'|'..tostring(g.shown))
 local gm=R.OfferCard('[Guaranteed offer] Ashen Tithe (Uncommon) wanted',true,false)
 C.expect(gm.quality=='Uncommon - guaranteed' and gm.tag==R.OFFER_PICK_TAG and gm.shown==R.OFFER_PICK_TAG,
  'P1: a marked guaranteed offer says so beside its quality; its tag line is the pick',gm.quality)
 C.expect(type(R.OfferHeadingForms)=='function' and R.OfferHeadingForms(false)[1]==R.OfferHeading(false)
  and R.OfferHeadingForms(false)[3]=='You choose' and R.OfferHeadingForms(true)[3]=='Auto ON',
  'P1: the shorter heading forms still say whose choice the offer is')
 local u=R.OfferCard('Mystery offer',false,false)
 C.expect(u.name=='Mystery offer' and u.quality=='? Quality unknown',
  'P1: a line without a known quality keeps its text and says the quality is unknown',u.quality)
 C.expect(R.OfferHeading(false)=='Current offer - you choose' and R.OfferHeading(true)=='Current offer - Auto ON'
  and R.OfferHeading(nil)=='Current offer','P1: the heading says whose choice the offer is')
 local ascii=true
 for _,s in ipairs({R.OFFER_PICK_TAG,R.OFFER_RECOMMENDED_TAG,R.WAITING_OFFER_HEADING,R.WAITING_OFFER_NOTE,R.AUTO_ON_NOTE}) do
  if type(s)~='string' or s:find('[^\32-\126]') or s:find('|',1,true) then ascii=false end
 end
 C.expect(ascii,'P1: the new Readout words are printable ASCII without pipes (the shared glyph rule)')
 C.expect(R.WaitingForOffer('unsynced') and not R.WaitingForOffer('manual mode') and not R.WaitingForOffer(nil),
  'P1: only the unsynced hold is the waiting state')
 C.expect(R.AutoHoldNote('unsynced')==R.WAITING_OFFER_NOTE,'P1: the waiting hold reads as the design waiting line')
 C.guard(R.AutoHoldNote('manual mode'):find('^Paused: ')~=nil,'P1: other holds keep their paused wording')
end)

-- P1b adversarial names: an Echo name that itself holds a quality word in
-- brackets. CardLine writes the quality right after the whole name, so the
-- card and the recommendation target read the TRAILING token, never the
-- first: the name is never cut and the quality is the card's own. The lines
-- come from the real CardLine; the decision (highlight) is not touched.
C.scenario('P1b a name holding " (Rare)" or similar is not cut; the quality is the card\'s own',function()
 local cases={
  {card={name='Shard (Rare)',quality=3},annotation='wanted',name='Shard (Rare)',quality='Epic',tag='wanted'},
  {card={name='Blade (Epic) of Dawn',quality=1},annotation=nil,name='Blade (Epic) of Dawn',quality='Uncommon',tag=''},
  {card={name='(Common) Relic (Legendary)',quality=4,isGuaranteed=true},annotation='wanted',
   name='(Common) Relic (Legendary)',quality='Legendary',tag='wanted',guaranteed=true},
  {card={name='Echo (Rare) (Rare)',quality=2},annotation='wanted',name='Echo (Rare) (Rare)',quality='Rare',tag='wanted'},
 }
 for i,case in ipairs(cases) do
  local line=R.CardLine(case.card,case.annotation,nil)
  local unmarked=R.OfferCard(line,false,false)
  local marked=R.OfferCard(line,true,false)
  local wantTag=case.annotation and (Nexus.UserText and Nexus.UserText.Annotation(case.annotation) or case.annotation) or ''
  C.expect(unmarked.name==case.name and unmarked.quality==case.quality and unmarked.tag==wantTag and unmarked.full==line
   and (unmarked.guaranteed==(case.guaranteed==true)),
   'P1b '..i..': the whole name and the card\'s own quality are read from "'..line..'"',
   tostring(unmarked.name)..'|'..tostring(unmarked.quality)..'|'..tostring(unmarked.tag))
  C.expect(marked.name==case.name and marked.tag==R.OFFER_PICK_TAG
   and marked.quality==case.quality..(case.guaranteed and ' - guaranteed' or ''),
   'P1b '..i..': the marked card keeps the same name and quality',tostring(marked.name)..'|'..tostring(marked.quality))
  local target=R.CardTarget(line)
  C.expect(target==case.name..' ('..case.quality..')',
   'P1b '..i..': the recommendation target names the whole Echo and its own quality',tostring(target))
  C.expect(R.RecommendationWithTarget('Take a needed Echo',line)=='Take a needed Echo: '..case.name..' ('..case.quality..')',
   'P1b '..i..': the named recommendation is not truncated',R.RecommendationWithTarget('Take a needed Echo',line))
 end
 -- From the text alone an unknown quality whose name ends in a quality token
 -- is indistinguishable (the stated limit); the HUD passes the card's own
 -- facts instead (P1c, P9).
 local unknown=R.OfferCard(R.CardLine({name='Mystery'},nil,nil),false,false)
 C.guard(unknown.name=='Mystery' and unknown.quality=='? Quality unknown','P1b: a line without a quality still says so')
end)

-- P1c adversarial unknown quality: a card whose quality is unknown and whose
-- name ends in a quality-like token. CardLine prints no quality for it, so
-- its line reads exactly like a Rare "Shard". With the card's own facts
-- (Readout.CardFacts, which the HUD model carries) the whole name stays the
-- name and the quality stays unknown; nothing is inferred from the text. The
-- one-line text is unchanged and stays the hover text. Known-quality controls
-- keep their own quality.
C.scenario('P1c an unknown quality is never read from a name ending in " (Rare)"',function()
 if not C.setup(type(R.CardFacts)=='function','P1c: fixture: Readout offers CardFacts') then return end
 local wanted=Nexus.UserText and Nexus.UserText.Annotation('wanted') or 'wanted'
 local cases={
  {card={name='Shard (Rare)'},annotation='wanted',name='Shard (Rare)',quality='? Quality unknown',tag=wanted},
  {card={name='Shard (Rare)',quality=9},annotation=nil,name='Shard (Rare)',quality='? Quality unknown',tag=''},
  {card={name='Relic (Epic) (Legendary)',isGuaranteed=true},annotation='wanted',name='Relic (Epic) (Legendary)',
   quality='? Quality unknown',tag=wanted,guaranteed=true},
  {card={name='Shard (Rare)',quality=3},annotation='wanted',name='Shard (Rare)',quality='Epic',tag=wanted,known=true},
  {card={name='Shard',quality=2},annotation='wanted',name='Shard',quality='Rare',tag=wanted,known=true},
 }
 for i,case in ipairs(cases) do
  local line=R.CardLine(case.card,case.annotation,nil)
  local facts=R.CardFacts(case.card)
  if case.known then
   C.setup(facts.quality==case.card.quality and line:find(case.name..' ('..case.quality..')',1,true)~=nil,
    'P1c '..i..': fixture: CardLine prints the known quality after the whole name',line)
  else
   C.setup(facts.quality==nil and facts.name==case.card.name and line:find(case.name,1,true)~=nil,
    'P1c '..i..': fixture: CardLine prints the whole name and no quality; the facts hold none',line)
  end
  local unmarked=R.OfferCard(line,false,false,facts)
  local marked=R.OfferCard(line,true,false,facts)
  C.expect(unmarked.name==case.name and unmarked.quality==case.quality and unmarked.tag==case.tag and unmarked.full==line
   and unmarked.guaranteed==(case.guaranteed==true),
   'P1c '..i..': with its own facts the card keeps the whole name and its own quality: "'..line..'"',
   tostring(unmarked.name)..'|'..tostring(unmarked.quality)..'|'..tostring(unmarked.tag))
  C.expect(marked.name==case.name and marked.tag==R.OFFER_PICK_TAG
   and marked.quality==(case.known and case.quality or '? Quality unknown'),
   'P1c '..i..': marked, the same name and quality',tostring(marked.name)..'|'..tostring(marked.quality))
  local target=R.CardTarget(line,facts)
  C.expect(target==(case.known and (case.name..' ('..case.quality..')') or nil),
   'P1c '..i..': the recommendation target is named only for a known quality',tostring(target))
  C.expect(R.RecommendationWithTarget('Take a needed Echo',line,facts)
   ==(case.known and ('Take a needed Echo: '..case.name..' ('..case.quality..')') or 'Take a needed Echo'),
   'P1c '..i..': no quality is added to the named recommendation from the text',R.RecommendationWithTarget('Take a needed Echo',line,facts))
 end
 -- The text-only reading is unchanged for callers without facts (P1, P1b).
 C.guard(R.OfferCard('Hollow Bell (Rare) wanted',false,false).quality=='Rare','P1c: a text-only line keeps its text reading')
end)

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()

C.scenario('P2 three compact offer rows, the Wishlist pick set apart, and nothing chosen',function()
 local before=Effects()
 C.setup(P.Render(Model({auto=false,cards=CARDS}))==true and NexusPanel:IsShown(),'P2: fixture: the HUD renders an offer with Auto OFF')
 local cards=NexusPanel._offerCards
 C.expect(type(cards)=='table' and #cards==3,'P2: the HUD has three offer cards')
 if type(cards)~='table' then return end
 local shown=0
 for i=1,3 do if cards[i]:IsShown() then shown=shown+1 end end
 C.expect(shown==3,'P2: every offered card is shown',tostring(shown))
 -- (The pick's words after its star: Starred. The check that stood here
 -- asked for the tag with its code-owned mark as the row's text.)
 C.expect(cards[1].name:GetText()=='Cinder Lattice' and cards[1].quality:GetText()=='Epic'
  and Starred(cards[1],R.OFFER_PICK_TAG) and cards[1]._nexusMarked==true,
  'P2: the marked card names its Echo, its quality and the Wishlist pick',tostring(cards[1].tag:GetText()))
 C.expect(cards[2].star~=nil and not cards[2].star:IsShown() and cards[3].star~=nil and not cards[3].star:IsShown(),
  'P2: only the selected row has the star')
 C.expect(cards[2]._nexusMarked==false and cards[3]._nexusMarked==false,'P2: only the runtime-marked card is set apart')
 C.expect(cards[3].quality:GetText()=='Uncommon' and cards[3].tag:GetText()==R.OFFER_GUARANTEED_TAG,
  'P2: the guaranteed card says so on its tag line')
 -- design/current "Nexus Main Panel - Compact Redesign": compact offer rows.
 C.expect(cards[1]._nexusLayout=='rows','P2: the offers are compact rows, one per offer',tostring(cards[1]._nexusLayout))
 C.expect(cards[1]._nexusFull=='Cinder Lattice (Epic) wanted','P2: the complete card line stays on its hover')
 -- (EXPECT: the heading was "Current offer - you choose" with the Auto
 -- state and the destination after it in one text. This model has no
 -- Saved Build slot, so the destination is the preview tag.)
 C.expect(ChoiceHeading((Nexus.Localization.Text('panel.label.preview_tag'))),
  'P2: the heading is "Your offers", the destination stands in its own cell and the Auto control says Auto OFF',Heading())
 -- Geometry: disjoint full-width rows inside the roll area.
 local area=NexusPanel._rollArea
 local layout=NexusPanel._responsiveLayout
 -- The approved compact rows. A row's text column is the row less its
 -- 6-pixel insets, the 24-pixel icon and the 8 pixels after it; at the
 -- row's right end stands the phrase: the quality, a dot (5 pixels either
 -- side) and the status, a selected status after its 12-pixel star and 4.
 -- The name and the phrase share the row's line while the name, the draft's
 -- 10 pixels and the phrase fit the column: the draft's 28-pixel row.
 -- Otherwise the phrase stands on a line of its own under the name: 24
 -- pixels more. Rows are 2 pixels apart. Which arrangement a row needs is
 -- worked out here from its words as this harness measures them (6 units a
 -- byte); nothing is read from the panel's own arrangement. The checks that
 -- stood here held the grid: three rows of one height, at least the
 -- two-line model row, with the name at 37 units over its quality and the
 -- tag in a status column; that grid is intentionally gone, so its literals
 -- are replaced by the compact row's, not relaxed.
 C.setup(layout~=nil and layout.small==11 and layout.normal==14 and layout.gap==6 and layout.width==284
  and area:GetWidth()==284-2*Design(7),
  'P2: fixture: the reference text size (11 and 14-unit rows) in the 284-unit reference panel',
  layout and (tostring(layout.small)..' / '..tostring(layout.normal)..' / '..tostring(layout.width)))
 local row={inset=Design(6),icon=Design(24),pad=Design(2),textX=Design(6)+Design(24)+Design(8)}
 C.setup(row.inset==4 and row.icon==16 and row.pad==1 and row.textX==25 and Design(10)==7 and Design(5)==3,
  'P2: fixture: the draft\'s row lengths at the reference size: insets 4, icon 16, pad 1, the name from 25')
 local function Arrangement(card)
  local column=card:GetWidth()-row.textX-row.inset
  local quality,tag=card.quality:GetText() or '',card.tag:GetText() or ''
  local qualityW=quality~='' and card.quality:GetStringWidth() or 0
  local tagW=tag~='' and card.tag:GetStringWidth() or 0
  -- (The dot is two bytes in this harness's measure.)
  local dotW=(qualityW>0 and tagW>0) and (2*Design(5)+6*#'\194\183') or 0
  local starW=(tagW>0 and card._nexusMarked==true) and (Design(12)+Design(4)) or 0
  local phrase=qualityW+dotW+starW+tagW
  return {column=column,qualityW=qualityW,tagW=tagW,dotW=dotW,starW=starW,phrase=phrase,
   inline=phrase==0 or card.name:GetStringWidth()+Design(10)+phrase<=column}
 end
 local lastBottom,inside,first=nil,true,nil
 local tops,plans={},{}
 for i=1,3 do
  local point,relative,_,x,y=cards[i]:GetPoint()
  first=first or -y
  tops[i],plans[i]=-y,Arrangement(cards[i])
  if point~='TOPLEFT' or relative~=area or x<0 or x+cards[i]:GetWidth()>area:GetWidth() or y>0
   or (lastBottom and -y<lastBottom) then inside=false end
  lastBottom=-y+cards[i]:GetHeight()
 end
 C.expect(inside and lastBottom~=nil and lastBottom<=area:GetHeight(),'P2: the offers are three disjoint rows inside the roll area')
 local h1,h2,h3=cards[1]:GetHeight(),cards[2]:GetHeight(),cards[3]:GetHeight()
 -- This board: rows 1 and 2 fit one line; row 3's guarantee does not fit
 -- beside its name (66 + 7 + 174 units in a column of 245).
 C.setup(plans[1].inline and plans[2].inline and not plans[3].inline and plans[3].phrase<=plans[3].column,
  'P2: fixture: rows 1 and 2 fit one line and row 3\'s phrase stands under its name',
  tostring(plans[1].phrase)..' / '..tostring(plans[2].phrase)..' / '..tostring(plans[3].phrase)..' in '..tostring(plans[3].column))
 C.expect(cards[1]:GetWidth()==area:GetWidth() and Drawn(28,h1) and Drawn(28,h2) and Drawn(52,h3)
  and Drawn(2,tops[2]-(tops[1]+h1)) and Drawn(2,tops[3]-(tops[2]+h2)),
  'P2: a one-line row is the draft\'s 28 pixels and a row with its phrase under the name 24 more; the rows span the block, 2 pixels apart',
  h1..'/'..h2..'/'..h3..' at '..tops[1]..'/'..tops[2]..'/'..tops[3])
 -- Inside each row: every name starts at one left edge after the icon; the
 -- phrase ends at the row's right inset, the quality before the status on
 -- one line with the dot between them, on the name's line or under it.
 local columns,notes=true,{}
 for i=1,3 do
  local card,plan=cards[i],plans[i]
  local np,nrel,_,nx,ny=card.name:GetPoint()
  local qp,qrel,_,qx,qy=card.quality:GetPoint()
  local tp,trel,_,tx,ty=card.tag:GetPoint()
  local right=card:GetWidth()-row.inset
  local dotShown=card.dot~=nil and card.dot:IsShown() and true or false
  notes[#notes+1]=i..': name '..tostring(nx)..','..tostring(ny)..' quality '..tostring(qx)..','..tostring(qy)..' tag '..tostring(tp)..' '..tostring(tx)
  local ok=np=='TOPLEFT' and nrel==card and nx==row.textX and -ny==row.pad
   and qp=='TOPLEFT' and qrel==card and card.quality:GetWidth()==plan.qualityW
  if ok and plan.tagW>0 then
   ok=tp=='TOPLEFT' and trel==card and card.tag:GetWidth()==plan.tagW and tx+plan.tagW==right and ty==qy
    and qx+plan.qualityW+plan.dotW+plan.starW==tx and dotShown
  elseif ok then
   ok=qx+plan.qualityW==right and not dotShown
  end
  if ok and plan.inline then
   -- On the name's line, after the name's box and the draft's 10 pixels.
   ok=qy==ny and card.name:GetWidth()>=card.name:GetStringWidth() and nx+card.name:GetWidth()+Design(10)<=qx
  elseif ok then
   -- Under the name, which has the whole text column.
   ok=card.name:GetWidth()==plan.column and -qy>=-ny+card.name:GetHeight()
  end
  if not ok then columns=false end
 end
 C.expect(columns,
  'P2: each row is the compact row: the name at 25 units, and ending 4 units from the row\'s right the quality, the dot and the status, on the name\'s line while they fit it, else under it',
  table.concat(notes,' | '))
 -- The icon: one square per row at the same inset, in the middle of the
 -- row's first line (the draft's 24-pixel line, 2 pixels under the row's
 -- top), before the text.
 local icons=true
 for i=1,3 do
  local icon=cards[i]._nexusSlot and cards[i]._nexusSlot.icon
  local ip,irel,_,ix,iy=nil,nil,nil,nil,nil
  if icon then ip,irel,_,ix,iy=icon:GetPoint() end
  if not (icon and ip=='TOPLEFT' and irel==cards[i] and ix==row.inset and -iy==row.pad
   and icon:GetWidth()==row.icon and icon:GetHeight()==row.icon and ix+icon:GetWidth()<row.textX) then icons=false end
 end
 C.expect(icons,'P2: every row keeps its 16-unit icon square (the draft\'s 24 pixels) at 4, 1 in the row, before its text')
 -- The selected row (the marked offer): a dark fill and an outline on the
 -- row's own four edges; no other row shows either.
 local function Selected(card)
  local edges=type(card.outline)=='table' and #card.outline or 0
  local shown=0
  for _,edge in ipairs(card.outline or {}) do if edge:IsShown() then shown=shown+1 end end
  return edges,shown,card.fill~=nil and card.fill:IsShown()
 end
 local e1,s1,f1=Selected(cards[1])
 local _,s2,f2=Selected(cards[2])
 local _,s3,f3=Selected(cards[3])
 C.expect(e1==4 and s1==4 and f1 and s2==0 and not f2 and s3==0 and not f3 and cards[1]._nexusMarked==true,
  'P2: only the selected row shows its four-edge outline and its dark fill',
  e1..' edges, shown '..s1..'/'..s2..'/'..s3..' fill '..tostring(f1)..'/'..tostring(f2)..'/'..tostring(f3))
 local clickable=false
 for i=1,3 do
  if cards[i]:GetScript('OnClick') or cards[i]:GetScript('OnMouseUp') or cards[i]:GetScript('OnMouseDown') then clickable=true end
 end
 C.guard(not clickable,'P2: a card has no click: it never chooses, banishes, rerolls or freezes')
 -- The star and the dot are marks only (the draft's decision D7: a mark,
 -- no gameplay action): plain regions on a layer of the offer block that
 -- has no script of its own, so they add no hover, click or drag. EXPECT
 -- (at eef1608f a row had neither). Whether the layer takes the mouse is
 -- the client's to show (the harness keeps no mouse state): NOT RUN.
 local star,dot=cards[1].star,cards[1].dot
 local layer=star and star:GetParent()
 local scripted=false
 for _,name in ipairs({'OnClick','OnMouseUp','OnMouseDown','OnEnter','OnLeave','OnDragStart','OnDragStop','OnUpdate'}) do
  if layer and layer:GetScript(name) then scripted=true end
 end
 C.expect(star~=nil and star.kind=='Texture' and dot~=nil and dot.kind=='FontString' and layer~=nil and layer.kind=='Frame'
  and layer:GetParent()==area and dot:GetParent()==layer and not scripted,
  'P2: the star and the dot are plain marks on a layer of the offer block that has no script: no hover, click or drag of their own',
  tostring(layer and layer.kind))
 for i=1,3 do local enter=cards[i]:GetScript('OnEnter');if enter then enter(cards[i]) end end
 C.guard(Effects()==before,'P2: rendering and pointing at the cards make no game action, send or Auto change',Effects())
end)

C.scenario('P3 a new board leaves no old card; no cards hides them',function()
 P.Render(Model({auto=false,cards={{text='Frostwake Sigil (Rare)'}}}))
 local cards=NexusPanel._offerCards
 if not C.setup(type(cards)=='table','P3: fixture: the cards exist') then return end
 C.expect(cards[1]:IsShown() and cards[1].name:GetText()=='Frostwake Sigil' and not cards[2]:IsShown() and not cards[3]:IsShown(),
  'P3: only the offered card shows; earlier cards are gone')
 C.expect(cards[1].tag:GetText()=='' and not cards[1]._nexusMarked,'P3: an unmarked board marks nothing')
 P.Render(Model({auto=false}))
 C.expect(not cards[1]:IsShown(),'P3: without an offer no card shows')
end)

C.scenario('P4 Auto ON: the offer is recommended only, with what Auto may do',function()
 local before=Effects()
 C.setup(P.Render(Model({auto=true,cards=CARDS}))==true,'P4: fixture: a synthetic Auto ON model with an offer')
 local cards=NexusPanel._offerCards
 C.expect(cards and Starred(cards[1],R.OFFER_RECOMMENDED_TAG),'P4: the marked card is recommended, not promised',
  cards and cards[1].tag:GetText())
 -- Approved panel cleanup (Auto ON takes no row of its own): the Auto
 -- explanation control shares the heading's row, so the heading is fitted
 -- beside it and may show one of its shorter forms (Readout
 -- .OfferHeadingForms); every form still says Auto is ON.
 local says=false
 for _,form in ipairs(R.OfferHeadingForms(true)) do if Heading():find(form,1,true) then says=true end end
 C.expect(says and Heading():find('Auto ON',1,true)~=nil,'P4: the heading says Auto is ON',Heading())
 -- Approved panel cleanup ("Compact Auto ON. Put long explanation behind
 -- optional disclosure"): the Auto ON line is no longer always on the panel.
 -- It starts closed behind its own control (NexusPanel._autoInfoBtn); once
 -- the player opens it, it is the panel's own row below the offer, in full,
 -- not a hover and not part of the body, and it stays open across renders
 -- (P6-P8) until the player closes it.
 local toggle=NexusPanel._autoInfoBtn
 local scope=NexusPanel._autoScopeText
 C.expect(toggle~=nil and toggle:IsShown() and not (scope and scope:IsShown()),
  'P4: the Auto ON line starts closed behind its control',toggle and toggle:GetText())
 if toggle then toggle:Click() end
 C.setup(P.Render(Model({auto=true,cards=CARDS}))==true,'P4: fixture: the same model rendered again after the control was clicked')
 scope=NexusPanel._autoScopeText
 local boxes=NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.boxes or {}
 C.expect(scope~=nil and scope:IsShown() and Visible(scope:GetText())==R.AUTO_ON_NOTE,
  'P4: once opened, the Auto ON line is shown in full on the panel',scope and scope:GetText())
 C.expect(boxes.autoScope and boxes.roll and boxes.autoScope.y>=boxes.roll.y+boxes.roll.h,
  'P4: the Auto ON line follows the offer, in its own rows below it')
 C.expect(not Body():find(R.AUTO_ON_NOTE,1,true),'P4: the line is not repeated in the recommendation body',Body())
 C.guard(Effects()==before,'P4: rendering an Auto ON model turns nothing on and sends nothing',Effects())
end)

C.scenario('P5 waiting for current Echo data: named as a wait, never zero offers',function()
 C.setup(P.Render(Model({auto=true,paused='unsynced'}))==true,'P5: fixture: Auto held for missing Echo data, no offer')
 C.expect(Heading()==('|cffffd100'..R.WAITING_OFFER_HEADING..'|r'),'P5: the heading is the waiting state',Heading())
 C.expect(Body():find(R.WAITING_OFFER_NOTE,1,true)~=nil,'P5: the body says nothing is chosen meanwhile',Body())
 -- The heading's colour escape |cffffd100 holds a "0" the player never sees;
 -- the visible heading and body must hold no zero count.
 C.expect(not Visible(Body()):find('0 offers',1,true) and not Visible(Heading()):find('0',1,true),
  'P5: no "0 offers" stands in for the wait',Visible(Heading())..' | '..Visible(Body()))
 local cards=NexusPanel._offerCards
 C.guard(not (cards and cards[1]:IsShown()),'P5: no card is shown while waiting')
 P.Render(Model({auto=true,paused='manual mode'}))
 C.guard(Heading():find('paused',1,true)~=nil,'P5: another hold keeps the paused heading',Heading())
end)

-- The opened Auto ON note (P4: opened by its control, and still open here)
-- must not retreat into the Auto hover when a recommendation is present.
-- Fit is the offline conservative text model only (native NOT RUN).
C.scenario('P6 Auto ON beside a recommendation: the scope line stays visible; the body stays the recommendation',function()
 local before=Effects()
 C.setup(P.Render(Model({auto=true,cards=CARDS,recommendation='Take a needed Echo'}))==true,
  'P6: fixture: a synthetic Auto ON model with an offer and a recommendation')
 local scope=NexusPanel._autoScopeText
 C.expect(scope~=nil and scope:IsShown() and Visible(scope:GetText())==R.AUTO_ON_NOTE,
  'P6: beside a recommendation the Auto ON line is still shown in full',scope and scope:GetText())
 C.expect(Visible(Body())=='Take a needed Echo','P6: the body stays exactly the recommendation',Body())
 local layout=NexusPanel._responsiveLayout
 local box=layout and layout.boxes.autoScope
 local _,line=Nexus.LayoutMetrics.ConservativeText(layout and layout.scale or 1)
 local rows=box and Nexus.LayoutMetrics.TextRows(R.AUTO_ON_NOTE,box.w,layout.scale) or 0
 C.expect(box~=nil and rows>0 and box.h>=rows*line and scope:GetHeight()==box.h and scope:GetWidth()==box.w,
  'P6: its rows hold the whole line in the conservative text model, inside the panel',
  box and (box.w..'x'..box.h..' rows='..rows) or 'no box')
 local cut=false
 for _,other in ipairs({'roll','progressHeader','planBar'}) do
  if box and layout.boxes[other] and Nexus.LayoutMetrics.Overlap(box,layout.boxes[other]) then cut=true end
 end
 C.expect(not cut,'P6: the line overlaps neither the offer nor the plan progress')
 C.setup(P.Render(Model({auto=false,cards=CARDS,recommendation='Take a needed Echo'}))==true,'P6: fixture: the same offer with Auto OFF')
 C.expect(not (scope and scope:IsShown()),'P6: with Auto OFF there is no Auto ON line')
 C.guard(Effects()==before,'P6: rendering either model turns nothing on, takes nothing and sends nothing',Effects())
end)

-- P7/P8 (review fit and fallback findings). P7 measures with the 125% text
-- model of layout_geometry_support (8.75 px per visible character, NexusFont
-- size 15, so LayoutMetrics' runtime font scale is 1.25): every heading and
-- card status line must be no wider than its own box. A model, not native
-- font measurement; native fit at 125% stays NOT RUN.
local G=dofile('tests/prototype/layout_geometry_support.lua')
local LARGE={name='125%',char=8.75,line=15,size=15}
local function Fits(text) return text:GetStringWidth()<=text:GetWidth() end
local function Rect(region) local ok,r=pcall(G.Rect,region,NexusPanel);return ok and r or nil end

-- Count disclosure (play_panel_summary S32): the compact banish, reroll and
-- freeze charges are counts and are on the panel only while Details is open.
-- P7 asks that the heading fits its row BESIDE the charges; with Details
-- closed there are no charges beside it any more (the heading has the whole
-- row), so P7 renders with Details open, where the charges cell stands, and
-- puts Details back. Its checks are unchanged.
C.scenario('P7 at 125% text the offer heading and every card status line fit without moving meaning to a hover',function()
 local before=Effects()
 local wasDetails=P._playDetails
 P._playDetails=true
 G.UseFont(LARGE)
 local function Large(auto,cards)
  local m=Model({auto=auto,cards=cards})
  m.progress.activeSlot=2
  m.charges={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true}
  P.Render(Model({auto=auto})) -- another layout first, so this one is applied in full
  return P.Render(m)
 end
 for _,case in ipairs({{false,'you choose','Auto OFF'},{true,'Auto ON','Active:'}}) do
  local tag='P7 Auto '..(case[1] and 'ON' or 'OFF')
  C.setup(Large(case[1],CARDS)==true,tag..': fixture: an offer with charges and Saved Build 2 at 125% text')
  local head=NexusPanel._rollStatus
  local shown=Visible(head:GetText())
  C.expect(Fits(head),tag..': the heading fits its row beside the charges on one line',
   shown..' '..head:GetStringWidth()..'/'..head:GetWidth())
  if case[1] then
   -- The shorter heading forms begin with whose choice it is ('You
   -- choose', P1), so that phrase is matched without case; the Auto state
   -- and the destination are matched exactly.
   C.expect(shown:lower():find(case[2]:lower(),1,true)~=nil and shown:find(case[3],1,true)~=nil and shown:find('Slot 2',1,true)~=nil,
    tag..': it still says whose choice it is, the Auto state and the destination',shown)
  else
   -- The approved compact heading with Auto OFF: "Your offers"; the
   -- destination is on the panel in the cell at the row's right end, after
   -- the charges and a dot, whole on its line; and the Auto state is the
   -- Auto control's own word in the header. Nothing of it moved to a
   -- hover. (EXPECT: one fitted text said all three here.)
   local cell=NexusPanel._offerSlot
   C.expect(ChoiceHeading('\194\183 '..(Nexus.Localization.Format('panel.label.slot_number',{slot='2'})))
    and Fits(cell),
    tag..': the heading is "Your offers"; the destination, in its own cell after the charges, and the Auto state, on the Auto control, are still on the panel, whole',
    shown..' | '..tostring(cell and cell:GetText())..' | '..tostring(NexusPanel._autoBtn:GetText()))
  end
  local cards=NexusPanel._offerCards or {}
  local area,rects,clipped=Rect(NexusPanel._rollArea),{},{}
  for i=1,3 do
   if cards[i] and cards[i]:IsShown() then
    rects[#rects+1]=Rect(cards[i])
    for _,key in ipairs({'quality','tag'}) do
     local text=cards[i][key]
     if (text:GetText() or '')~='' and not Fits(text) then clipped[#clipped+1]=i..'.'..key..'='..Visible(text:GetText()) end
    end
   end
  end
  C.expect(#rects==3 and #clipped==0,tag..': every card quality and tag line is whole on the panel',table.concat(clipped,', '))
  C.expect(Visible(cards[3].tag:GetText())==R.OFFER_GUARANTEED_TAG and cards[3]._nexusLayout=='rows',
   tag..': the guaranteed card says so in full, the cards stacked as rows of the same band',tostring(cards[3]._nexusLayout))
  local inside,apart=true,true
  for i=1,#rects do
   if not (area and rects[i] and G.Inside(rects[i],area)) then inside=false end
   for j=i+1,#rects do if not G.Apart(rects[i],rects[j]) then apart=false end end
  end
  C.expect(inside and apart,tag..': the stacked cards stay inside the roll area and apart')
 end
 -- A marked guaranteed card: the guarantee beside its quality, the pick tag.
 local marked={{text='[Guaranteed offer] Cinder Lattice (Epic) wanted',highlight=true},CARDS[2],{text='Ashen Tithe (Uncommon)'}}
 C.setup(Large(false,marked)==true,'P7: fixture: a marked guaranteed offer at 125% text')
 local c1=(NexusPanel._offerCards or {})[1]
 C.expect(c1 and Visible(c1.quality:GetText())=='Epic - guaranteed' and Fits(c1.quality)
  and Starred(c1,R.OFFER_PICK_TAG) and Fits(c1.tag),
  'P7: a marked guaranteed card shows its guarantee and the pick, both whole',c1 and Visible(c1.quality:GetText()))
 P._playDetails=wasDetails
 G.UseFont(G.MODELS.default)
 P.Render(Model({auto=false}))
 C.setup(P.Render(Model({auto=false,cards=CARDS}))==true,'P7: fixture: the stock model again')
 -- (The offers stay compact rows: the GUARD it was. The heading it asked
 -- for beside that, the full fitted form returning with room, is the
 -- compact heading's one form now: an EXPECT.)
 C.guard(NexusPanel._offerCards[1]._nexusLayout=='rows','P7: back at the stock text the offers stay compact rows')
 C.expect(ChoiceHeading((Nexus.Localization.Text('panel.label.preview_tag'))),
  'P7: back at the stock text the heading is the same "Your offers"',Heading())
 C.guard(Effects()==before,'P7: fitting and stacking change no game state',Effects())
end)

C.scenario('P8 Auto ON when the responsive layout cannot be built: the permission line stays visible in the body',function()
 local before=Effects()
 local metrics=Nexus.LayoutMetrics
 local real=metrics.Panel
 local AUTO=Model({auto=true,cards=CARDS,recommendation='Take a needed Echo'})
 local function Failing(tag)
  metrics.Panel=function() error('synthetic layout failure') end
  local ok,result=pcall(P.Render,H.Clone(AUTO))
  metrics.Panel=real
  C.setup(ok and result==true,tag..': fixture: the render committed while LayoutMetrics.Panel failed',tostring(result))
  return Visible(Body())
 end
 -- 1. No layout at hand at all.
 P.Render(Model({auto=false}))
 NexusPanel._responsiveLayout=nil
 local body=Failing('P8 none')
 C.expect(body:find('Take a needed Echo',1,true)==1 and body:find(R.AUTO_ON_NOTE,1,true)~=nil,
  'P8: with no layout the body keeps the recommendation and adds the Auto ON line',body)
 C.expect(not (NexusPanel._autoScopeText and NexusPanel._autoScopeText:IsShown()),'P8: no scope row is shown without a layout')
 -- 2. Only an earlier layout, which has no scope row (Auto OFF).
 C.setup(P.Render(Model({auto=false,cards=CARDS}))==true and NexusPanel._responsiveLayout
  and not NexusPanel._responsiveLayout.boxes.autoScope,'P8: fixture: an earlier layout without the scope row')
 body=Failing('P8 earlier')
 C.expect(body:find(R.AUTO_ON_NOTE,1,true)~=nil,'P8: with an earlier layout lacking the row the body still says what Auto may do',body)
 -- 3. Control: a built layout holds the row; the body stays the recommendation.
 P.Render(Model({auto=false,cards=CARDS}))
 C.setup(P.Render(H.Clone(AUTO))==true,'P8: fixture: the same model with the layout built')
 local scope=NexusPanel._autoScopeText
 C.guard(scope and scope:IsShown() and Visible(scope:GetText())==R.AUTO_ON_NOTE and Visible(Body())=='Take a needed Echo',
  'P8: with the layout the row shows the line and the body is not repeated',Body())
 C.guard(Effects()==before,'P8: the fallback turns nothing on, takes nothing and sends nothing',Effects())
end)

-- P9: P1c's adversarial card through the real HUD, its model card carrying
-- the facts the runtime puts beside the text (core/AutomationRuntime.lua
-- cardLines .facts = Readout.CardFacts). The marked card's named
-- recommendation gets no quality from the text either. A model card without
-- facts keeps the text reading.
C.scenario('P9 the HUD card of an unknown-quality "Shard (Rare)" keeps the whole name and says its quality is unknown',function()
 local before=Effects()
 local adversary,known={name='Shard (Rare)'},{name='Hollow Bell',quality=2}
 local line=R.CardLine(adversary,'wanted',nil)
 local cards={{text=line,highlight=true,facts=R.CardFacts(adversary)},
  {text=R.CardLine(known,nil,nil),facts=R.CardFacts(known)},{text='Ashen Tithe (Uncommon)'}}
 C.setup(P.Render(Model({auto=false,cards=cards,recommendation='Take a needed Echo'}))==true,
  'P9: fixture: an Auto OFF offer whose marked card has an unknown quality')
 local c=NexusPanel._offerCards
 if not C.setup(type(c)=='table' and c[1]:IsShown(),'P9: fixture: the offer cards show') then return end
 C.expect(c[1].name:GetText()=='Shard (Rare)' and c[1].quality:GetText()=='? Quality unknown'
  and Starred(c[1],R.OFFER_PICK_TAG) and c[1]._nexusFull==line and c[1]._nexusMarked==true,
  'P9: the card shows the whole name, an unknown quality and the pick; its hover keeps the one-line text',
  tostring(c[1].name:GetText())..'|'..tostring(c[1].quality:GetText()))
 C.expect(c[2].name:GetText()=='Hollow Bell' and c[2].quality:GetText()=='Rare','P9: a known quality is the card\'s own')
 C.expect(c[3].name:GetText()=='Ashen Tithe' and c[3].quality:GetText()=='Uncommon','P9: a model card without facts keeps the text reading')
 local body=Visible(Body())
 C.expect(body:find('Take a needed Echo',1,true)==1 and not body:find('Shard',1,true),
  'P9: the recommendation names no target with a quality read from the text',body)
 C.guard(Effects()==before,'P9: rendering chooses, takes, sends and toggles nothing',Effects())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Play offer cards, waiting state, Auto ON line, 125% fit model and layout fallback; native NOT RUN)')
