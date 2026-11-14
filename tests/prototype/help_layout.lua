-- Structural rendering checks; native text fit/clicks remain a separate gate.
local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
-- The reference pages open with /nexus reference (/nexus help opens the coach).
SlashCmdList.NEXUS('reference');local f=assert(NexusHelpWindow)
local scroll=assert(NexusHelpScroll);local child=assert(f.content)
assert(scroll:GetFrameLevel()>f:GetFrameLevel(),'Help scroll must render above its opaque parent')
assert(f:GetFrameLevel()<100 and child:GetFrameLevel()<128,'keep every Help layer below the observed native clamping boundary')
assert(child:GetFrameLevel()>=scroll:GetFrameLevel(),'Help body must render above its scroll viewport')
assert(child:GetNumPoints()>0,'Help body needs an explicit viewport anchor')
local navigation={}
for _,b in ipairs(H.frames)do if b.kind=='Button' and b:GetParent()==f then
 assert(b:GetFrameLevel()>f:GetFrameLevel(),'Help navigation must render and receive clicks above the parent')
 navigation[b:GetText()]=b
end end
for i=1,7 do
 assert(f.body:IsVisible() and #f.body:GetText()>300,'complete Help body visible on page '..i)
 assert(f.body:GetWidth()>400 and f.body:GetHeight()>0,'Help body has explicit dimensions')
 assert(child:GetHeight()>=f.body:GetHeight(),'scroll child cannot clip its text')
 navigation.Next:Click()
end
navigation.Previous:Click();navigation.Close:Click();assert(not f:IsShown())
SlashCmdList.NEXUS('reference');assert(f:IsShown() and f.body:IsVisible())
assert(#H.actions==0 and #H.sent==0,'Help is passive before readiness')
-- v23 (A), refined per ROOT_TEST_DISPOSITION: every full manual page reads
-- like Questions (FAQ). Each of the seven non-FAQ pages opens its body with
-- its own existing localized page title (pages[].titleKey, the name its tab
-- and window title already use) as a heading in the Nexus heading gold
-- (|cffffd100) on its own line. No new heading text, key or API is required,
-- and a paragraph needs no heading of its own. The body keeps the white body
-- font: every block of a paragraph with more than one block, and every
-- multi-line block, carries no heading gold. A genuine existing label block
-- (help.label.*) is gold. A one-line block that is a whole paragraph by
-- itself may be gold or white, but never partly gold. Paragraphs stay a
-- blank line apart; list lines keep their own lines. The meaning is the
-- localized PageBlocks text, complete and in order, with every command exactly
-- as typed. H.PageText stays the raw, unformatted text. Questions (FAQ) is
-- shown exactly as today: H.FormatQuestions of its PageText. Nothing parses
-- English. Reading and navigating change nothing.
-- Commands: Localization inserts a text slot verbatim (core/Localization.lua
-- 181-183, SlotText 4582-4585) and a catalog block may not hold "|" (170-172),
-- so a code-owned command such as "/nexus policy adaptive|released" reaches the
-- body with a bare "|r" that the client reads as a colour reset. It shows
-- only if the shown text escapes it ("||").
-- Offline model: the shown text is read with the client's escapes (|| is one
-- pipe, |cAARRGGBB opens a colour, |r always ends it); native glyphs, wrap and
-- scrolling are NOT_RUN. Misses are collected, then raised together.
do
 local Help=assert(Nexus.Help,'SETUP: the Help module');local L=Nexus.Localization
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local GOLD='ffffd100'
 -- What the client shows: the visible bytes and, per byte, heading gold or not.
 local function Shown(s)
  local out,gold,i,colour={},{},1,nil
  while i<=#s do
   local c=s:sub(i,i)
   if c=='|' and s:sub(i+1,i+1)=='|' then out[#out+1]='|';gold[#out]=colour==GOLD;i=i+2
   elseif c=='|' and s:sub(i+1,i+1)=='c' and s:sub(i+2,i+9):match('^%x%x%x%x%x%x%x%x$') then colour=s:sub(i+2,i+9):lower();i=i+10
   elseif c=='|' and s:sub(i+1,i+1)=='r' then colour=nil;i=i+2
   else out[#out+1]=c;gold[#out]=colour==GOLD;i=i+1 end
  end
  return table.concat(out),gold
 end
 -- What a catalog string means to the reader: its own colour spans are
 -- presentation, || is one pipe, and a |r that closes no colour is a literal
 -- pipe and r (as in a typed command such as "adaptive|released").
 local function Meaning(s)
  local out,i,open={},1,false
  while i<=#s do
   local c=s:sub(i,i)
   if c=='|' and s:sub(i+1,i+1)=='|' then out[#out+1]='|';i=i+2
   elseif c=='|' and s:sub(i+1,i+1)=='c' and s:sub(i+2,i+9):match('^%x%x%x%x%x%x%x%x$') then open=true;i=i+10
   elseif c=='|' and s:sub(i+1,i+1)=='r' and open then open=false;i=i+2
   else out[#out+1]=c;i=i+1 end
  end
  return table.concat(out)
 end
 local function Localized(b)
  if type(L)~='table' then return nil,'unavailable' end
  if b[3] then return L.Format(b[1],b[3]) end
  return L.Text(b[1])
 end
 local function Groups(blocks)
  local groups,cur={},nil
  for i,b in ipairs(blocks) do
   if not cur then cur={first=i,blocks={}};groups[#groups+1]=cur end
   cur.blocks[#cur.blocks+1]=i
   if b[2]=='\n\n' or b[2]==nil then cur=nil end
  end
  return groups
 end
 -- The page's own shown title, as Help names it (its titleKey, else its
 -- English title when the key cannot be shown).
 local function Title(p)
  if type(L)=='table' and type(p.titleKey)=='string' then
   local text,source=L.Text(p.titleKey)
   if type(text)=='string' and source~='unavailable' then return text end
  end
  return p.title
 end
 -- Measured height: whole wrapped lines of the shown text at the body width
 -- (about 7 units a character, 14 a row); a test-local stand-in for the
 -- client's GetStringHeight, which the harness answers with one row.
 local function Rows(text,width)
  local visible=Shown(text or '')
  local per=math.max(20,math.floor((tonumber(width) or 585)/7))
  local rows=0
  for line in (visible..'\n'):gmatch('(.-)\n') do rows=rows+math.max(1,math.ceil(#line/per)) end
  return rows
 end
 rawset(f.body,'GetStringHeight',function(self) return Rows(self:GetText(),self:GetWidth())*14 end)
 local function Serialize(v,seen)
  if type(v)~='table' then return type(v)..':'..tostring(v) end
  seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
  local out={'{'};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen)..',' end
  seen[v]=nil;return table.concat(out)..'}'
 end
 local saved,acts,sent=Serialize(NexusDB),#H.actions,#H.sent
 local rawBefore={}
 for _,p in ipairs(Help.Pages) do rawBefore[p.id]=Help.PageText(p) end
 local groupsSeen,headed=0,0
 for _,p in ipairs(Help.Pages) do
  local blocks=Help.PageBlocks and Help.PageBlocks[p.id]
  expect(type(blocks)=='table' and #blocks>0,'SETUP: '..p.id..' has PageBlocks identities')
  Help.Show(p.id)
  local display=f.body:GetText() or ''
  local V,gold=Shown(display)
  local raw=Help.PageText(p)
  expect(raw==rawBefore[p.id] and not raw:find('|c'..GOLD,1,true),
   p.id..': H.PageText stays the raw, unformatted text (formatting is display only)')
  local cursor,prevEnd,titleEnd=1,nil,nil
  if p.id=='faq' then
   -- Questions keeps its accepted look exactly: seven gold questions.
   expect(display==Help.FormatQuestions(raw),'faq: Questions is shown exactly as H.FormatQuestions of its PageText (unchanged)')
  else
   -- The page's own title opens the body, in the heading gold, on its own line.
   local title=Meaning(Title(p) or '')
   local at=V:match('^%s*()')
   -- Matched only when it is gold, so body text that happens to begin with
   -- the same word is never taken for the heading.
   local wrong=0
   if title~='' and V:sub(at,at+#title-1)==title then
    for j=at,at+#title-1 do if not gold[j] then wrong=wrong+1 end end
   end
   if title~='' and V:sub(at,at+#title-1)==title and wrong==0 then
    titleEnd=at+#title-1;cursor=titleEnd+1;headed=headed+1
   else
    expect(false,p.id..': the body opens with its page title "'..title..'" as a gold heading')
   end
  end
  for gi,g in ipairs(type(blocks)=='table' and Groups(blocks) or {}) do
   groupsSeen=groupsSeen+1
   local lastEnd
   for n,bi in ipairs(g.blocks) do
    local b=blocks[bi]
    local text=Localized(b)
    local m=Meaning(type(text)=='string' and text or '')
    local s=m~='' and V:find(m,cursor,true) or nil
    if not s then
     expect(false,p.id..': '..b[1]..' is shown complete and in order (exact localized meaning)')
    else
     local goldBytes=0;for j=s,s+#m-1 do if gold[j] then goldBytes=goldBytes+1 end end
     if b[1]:find('^help%.label%.') then
      expect(goldBytes==#m,p.id..': the label '..b[1]..' is drawn in the heading gold ('..(#m-goldBytes)..' bytes are not)')
     elseif #g.blocks==1 and not m:find('\n',1,true) then
      expect(goldBytes==0 or goldBytes==#m,p.id..': the one-line paragraph '..b[1]..' is wholly white or wholly gold ('..goldBytes..' of '..#m..' gold)')
     else
      expect(goldBytes==0,p.id..': '..b[1]..' is white body text, not heading gold ('..goldBytes..' bytes gold)')
     end
     if n==1 then
      if gi==1 and titleEnd then
       local between=V:sub(titleEnd+1,s-1)
       expect(between:find('\n',1,true) and not between:find('%S'),p.id..': the title heading sits on its own line above the first paragraph')
      end
      if prevEnd then
       local between=V:sub(prevEnd+1,s-1)
       expect(between:find('\n\n',1,true)~=nil and not between:find('%S'),
        p.id..': paragraph '..gi..' ('..b[1]..') is a blank line apart from the one before')
      end
     elseif lastEnd then
      local sep=blocks[bi-1][2];local between=V:sub(lastEnd+1,s-1)
      if sep=='\n' then
       expect(between:find('\n',1,true) and not between:find('%S'),p.id..': the list line '..b[1]..' keeps its own line')
      elseif sep==' ' then
       expect(not between:find('\n\n',1,true),p.id..': '..b[1]..' stays in its paragraph')
      end
     end
     lastEnd=s+#m-1;cursor=lastEnd+1
    end
    if type(b[3])=='table' then
     for k,v in pairs(b[3]) do
      if type(v)=='string' then expect(V:find(v,1,true)~=nil,p.id..': the command '..k..' shows exactly as typed: '..v) end
     end
    end
   end
   prevEnd=lastEnd or prevEnd
  end
  local rows=Rows(display,f.body:GetWidth())
  expect(f.body:GetHeight()>=rows*14 and child:GetHeight()>=f.body:GetHeight(),
   p.id..': the scroll body is measured after formatting and holds every shown row ('..rows..' rows, body '
   ..tostring(f.body:GetHeight())..', content '..tostring(child:GetHeight())..')')
  expect(f.body:IsVisible() and f.body:GetParent()==child and child:GetParent()==scroll,p.id..': the page scrolls inside its own viewport')
 end
 expect(groupsSeen>=30,'SETUP: the manual has its paragraphs ('..groupsSeen..')')
 -- Every route between pages: page buttons, Next to the end, Previous back,
 -- Start page, and Close. None writes, acts or sends.
 for _,t in ipairs(f.tabs or {}) do t:Click() end
 for _=1,#Help.Pages do navigation.Next:Click() end
 for _=1,#Help.Pages do navigation.Previous:Click() end
 navigation['Start page']:Click();navigation.Close:Click()
 for _,p in ipairs(Help.Pages) do Help.PageText(p);Help.Show(p.id) end
 Help.Hide()
 expect(Serialize(NexusDB)==saved,'showing, reading and navigating every page writes no saved data')
 expect(#H.actions==acts and #H.sent==sent,'and takes no game action and sends nothing')
 if #misses>0 then
  local shown={};for i=1,math.min(#misses,60) do shown[i]=misses[i] end
  error('v23 manual format: '..#misses..' expectation(s) missed ('..headed..' of 7 manual pages open with their gold title; '
   ..groupsSeen..' paragraphs read):\n'
   ..table.concat(shown,'\n'),0)
 end
end
print('PASS explicit Help layering, anchors, text dimensions, seven-page navigation and passive reopen')
