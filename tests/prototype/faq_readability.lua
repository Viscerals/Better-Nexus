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
C.setup(#groups==7 and groups[1].q=='What do I do next?' and groups[2].q=='Which Wishlist is Nexus using?'
 and groups[3].q=='What does Auto do?' and groups[4].q=='Does Auto OFF stop Sync?','fixture: the FAQ page holds its seven questions',#groups)
local before=Effects()

C.scenario('Q1 every question is a gold line of its own; answers stay uncoloured; wording unchanged',function()
 Help.Show('faq')
 local w=_G.NexusHelpWindow
 local body=w.body:GetText() or ''
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
 for _,p in ipairs(Help.Pages) do
  if p.id~='faq' and p.id~='rolling' then
   Help.Show(p.id)
   C.guard(w.body:GetText()==p.text,'Q2: the '..p.id..' page text is shown exactly as before')
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
   local rows=G.Rows(w.body:GetText(),585,model.char)
   local need=rows*model.line
   local body,content,scroll=w.body:GetHeight(),w.content:GetHeight(),w.scroll:GetHeight()
   C.expect(V.Plain(w.body:GetText()):find('\n\n\n',1,true)~=nil,'Q3 '..model.name..': the groups carry their extra gap')
   C.guard(body>=need and content>body,'Q3 '..model.name..': the body covers every wrapped row ('..rows..') and the scroll child is taller',
    body..' / '..need..' / '..content)
   C.guard(need<=scroll or content-scroll>=need-scroll,'Q3 '..model.name..': the last answer is inside the scroll range',
    content..' / '..scroll)
  end
 end
 Help.Hide()
end)

C.scenario('Q4 reading the FAQ changes nothing',function()
 Help.Show('faq');Help.Hide()
 C.guard(Effects()==before and Nexus.RecomputeStats().autoEnabled==false,'Q4: no saved data, Auto, action or send changed',Effects())
end)

C.finish('(FAQ question colour, group spacing and measured height over stated font models; native colour, contrast and glyph fit NOT RUN)')
