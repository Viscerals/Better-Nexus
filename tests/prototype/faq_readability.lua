-- Owner-approved FAQ readability (issue #169, with its #131 / #163 context):
-- native test.163012's Reference > Questions (FAQ) page showed every question
-- in the same white as its answer, one blank line apart, so the questions
-- blended into the answer paragraphs. The FAQ page now draws each question
-- line in the Nexus heading gold (|cffffd100, the colour the panel already
-- uses for its headings) and leaves the answer in the page's white body font;
-- question/answer groups are one extra blank line apart.
-- Q1 every FAQ question is a gold line of its own and no answer line is
--    coloured; the wording and the order are unchanged (the visible text is
--    the page text with one more blank line between groups);
-- Q2 the body keeps its white GameFontHighlight face, left justification and
--    word wrap; no other Reference page is recoloured or respaced;
-- Q3 at every supported font model (0.75 to 2.0 scale, a 16 px face) the
--    measured body height covers every wrapped row, the gaps included, and
--    the scroll child is taller than the body, so the last answer is inside
--    the scroll range;
-- Q4 reading the FAQ changes no saved data, Auto, action or send.
-- Categories (view_regression_support): EXPECT is behaviour this change adds
-- (fails at b1ef408: questions are plain text one blank line apart), GUARD
-- already held, SETUP is the fixture. Text measurement follows the stated
-- font models (layout_geometry_support); native glyph widths, colour
-- rendering and contrast are NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('faq_readability')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
Nexus.DisableOrdinaryAutomation()
local Help=Nexus.Help
-- Observation only: the template a font string is made from, its
-- justification and any text colour set on it (the harness keeps none).
local RM=G.RegionMethods()
do
 local create=rawget(RM,'CreateFontString')
 RM.CreateFontString=function(self,name,layer,template,...)
  local r=create(self,name,layer,template,...)
  r._template=template
  return r
 end
 RM.SetJustifyH=function(self,v) self._justify=v end
 RM.SetTextColor=function(self,...) self._color={...} end
end
C.setup(_G.NexusHelpWindow==nil,'fixture: the Reference window is made after the observers')
local GOLD='|cffffd100'
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local function Page(id)
 for _,p in ipairs(Help.Pages) do if p.id==id then return p end end
end
-- The page text's groups: blank-line separated, the first line a question.
local function Groups(text)
 local out={}
 for block in (text..'\n\n'):gmatch('(.-)\n\n') do
  if block~='' then
   local q,a=block:match('^([^\n]*)\n(.*)$')
   out[#out+1]={q=q or block,a=a or ''}
  end
 end
 return out
end
local faq=Page('faq')
local groups=Groups(faq.text)
-- v39 (C): the FAQ keeps its original seven groups, word for word and in
-- order, and appends the eight accepted r3 groups after them (15 in all).
-- Both are restated here independently (FAQ_DRAFT r3 lines 34-56; the old
-- seven as Source 35 ships them); nothing is read from the new production.
local OLD7={
 {q='What do I do next?',a='Follow the step the panel shows, or Setup / Welcome (button above): it opens the guide at the step you left. Opening it changes nothing.'},
 {q='Which Wishlist is Nexus using?',a='The Wishlist line on the panel is the assigned Wishlist of your active Saved Build. A Wishlist you only selected, an example, or a Community build marked Preview is not used for rolling until you assign it in the Echo Journal chooser (Assign Wishlist... above).'},
 {q='What does Auto do?',a='Auto OFF: Nexus only recommends and you choose. Auto ON: your enabled actions may Take, Banish, Reroll and Freeze for you, and may save a better finished run over your Saved Build. Every permission and its current value: Options > Auto explained, or the Auto tab above.'},
 {q='Does Auto OFF stop Sync?',a='No. Sync has its own mode (Automatic, Manual or Off) in Sync settings; see the Sharing tab.'},
 {q='Pause, hide or Auto OFF?',a='Auto OFF stops automatic actions only. Hide Nexus Panel only hides the panel. Pause Nexus for this session (Options) holds Auto, Orb actions, sharing and DPS recording until you choose Resume Nexus, reload or log out. It is kept in memory only. Your windows, status and the checks on an action already sent stay available. An action already sent may still finish: pausing cancels nothing that was sent, Nexus stays loaded, and it does not stop all of its work on your computer. A reload does not decide a result that is still unknown. After Resume Nexus, Auto can continue if it was already on; an Orb run that is still ON continues, and Stop ends it.'},
 {q='Can I make the panel smaller or move it?',a="Options > Main panel size makes the main panel 50% to 150%; Reset to 100% puts it back. A screen too small for that size shows it smaller until it fits. Other Nexus windows, the Wishlist overlay, the game's own difficulty HUD and your UI scale keep their own size. Hold Shift and drag any part of the panel that is not a button to move it. Release Shift to stop. Options > Reset Panel Position puts it back."},
 {q='How do I get back to what I was doing?',a='Close this window (Close or Escape). Reading these pages changed no setting, assignment or Auto.'},
}
local NEW8={
 {q="Why doesn't an Echo I can see count for my Wishlist?",a='A target is one exact Echo at one exact quality. A lower-quality copy does not count for a higher-quality target; on the panel, an offer at another quality can show Wrong quality. An Echo your Wishlist does not ask for never counts. Only copies you have count, up to the copies the plan asks for; locked copies count only up to its locked targets. Copies above a target are extras. See the Wishlists tab above.'},
 {q='Does Auto ON start an Orb run, and is there a maximum?',a='No. Auto never starts an Orb run. A run starts only when you open Orbs and click Start; starting it leaves ordinary Automation as it is. There is no maximum: Nexus uses one Orb per replacement and stops when your rolled targets are complete, when you press Stop, or when no Orb can be used safely.'},
 {q="Why can't I start an Orb run, or why did it stop early?",a='Open the Orb window: it shows what is blocked, then what you can do now. An Orb action from before a reload without a confirmed result is kept as history; it does not hold a new Start. A run ends when your rolled targets are complete, when no Orb or safe source is left, when you press Stop, or when the active loadout changes. Orb mode never changes locked Echo slots. A reload does not settle an unknown result. Do not clear saved data. See the Orbs tab above.'},
 {q='Can Auto replace a Saved Build that has Echoes I value?',a='Yes, while Auto is ON. After a finished run, Nexus may save it over your active Saved Build when overall Wishlist progress is higher, or equal with cleanup. It counts Wishlist progress, not Orbs spent, so an Echo you got with Orbs can be lost. At level 80 after a finished run, turning Auto ON or changing the assigned Wishlist can lead to a replacement without a new run. Saving edits to the assigned Wishlist can also lead to a replacement without a new run. Nexus cannot undo a save, and Unassign does not restore a Saved Build. There is no separate automatic-save switch: keep Auto OFF to leave it unchanged.'},
 {q='Does a hidden panel stay hidden after a reload?',a="Yes. Hide Nexus Panel is saved as your choice, so the panel stays hidden after a reload or login. Type /nexus panel to show it again. If Nexus's saved data is read-only, the choice lasts this session only. Hiding changes no Auto setting."},
 {q='Why is the Build Library empty?',a='Check the scope: All Shared, or Mine (your Saved Builds and shared listings). The class button can limit the list to your current class; click it to switch between your class and all classes. Require both DPS records lists only builds with both a Training Dummy and a Lich King record this client holds; uncheck it to drop that requirement. Updating results... means a filter change is still applying, and a gray Explore control means shared views are loading or unavailable (/nexus loading). The list shows only what this client has stored. See the Sharing tab above.'},
 {q='Something went wrong. What do I do before a reload?',a='Do not reload, relog or change builds first. Type /nexus report, click Copy summary and paste it into your report. Add your exact build (/nexus update shows it), what happened versus what you expected, and Auto ON or OFF. If reporting fails or says Not prepared, say so and send what you have. Never post the report file in public. See the Problems tab above.'},
 {q='Can Nexus pick Echoes while I level without a Wishlist?',a="Yes, with Random Roll, an optional mode. Type /nexus leveling on or /nexus leveling off; /nexus leveling alone shows whether it is ON or OFF. It picks only when no Wishlist is assigned, at levels 2 to 79, with Auto ON and its Take permission allowed. Turning it on does not turn Auto ON. It takes the highest-rarity Echo offered (the first offer on a tie), not a random one. If an offer's rarity is unknown, it waits: pick by hand. It never rerolls, banishes, freezes, spends, saves or uses Orbs, and it makes no new pick at level 80. An assigned Wishlist always uses the normal rules instead."},
}
local oldKept=#groups>=7
for i,g in ipairs(OLD7) do
 if not (groups[i] and groups[i].q==g.q and groups[i].a==g.a) then oldKept=false end
end
C.setup(oldKept,'fixture: the FAQ page holds its original seven questions and answers first, unchanged',#groups)
local before=Effects()

C.scenario('Q1 every question is a gold line of its own; answers stay uncoloured; wording unchanged',function()
 Help.Show('faq')
 local w=_G.NexusHelpWindow
 -- The whole stored FAQ document (all shown parts, V.HelpDocument), exact.
 local body=V.HelpDocument(w)
 for i,g in ipairs(groups) do
  local line=GOLD..g.q..'|r'
  local at=body:find(line,1,true)
  C.expect(at~=nil and (at==1 or body:sub(at-1,at-1)=='\n') and body:sub(at+#line,at+#line)=='\n',
   'Q1: question '..i..' ('..g.q..') is a gold line of its own')
 end
 local coloured=0
 for line in (body..'\n'):gmatch('(.-)\n') do
  if line:find('|c',1,true) and not (line:sub(1,#GOLD)==GOLD and line:sub(-2)=='|r') then coloured=coloured+1 end
 end
 C.guard(coloured==0,'Q1: no answer line carries a colour code',coloured)
 local parts={}
 for _,g in ipairs(groups) do parts[#parts+1]=g.q..'\n'..g.a end
 C.expect(V.Plain(body)==table.concat(parts,'\n\n\n'),'Q1: the visible text is the page text, one more blank line between groups')
 C.guard(V.Plain(body):gsub('\n\n\n','\n\n')==faq.text,'Q1: the wording and the order of every question and answer are unchanged')
 Help.Hide()
end)

C.scenario('Q2 the body keeps its white face; other pages are unchanged',function()
 Help.Show('faq')
 local w=_G.NexusHelpWindow
 C.guard(w.body._template=='GameFontHighlight' and w.body._color==nil and w.body._justify=='LEFT',
  'Q2: the body keeps its white GameFontHighlight face, no recolouring and left justification',
  tostring(w.body._template)..' '..tostring(w.body._justify))
 -- Every part of the pool is made like the body (Help.lua NewPart).
 local odd=0
 for _,part in ipairs(w.parts or {w.body}) do
  if not (part._template=='GameFontHighlight' and part._color==nil and part._justify=='LEFT') then odd=odd+1 end
 end
 C.guard(odd==0,'Q2: every document part keeps the same white face, no recolouring and left justification',odd)
 local L=Nexus.Localization
 for _,p in ipairs(Help.Pages) do
  if p.id~='faq' and p.id~='rolling' then
   Help.Show(p.id)
   -- Accepted v23 form, restated independently: the page title as the gold
   -- heading, a blank line, then the complete page text with '|' written
   -- '||' (V.HelpReferenceExpected), compared with the whole shown document.
   local title=L and L.Text and p.titleKey and L.Text(p.titleKey) or p.title
   local ok,doc=pcall(V.HelpDocument,w)
   C.guard(ok and doc==V.HelpReferenceExpected(title,p.text),'Q2: the '..p.id..' page text is shown exactly, under its title',
    ok and doc:sub(1,80) or doc)
  end
 end
 Help.Hide()
end)

C.scenario('Q3 the measured height covers every wrapped row and keeps the last answer in the scroll range',function()
 for _,key in ipairs({'small','default','px16','double'}) do
  local model=G.MODELS[key]
  if model then
   G.UseFont(model)
   Help.Show('start');Help.Show('faq')
   local w=_G.NexusHelpWindow
   -- Every shown part of the document (Help's part pool; the FAQ may span
   -- more than one part once it holds fifteen groups): each part covers its
   -- own wrapped rows, and the scroll child covers all of them.
   local parts=V.HelpParts(w) or {w.body}
   local rows,need,heights,short=0,0,0,0
   for _,part in ipairs(parts) do
    local r=G.Rows(part:GetText(),585,model.char)
    rows=rows+r;need=need+r*model.line;heights=heights+part:GetHeight()
    if part:GetHeight()<r*model.line then short=short+1 end
   end
   local content,scroll=w.content:GetHeight(),w.scroll:GetHeight()
   C.expect(V.Plain(V.HelpDocument(w)):find('\n\n\n',1,true)~=nil,'Q3 '..model.name..': the groups carry their extra gap')
   C.guard(short==0 and heights>=need and content>=heights,'Q3 '..model.name..': every part covers its wrapped rows ('..rows..' in '..#parts
    ..' parts) and the scroll child holds them all',heights..' / '..need..' / '..content)
   C.guard(need<=scroll or content-scroll>=need-scroll,'Q3 '..model.name..': the last answer is inside the scroll range',
    content..' / '..scroll)
  end
 end
 Help.Hide()
end)

C.scenario('Q5 v39 (C): the eight accepted groups follow the original seven, gold questions and white answers, the last answer at the end',function()
 -- Independent text contract of the eight new groups: a question is one line
 -- of at most 256 bytes, an answer at most 1024 bytes, neither holds a '|',
 -- a brace or a line feed in an answer.
 local contract=#NEW8==8
 for _,g in ipairs(NEW8) do
  if #g.q>256 or g.q:find('[\n|{}]') or #g.a>1024 or g.a:find('[\n|{}]') then contract=false end
 end
 C.setup(contract,'Q5: the eight accepted groups are within the text and block contracts')
 Help.Show('start');Help.Show('faq')
 local w=_G.NexusHelpWindow
 local ok,doc=pcall(V.HelpDocument,w)
 doc=ok and doc or ''
 -- The accepted FAQ form, restated: each group's question line in the heading
 -- gold, its answer white on the next line, groups one more blank line apart.
 local want={}
 for _,g in ipairs(OLD7) do want[#want+1]=GOLD..g.q..'|r\n'..g.a end
 for _,g in ipairs(NEW8) do want[#want+1]=GOLD..g.q..'|r\n'..g.a end
 local expected=table.concat(want,'\n\n\n')
 C.expect(ok and doc==expected,'Q5: the shown FAQ is the original seven then the eight accepted groups, exactly (15 groups)',
  ok and (#doc..' bytes, ends "'..doc:sub(-60)..'"') or doc)
 local gold,coloured=0,0
 for line in (doc..'\n'):gmatch('(.-)\n') do
  if line:sub(1,#GOLD)==GOLD and line:sub(-2)=='|r' then gold=gold+1
  elseif line:find('|c',1,true) then coloured=coloured+1 end
 end
 C.expect(gold==15 and coloured==0,'Q5: fifteen gold question lines and no coloured answer line ('..gold..' gold, '..coloured..' coloured)')
 local last=NEW8[#NEW8].a
 C.expect(doc:sub(-#last)==last,'Q5: the Random Roll answer is the last text of the page')
 Help.Hide()
end)

C.scenario('Q4 reading the FAQ changes nothing',function()
 Help.Show('faq');Help.Hide()
 C.guard(Effects()==before and Nexus.RecomputeStats().autoEnabled==false,'Q4: no saved data, Auto, action or send changed',Effects())
end)

C.finish('(FAQ question colour, group spacing and measured height over stated font models; native colour, contrast and glyph fit NOT RUN)')
