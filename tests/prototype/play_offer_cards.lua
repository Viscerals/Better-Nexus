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

C.scenario('P2 three offer cards side by side, the Wishlist pick set apart, and nothing chosen',function()
 local before=Effects()
 C.setup(P.Render(Model({auto=false,cards=CARDS}))==true and NexusPanel:IsShown(),'P2: fixture: the HUD renders an offer with Auto OFF')
 local cards=NexusPanel._offerCards
 C.expect(type(cards)=='table' and #cards==3,'P2: the HUD has three offer cards')
 if type(cards)~='table' then return end
 local shown=0
 for i=1,3 do if cards[i]:IsShown() then shown=shown+1 end end
 C.expect(shown==3,'P2: every offered card is shown',tostring(shown))
 C.expect(cards[1].name:GetText()=='Cinder Lattice' and cards[1].quality:GetText()=='Epic'
  and cards[1].tag:GetText()==R.OFFER_PICK_TAG and cards[1]._nexusMarked==true,
  'P2: the marked card names its Echo, its quality and the Wishlist pick',tostring(cards[1].tag:GetText()))
 C.expect(cards[2]._nexusMarked==false and cards[3]._nexusMarked==false,'P2: only the runtime-marked card is set apart')
 C.expect(cards[3].quality:GetText()=='Uncommon' and cards[3].tag:GetText()==R.OFFER_GUARANTEED_TAG,
  'P2: the guaranteed card says so on its tag line')
 -- design/current "Nexus Main Panel - Compact Redesign": compact offer rows.
 C.expect(cards[1]._nexusLayout=='rows','P2: the offers are compact rows, one per offer',tostring(cards[1]._nexusLayout))
 C.expect(cards[1]._nexusFull=='Cinder Lattice (Epic) wanted','P2: the complete card line stays on its hover')
 C.expect(Heading():find('Current offer - you choose',1,true)~=nil,'P2: the heading says the player chooses',Heading())
 -- Geometry: disjoint full-width rows inside the roll area, within the card band.
 local area=NexusPanel._rollArea
 local layout=NexusPanel._responsiveLayout
 -- Offer-row spacing: a row is its small line with a row gap above and below, a row gap from the next.
 local rowGap=layout and math.max(2,math.floor(layout.gap/3)) or 0
 local band=layout and 3*(layout.small+2*rowGap)+2*rowGap or 0
 local lastBottom,inside,first=nil,true,nil
 for i=1,3 do
  local point,relative,_,x,y=cards[i]:GetPoint()
  first=first or -y
  if point~='TOPLEFT' or relative~=area or x<0 or x+cards[i]:GetWidth()>area:GetWidth() or y>0
   or (lastBottom and -y<lastBottom) then inside=false end
  lastBottom=-y+cards[i]:GetHeight()
 end
 C.expect(inside,'P2: the offers are three disjoint rows inside the roll area')
 C.expect(layout and lastBottom and first and lastBottom-first<=band and cards[1]:GetHeight()==layout.small+2*rowGap,
  'P2: the three rows stay within the band the card rows reserve',tostring(lastBottom)..'-'..tostring(first)..'/'..band)
 local clickable=false
 for i=1,3 do
  if cards[i]:GetScript('OnClick') or cards[i]:GetScript('OnMouseUp') or cards[i]:GetScript('OnMouseDown') then clickable=true end
 end
 C.guard(not clickable,'P2: a card has no click: it never chooses, banishes, rerolls or freezes')
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
 C.expect(cards and cards[1].tag:GetText()==R.OFFER_RECOMMENDED_TAG,'P4: the marked card is recommended, not promised')
 C.expect(Heading():find('Current offer - Auto ON',1,true)~=nil,'P4: the heading says Auto is ON',Heading())
 -- The Auto ON line is the panel's own visible row below the offer (the
 -- design's always-shown note), not a hover and not part of the body.
 local scope=NexusPanel._autoScopeText
 local boxes=NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.boxes or {}
 C.expect(scope~=nil and scope:IsShown() and Visible(scope:GetText())==R.AUTO_ON_NOTE,
  'P4: the Auto ON line is shown in full on the panel',scope and scope:GetText())
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

-- The original design shows the Auto ON note whenever Auto is ON with an
-- offer; it must not retreat into the Auto hover when a recommendation is
-- present. Fit is the offline conservative text model only (native NOT RUN).
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

C.scenario('P7 at 125% text the offer heading and every card status line fit without moving meaning to a hover',function()
 local before=Effects()
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
  -- The shorter heading forms begin with whose choice it is ('You choose',
  -- P1), so that phrase is matched without case; the Auto state and the
  -- destination are matched exactly.
  C.expect(shown:lower():find(case[2]:lower(),1,true)~=nil and shown:find(case[3],1,true)~=nil and shown:find('Slot 2',1,true)~=nil,
   tag..': it still says whose choice it is, the Auto state and the destination',shown)
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
  and Visible(c1.tag:GetText())==R.OFFER_PICK_TAG and Fits(c1.tag),
  'P7: a marked guaranteed card shows its guarantee and the pick, both whole',c1 and Visible(c1.quality:GetText()))
 G.UseFont(G.MODELS.default)
 P.Render(Model({auto=false}))
 C.setup(P.Render(Model({auto=false,cards=CARDS}))==true,'P7: fixture: the stock model again')
 C.guard(Heading():find('Current offer - you choose',1,true)~=nil and NexusPanel._offerCards[1]._nexusLayout=='rows',
  'P7: with room the full heading returns, the offers stay compact rows',Heading())
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
  and c[1].tag:GetText()==R.OFFER_PICK_TAG and c[1]._nexusFull==line and c[1]._nexusMarked==true,
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
