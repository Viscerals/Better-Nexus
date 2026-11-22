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
-- v28 r3 representation (read seam only): the Reference document is every
-- FontString under the scroll child (the content frame), in its harness
-- creation order (a depth-first walk of .children). The shown document is the
-- VISIBLE ones, read as they store their text (GetText), joined at part
-- boundaries by a line break. With all=true every document FontString is
-- listed, shown or not (for fixtures that must reach each one).
local function DocumentParts(all)
 local out={}
 local function walk(o)
  if o.kind=='FontString' then
   local okV,vis=pcall(function() return o:IsVisible() end)
   if all or (okV and vis) then out[#out+1]=o end
  end
  for _,c in ipairs(type(o.children)=='table' and o.children or {}) do walk(c) end
 end
 walk(child)
 return out
end
local function DocumentText()
 local t={}
 for i,fs in ipairs(DocumentParts()) do t[i]=fs:GetText() or '' end
 return table.concat(t,'\n')
end
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
 -- v28 r3: the same stand-in on every document part (f.body is part 1).
 for _,fs in ipairs(DocumentParts(true)) do
  rawset(fs,'GetStringHeight',function(self) return Rows(self:GetText(),self:GetWidth())*14 end)
 end
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
  -- v28 r3: the shown document is every visible part, as stored, in order.
  local display=DocumentText()
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
  -- v28 r3: each shown part holds its own rows, and the content holds the
  -- parts (together every row of the shown document).
  local rows=Rows(display,f.body:GetWidth())
  local partsHold,partSum,partCount,inViewport=true,0,0,true
  for _,fs in ipairs(DocumentParts()) do
   partCount=partCount+1
   local h=tonumber(fs:GetHeight()) or 0
   partSum=partSum+h
   if h<Rows(fs:GetText() or '',fs:GetWidth())*14 then partsHold=false end
   if fs:GetParent()~=child then inViewport=false end
  end
  expect(partsHold and partSum>=rows*14 and child:GetHeight()>=partSum,
   p.id..': the scroll body is measured after formatting and holds every shown row ('..rows..' rows, '
   ..partCount..' part(s) '..tostring(partSum)..', content '..tostring(child:GetHeight())..')')
  expect(f.body:IsVisible() and inViewport and partCount>0 and child:GetParent()==scroll,p.id..': the page scrolls inside its own viewport')
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
-- v28 (native test.163033-40755f5b, 2026-11-14T12:15:47Z): on the Orbs page
-- of the Reference, scrolling the body to its end showed text ending
-- mid-sentence ('... is f'); no horizontal clipping; the topic card kept.
-- Native cause UNKNOWN. This section separates the layers the text passes
-- through, using the public Help flow only:
--  A1 supply: the Orbs PageBlocks resolve through the Localization seam, and
--     with English active their joined text equals the page's English
--     reference text (Help.lua 226-232 states that equality);
--  A2 hand-off: the text Help gives the body FontString (frame.body:GetText
--     after Help.Show('orbs')) ends with that complete page text;
--  A3 formatting: H.FormatReference keeps a bounded synthetic long text
--     (UTF-8, pipes) whole;
--  B  measurement (red-capable): the scroll content holds the whole shown
--     text even when the client's FIRST GetStringHeight read after SetText
--     is not yet wrapped. Help.lua 492-494 records that caveat for the client
--     and applies it to the topic card (topicHeight), and LayoutMetrics
--     WrapHeight/TextRows/ConservativeText give the conservative model. The
--     body (Help.lua 573-577) reads GetStringHeight once.
-- A failure in A1 points before the renderer (seam or catalog); A2 or A3 to
-- Help's own hand-off; B to the body's measured scroll range. B models a
-- documented client caveat with a bounded instance mock on the real body
-- FontString (first read one row, later reads the conservative model); it
-- exposes a measurement gap consistent with, NOT proof of, the native
-- symptom. Native glyphs, wrap and any client text limit stay NOT_RUN.
do
 local Help=assert(Nexus.Help,'SETUP: the Help module')
 local LM=assert(Nexus.LayoutMetrics,'SETUP: LayoutMetrics')
 local L=Nexus.Localization
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local orbs
 for _,p in ipairs(Help.Pages) do if p.id=='orbs' then orbs=p end end
 assert(orbs and type(orbs.text)=='string' and #orbs.text>1000,'v28 SETUP: the Orbs reference page and its English text')
 local blocks=assert(Help.PageBlocks and Help.PageBlocks.orbs,'v28 SETUP: the Orbs PageBlocks')
 -- The visible characters: || is one pipe; colour codes are not visible.
 local function Visible(s)
  s=tostring(s or ''):gsub('||','\1'):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
  return (s:gsub('\1','|'))
 end
 local function Tail(s,n) s=tostring(s or '');return s:sub(math.max(1,#s-n+1)) end
 local function Serialize(v,seen)
  if type(v)~='table' then return type(v)..':'..tostring(v) end
  seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
  local out={'{'};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],seen)..',' end
  seen[v]=nil;return table.concat(out)..'}'
 end
 local saved,acts,sent=Serialize(NexusDB),#H.actions,#H.sent

 -- A1. Supply: every Orbs block resolves (no whole-page English fallback),
 -- and the joined blocks equal the English reference text.
 local unavailable={}
 if type(L)=='table' then
  for _,b in ipairs(blocks) do
   local _,source
   if b[3] then _,source=L.Format(b[1],b[3]) else _,source=L.Text(b[1]) end
   if source=='unavailable' then unavailable[#unavailable+1]=b[1] end
  end
 end
 expect(#unavailable==0,'A1 orbs: every PageBlocks key resolves through the Localization seam (unavailable: '..table.concat(unavailable,', ')..')')
 local raw=Help.PageText(orbs)
 expect(raw==orbs.text,'A1 orbs: the joined English blocks equal the page reference text before rendering ('
  ..#raw..' and '..#orbs.text..' bytes; the supplied text ends "'..Tail(raw,40)..'")')

 -- A2. Hand-off: what Help gives the body FontString ends with the whole page text.
 Help.Show('orbs')
 local f=assert(NexusHelpWindow,'v28 SETUP: the Help window');local child=assert(f.content)
 -- v28 r3: the document handed over is every visible part, as stored, in order.
 local display=DocumentText()
 local expectedBody=Visible(Help.FormatReference('',raw))
 expect(Visible(display):sub(-#expectedBody)==expectedBody,
  'A2 orbs: the document FontStrings are given the complete page text (it ends "'..Tail(Visible(display),40)..'")')

 -- A3. Formatting keeps a bounded synthetic long text whole (UTF-8 and pipes).
 local parts={}
 for i=1,600 do parts[i]='line '..i..' é Ж … a|b ' end
 local long=table.concat(parts)..'END-OF-SYNTHETIC'
 local formatted=Help.FormatReference('Orbs',long)
 local escaped=(long:gsub('|','||'))
 expect(formatted:sub(-#escaped)==escaped and Visible(formatted):sub(-#long)==long,
  'A3: H.FormatReference keeps a '..#long..'-byte synthetic text whole and in order')

 -- B. Measurement: the scroll content must hold the whole shown text when
 -- the first GetStringHeight read after SetText is unwrapped (one row).
 -- v28 r3: the same first-read mock on every document part (f.body is part
 -- 1); each shown part must hold its own stored text, and the content the
 -- whole shown document.
 local body=f.body
 local scale=LM.RuntimeMetrics and LM.RuntimeMetrics() or 1
 local _,line=LM.ConservativeText(scale)
 local function Model(text,width) return LM.TextRows(Visible(text),tonumber(width) or 585,scale)*line end
 local mocked={}
 for _,fs in ipairs(DocumentParts(true)) do
  local priorHeight,priorSet,setText=rawget(fs,'GetStringHeight'),rawget(fs,'SetText'),fs.SetText
  local reads=0
  mocked[#mocked+1]={fs=fs,height=priorHeight,set=priorSet}
  rawset(fs,'SetText',function(self,...) reads=0;return setText(self,...) end)
  rawset(fs,'GetStringHeight',function(self)
   reads=reads+1
   if reads==1 then return line end
   return Model(self:GetText(),self:GetWidth())
  end)
 end
 Help.Show('rolling');Help.Show('orbs')
 display=DocumentText()
 local need=Model(display,body:GetWidth())
 local partSum,partsHold=0,true
 for _,fs in ipairs(DocumentParts()) do
  local h=tonumber(fs:GetHeight()) or 0
  partSum=partSum+h
  if h<Model(fs:GetText() or '',fs:GetWidth()) then partsHold=false end
 end
 expect(child:GetHeight()>=need and partSum>=need and partsHold,
  'B orbs: the scroll content holds the whole shown text when the first height read is unwrapped (model '
  ..need..', parts '..tostring(partSum)..', content '..tostring(child:GetHeight())..')')
 for _,m in ipairs(mocked) do rawset(m.fs,'GetStringHeight',m.height);rawset(m.fs,'SetText',m.set) end

 Help.Hide()
 expect(Serialize(NexusDB)==saved,'v28: reading the Orbs page writes no saved data')
 expect(#H.actions==acts and #H.sent==sent,'v28: and takes no game action and sends nothing')
 if #misses>0 then
  error('v28 Orbs reference body: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0)
 end
end
-- v28 r3 C (native, unchanged test.163033-40755f5b, 2026-11-14T12:58:40Z):
-- the Orbs body FontString STORED 8189 bytes (HB); its stored tail itself
-- ended '... the server is f' (HT), exactly the visible bottom. The English
-- fallback is 8452 bytes and the formatted English 8486, ending 'Return to
-- this build to review eligibility; this does not restart spending.' The
-- exact localized input before SetText is still UNKNOWN natively; no
-- universal client byte cap is claimed, and no catalog cause is chosen.
-- Contract: the displayed Reference document keeps the whole intended
-- formatted page, as its actual FontStrings store it. Reading the GetText of
-- every visible FontString of the document (the scroll child NexusHelpScroll's
-- content frame and its descendants), in document order, gives every
-- non-empty line of H.FormatReference(title, H.PageText(orbs)), complete and
-- in order, including the final sentence, with the page title as the gold
-- heading ('|cffffd100'..title..'|r') and pipes, UTF-8 and line order kept.
-- Fixture (modelled, test-local, NOT a native contract): within this case
-- only, SetText on each document FontString stores at most 8189 bytes (the
-- observed native storage, a model of the observed class of loss). It is
-- installed on the existing body and any other existing document FontString,
-- and on every FontString created later under the document (through
-- CreateFontString of the content frame or of any frame created under it).
-- Labels outside the document (title, topic card, page label, buttons) are
-- not touched. GetText is never replaced: parts are read as stored. Every
-- mock is removed at the end.
-- Document order is the harness creation order of the content subtree (a
-- depth-first walk of .children); a renderer must keep its parts in reading
-- order there. Parts are joined at line boundaries, so a renderer must split
-- only at existing line breaks, never inside a line. On the unchanged runtime
-- one body FontString holds the page, so this case is expected to miss
-- (behavioural RED) even with the R1 conservative height in place.
do
 local Help=assert(Nexus.Help,'SETUP: the Help module')
 local L=Nexus.Localization
 local LIMIT=8189
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local f=assert(NexusHelpWindow,'r3 SETUP: the Help window');local content=assert(f.content,'r3 SETUP: the Help document frame')
 -- v47 (2026-11-19): the corrected Orbs page (no maximum, Pause or Continue
 -- text) is shorter than this storage model; the longest page, Auto, rolling
 -- and saving, keeps the case meaningful (a page longer than one part). Its
 -- live "Auto right now" lines are not this case's subject: within this case
 -- only they are left out (restored below), so the document is the page.
 local panelAuto=Nexus.Panel and Nexus.Panel.AutoDetailLines
 if Nexus.Panel then Nexus.Panel.AutoDetailLines=function() return {} end end
 local orbs
 for _,p in ipairs(Help.Pages) do if p.id=='rolling' then orbs=p end end
 assert(orbs,'r3 SETUP: the Orbs reference page')
 local function Visible(s)
  s=tostring(s or ''):gsub('||','\1'):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
  return (s:gsub('\1','|'))
 end
 local function Lines(s)
  local out={}
  for line in (Visible(s)..'\n'):gmatch('(.-)\n') do if line:find('%S') then out[#out+1]=line end end
  return out
 end
 local title=orbs.title
 if type(L)=='table' and type(orbs.titleKey)=='string' then
  local text,source=L.Text(orbs.titleKey)
  if type(text)=='string' and source~='unavailable' then title=text end
 end
 local intended=Help.FormatReference(title,Help.PageText(orbs))
 local want=Lines(intended)
 assert(#intended>LIMIT and #want>1,'r3 SETUP: the formatted Orbs page ('..#intended..' bytes) is longer than the modelled '..LIMIT..'-byte storage')
 -- The document subtree (frames and FontStrings under the content frame).
 local function InDocument(o)
  local guard=0
  while o and guard<64 do
   if o==content then return true end
   local ok,p=pcall(function() return o:GetParent() end)
   if not ok then return false end
   o=p;guard=guard+1
  end
  return false
 end
 local armed,creators={},{}
 local function Arm(fs)
  if not fs or armed[fs] or type(fs.SetText)~='function' then return end
  local prior,orig=rawget(fs,'SetText'),fs.SetText
  armed[fs]={prior=prior}
  rawset(fs,'SetText',function(self,v,...)
   local s=v
   if type(s)=='string' and #s>LIMIT then s=s:sub(1,LIMIT) end
   return orig(self,s,...)
  end)
 end
 local function WrapCreator(frame)
  if creators[frame] or type(frame.CreateFontString)~='function' then return end
  local prior,orig=rawget(frame,'CreateFontString'),frame.CreateFontString
  creators[frame]={prior=prior}
  rawset(frame,'CreateFontString',function(self,...) local fs=orig(self,...);Arm(fs);return fs end)
 end
 local function Walk(root,visit)
  visit(root)
  for _,c in ipairs(type(root.children)=='table' and root.children or {}) do Walk(c,visit) end
 end
 local foundBody=false
 Walk(content,function(o)
  if o==f.body then foundBody=true end
  if o.kind=='FontString' then Arm(o) elseif o~=nil then WrapCreator(o) end
 end)
 assert(foundBody,'r3 SETUP: the body FontString is reachable in the document subtree (.children)')
 local priorCreate=CreateFrame
 CreateFrame=function(kind,name,parent,template,...)
  local fr=priorCreate(kind,name,parent,template,...)
  local p=parent;if type(p)=='string' then p=_G[p] end
  if type(p)=='table' and InDocument(p) then WrapCreator(fr) end
  return fr
 end
 -- The real call site, twice (another page first forces a fresh SetText).
 Help.Show('orbs');Help.Show('rolling')
 local parts,stored={},0
 Walk(content,function(o)
  if o.kind=='FontString' then
   local okV,vis=pcall(function() return o:IsVisible() end)
   local okT,text=pcall(function() return o:GetText() end)
   if okV and vis and okT and type(text)=='string' and text~='' then parts[#parts+1]=text;stored=stored+#text end
  end
 end)
 local joined=table.concat(parts,'\n')
 local got=Lines(joined)
 local same=#got==#want
 if same then for i=1,#want do if got[i]~=want[i] then same=false;break end end end
 local lastWant,lastGot=want[#want] or '',got[#got] or ''
 expect(same,'C orbs: the displayed document FontStrings store every line of the formatted page, complete and in order ('
  ..#parts..' visible part(s), '..stored..' stored bytes, '..#got..' of '..#want..' lines; the stored text ends "'
  ..lastGot:sub(-40)..'", the page ends "'..lastWant:sub(-40)..'")')
 expect(lastGot==lastWant,'C orbs: the final sentence is displayed whole ("'..lastWant:sub(-60)..'")')
 local head='|cffffd100'..(tostring(title):gsub('|','||'))..'|r'
 expect(joined:match('^%s*()')~=nil and joined:sub(joined:match('^%s*()'),joined:match('^%s*()')+#head-1)==head,
  'C orbs: the document opens with the page title as the gold heading')
 -- Restore every mock: FontString SetText, CreateFontString, CreateFrame.
 for fs,r in pairs(armed) do rawset(fs,'SetText',r.prior) end
 for fr,r in pairs(creators) do rawset(fr,'CreateFontString',r.prior) end
 CreateFrame=priorCreate
 if Nexus.Panel then Nexus.Panel.AutoDetailLines=panelAuto end
 Help.Hide()
 if #misses>0 then
  error('v28 r3 Orbs document storage: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0)
 end
end
-- v28 r3 D (document switching, shrinking and reuse; read seam only). After
-- the long Orbs page, a shorter page shows exactly its own document (no part
-- still showing, or invisibly keeping, Orbs text); returning to Orbs gives
-- the same document again; cycling every page adds no FontString or frame.
-- Read through the visible parts as stored; nothing here mirrors how the
-- document is split.
do
 local Help=assert(Nexus.Help,'SETUP: the Help module')
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local byId={}
 for _,p in ipairs(Help.Pages) do byId[p.id]=p end
 assert(byId.orbs and byId.faq and byId.start,'r3 SETUP: the Orbs, Questions and Getting started pages')
 Help.Show('orbs')
 local orbsDoc=DocumentText()
 Help.Show('faq')
 local faqDoc=DocumentText()
 expect(faqDoc==Help.FormatQuestions(Help.PageText(byId.faq)),
  'D: after the Orbs page, Questions shows exactly its own document ('..#faqDoc..' bytes)')
 local visible={}
 for _,fs in ipairs(DocumentParts()) do visible[fs]=true end
 local stale=0
 for _,fs in ipairs(DocumentParts(true)) do
  if not visible[fs] and (fs:GetText() or '')~='' then stale=stale+1 end
 end
 expect(stale==0,'D: no hidden document FontString keeps text from the earlier page ('..stale..')')
 Help.Show('start');Help.Show('orbs')
 expect(DocumentText()==orbsDoc,'D: returning to Orbs shows the same document again')
 local fontStrings,frames=#DocumentParts(true),#H.frames
 for _=1,2 do for _,p in ipairs(Help.Pages) do Help.Show(p.id) end end
 expect(#DocumentParts(true)==fontStrings and #H.frames==frames,
  'D: cycling every page twice adds no document FontString ('..fontStrings..' -> '..#DocumentParts(true)
  ..') and no frame ('..frames..' -> '..#H.frames..')')
 Help.Hide()
 if #misses>0 then
  error('v28 r3 Reference document switching: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0)
 end
end
-- v28 r4 E (largest valid "Auto right now", over-budget line, shrink, reuse).
-- The Auto page appends Panel.AutoDetailLines below its reference text.
-- Contract (ui/Panel.lua 9792-9835, ui/Readout.lua 663-722, core/Localization.lua
-- MAX_TEMPLATE_RESULT_BYTES): at most 21 lines, each one Localization result
-- of at most 2048 bytes with at most a two-byte "- " prefix. Here
-- AutoDetailLines is replaced (a bounded fixture on its public entry,
-- restored after) by 21 lines of exactly 2050 bytes each (UTF-8 letters,
-- escaped pipes, a unique end marker), under R3 C's modelled 8189-byte
-- FontString storage on EVERY document FontString (existing ones and any
-- made later). Expectations: every line and the reference text reach the
-- stored document complete and in order; no part stores a partial UTF-8
-- character or a broken escape; the window keeps the FontStrings it made
-- when it was created (a contract-valid document needs no new part).
-- Then one line BEYOND the contract (6000 bytes, longer than any part,
-- inside a gold colour span) must still be stored whole across parts: the
-- visible text survives with valid UTF-8 and escapes. Then a shorter page
-- (Questions) shows exactly its own document, with no stale text in hidden
-- parts, and cycling every page adds no FontString or frame.
do
 local Help=assert(Nexus.Help,'SETUP: the Help module')
 local L=Nexus.Localization
 local LIMIT=8189
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local f=assert(NexusHelpWindow,'r4 SETUP: the Help window');local content=assert(f.content,'r4 SETUP: the document frame')
 local byId={}
 for _,p in ipairs(Help.Pages) do byId[p.id]=p end
 assert(byId.rolling and byId.faq,'r4 SETUP: the Auto and Questions pages')
 local function Visible(s)
  s=tostring(s or ''):gsub('||','\1'):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
  return (s:gsub('\1','|'))
 end
 local function Lines(s)
  local out={}
  for line in (Visible(s)..'\n'):gmatch('(.-)\n') do if line:find('%S') then out[#out+1]=line end end
  return out
 end
 local function ValidUtf8(s)
  local i=1
  while i<=#s do
   local c=s:byte(i);local n=c<128 and 0 or c>=240 and 3 or c>=224 and 2 or c>=192 and 1 or -1
   if n<0 then return false end
   for k=1,n do local d=s:byte(i+k);if not d or d<128 or d>=192 then return false end end
   i=i+n+1
  end
  return true
 end
 local function Stray(s) return (s:gsub('||',''):gsub('|r',''):gsub('|c%x%x%x%x%x%x%x%x',''):find('|',1,true))~=nil end
 -- R3 C's storage model, on every document FontString (now and later).
 local armed,creators={},{}
 local function Arm(fs)
  if not fs or armed[fs] or type(fs.SetText)~='function' then return end
  local prior,orig=rawget(fs,'SetText'),fs.SetText
  armed[fs]={prior=prior}
  rawset(fs,'SetText',function(self,v,...)
   local s=v
   if type(s)=='string' and #s>LIMIT then s=s:sub(1,LIMIT) end
   return orig(self,s,...)
  end)
 end
 for _,fs in ipairs(DocumentParts(true)) do Arm(fs) end
 local priorCreate,origCreate=rawget(content,'CreateFontString'),content.CreateFontString
 creators[content]=priorCreate
 rawset(content,'CreateFontString',function(self,...) local fs=origCreate(self,...);Arm(fs);return fs end)
 -- The largest valid Auto addition: 21 lines of 2050 bytes.
 local function Line(n,size)
  local marker=' L'..n..'-END'
  local core={}
  local used=2
  while true do
   local word='Écho Ж a||b scope '..n..' '
   if used+#word+#marker>size then break end
   core[#core+1]=word;used=used+#word
  end
  local text='- '..table.concat(core)
  return text..string.rep('x',size-#text-#marker)..marker
 end
 local maxLines={}
 for n=1,21 do maxLines[n]=Line(n,2050) end
 assert(#maxLines[1]==2050 and #maxLines[21]==2050,'r4 SETUP: each Auto line is exactly 2050 bytes')
 local panel=Nexus.Panel
 local ownPanel=type(panel)~='table'
 if ownPanel then panel={};Nexus.Panel=panel end
 local priorLines=rawget(panel,'AutoDetailLines')
 local supplied=maxLines
 rawset(panel,'AutoDetailLines',function() return supplied end)
 local fontStrings,frames=#DocumentParts(true),#H.frames
 local function PartsSafe(tag)
  local bad=0
  for _,fs in ipairs(DocumentParts()) do
   local s=fs:GetText() or ''
   if #s>LIMIT or not ValidUtf8(s) or Stray(s) then bad=bad+1 end
  end
  expect(bad==0,tag..': every stored part is whole UTF-8 with intact escapes, within the modelled storage ('..bad..' not)')
 end
 Help.Show('faq');Help.Show('rolling')
 local got=Lines(DocumentText())
 local title=byId.rolling.title
 if type(L)=='table' and type(byId.rolling.titleKey)=='string' then
  local text,source=L.Text(byId.rolling.titleKey);if type(text)=='string' and source~='unavailable' then title=text end
 end
 local ref=Lines(Help.FormatReference(title,Help.PageText(byId.rolling)))
 local refOk=#got>=#ref+#maxLines
 if refOk then for i=1,#ref do if got[i]~=ref[i] then refOk=false;break end end end
 local tailOk=refOk
 if tailOk then for n=1,#maxLines do if got[#got-#maxLines+n]~=Visible(maxLines[n]) then tailOk=false;break end end end
 expect(refOk,'E max: the Auto reference text is stored complete and in order before the Auto addition ('..#got..' lines)')
 expect(tailOk,'E max: all 21 largest valid Auto lines are stored whole and in order, the last ending "'
  ..tostring(got[#got]):sub(-12)..'"')
 PartsSafe('E max')
 expect(#DocumentParts(true)==fontStrings and #H.frames==frames and f.documentBeyondContract==nil,
  'E max: a contract-valid document uses the FontStrings made with the window ('..fontStrings..' -> '..#DocumentParts(true)..')')
 -- One line beyond the contract: 6000 bytes in a gold span, longer than any part.
 local over='|cffffd100'..Line(99,5988):sub(3)..'|r'
 supplied={over}
 Help.Show('faq');Help.Show('rolling')
 local stored={}
 for i,fs in ipairs(DocumentParts()) do stored[i]=fs:GetText() or '' end
 expect(Visible(table.concat(stored)):find(Visible(over),1,true)~=nil,
  'E over: a '..#over..'-byte line beyond the contract is stored whole across parts (its visible text survives)')
 PartsSafe('E over')
 -- Shrink and reuse.
 supplied=maxLines
 Help.Show('rolling');Help.Show('faq')
 expect(DocumentText()==Help.FormatQuestions(Help.PageText(byId.faq)),'E shrink: after the largest Auto page, Questions shows exactly its own document')
 local visible={}
 for _,fs in ipairs(DocumentParts()) do visible[fs]=true end
 local stale=0
 for _,fs in ipairs(DocumentParts(true)) do if not visible[fs] and (fs:GetText() or '')~='' then stale=stale+1 end end
 expect(stale==0,'E shrink: no hidden document FontString keeps earlier text ('..stale..')')
 local afterOver=#DocumentParts(true)
 for _=1,2 do for _,p in ipairs(Help.Pages) do Help.Show(p.id) end end
 expect(#DocumentParts(true)==afterOver and #H.frames==frames,'E reuse: cycling every page twice adds no document FontString or frame ('
  ..afterOver..' -> '..#DocumentParts(true)..')')
 -- Restore every fixture.
 rawset(panel,'AutoDetailLines',priorLines)
 if ownPanel then Nexus.Panel=nil end
 for fs,r in pairs(armed) do rawset(fs,'SetText',r.prior) end
 rawset(content,'CreateFontString',creators[content])
 Help.Hide()
 if #misses>0 then
  error('v28 r4 Auto addition and document bounds: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0)
 end
end
-- v29 F (native test.163034-8b3a5409, recorded 2026-11-14T14:09:51Z): the
-- stored Orbs document was complete (HD 3 parts, 8484 bytes, final sentence),
-- but the parts' allocated heights were about twice the client's own wrapped
-- heights (HG floored allocated/native 1480/727, 1600/775, 640/290). Dragging
-- the scrollbar to an inner point and to the bottom showed an entirely blank
-- viewport, so the final sentence could not be seen. Manual readability FAILS
-- natively.
-- Contract (product intent: complete, readable, scrollable text without
-- clipping; not a permanent conservative maximum):
--  F stable: when the client's wrapped height is valid and stable, no part is
--    shorter than its wrapped text, no part reserves more than one row of
--    empty space below its text inside the document, and at the scroll bottom
--    the last line is in view. The content is either no taller than the
--    viewport, or at most the text plus small padding; it never leaves a
--    blank bottom view. Every page is checked.
--  F stale: when the FIRST read after SetText is not yet wrapped (one row; a
--    caveat Help.lua already records for the client), nothing is clipped right
--    after showing; once the layout settles (within 0.5 s of frames) the same
--    no-gap and visible-ending contract holds; after that, further frames do
--    only bounded height work (no per-frame re-measuring).
--  F invalid: with no valid wrapped height at all (no method, no value, 0,
--    an error, NaN or infinite), every part keeps at least the conservative
--    LayoutMetrics model height and the content holds the parts: no clipping
--    or collapse.
--  F text and reuse: the stored document (under C's 8189-byte storage model)
--    is the complete formatted Orbs page, unchanged by any of this; the
--    height work adds no FontString or frame, saves nothing and acts on
--    nothing.
-- Mapping to v28 B (kept unchanged): B's settled reads ARE the conservative
-- model, so its 'each part >= model' is a no-clipping check for that
-- fixture, not a required maximum. F adds the stronger behaviour: >= the
-- settled wrapped text and <= it plus one row, for stable and stale-first
-- reads, with the conservative model required only while no valid read
-- exists (F invalid; F stale before settling).
-- Fixture (stated; a model, not a native contract): a queued-layout stand-in
-- on every document FontString, removed at the end. Its settled wrapped
-- height uses a narrower glyph (3.5 units a character, 14 a row) than the
-- conservative model (LayoutMetrics.ConservativeText: 7 and 17). That ratio,
-- about one half, is the one HG showed natively. In the stale mode a read at
-- the same harness time as the part's last SetText answers one row; a later
-- read answers the settled height. GetText is never replaced. Frames advance
-- only through the harness (H.Advance runs visible frames' OnUpdate).
-- Expected on the unchanged runtime (each part = max(read, model)): F stable
-- and F stale-settled miss (internal gaps of hundreds of units, a blank bottom
-- view). F stale-immediate, F stale bounded work, F invalid, F text, F reuse
-- and no-action are expected to hold (safety guards a correction must keep).
-- The 414 floor: the viewport is at most 295 (Help.lua 683), so on a page
-- whose text is short the fixed 414+24 content can also leave a blank bottom
-- view; a floor at the viewport height satisfies F.
do
 local Help=assert(Nexus.Help,'SETUP: the Help module')
 local LM=assert(Nexus.LayoutMetrics,'SETUP: LayoutMetrics')
 local L=Nexus.Localization
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local f=assert(NexusHelpWindow,'v29 SETUP: the Help window')
 local content,scroll=assert(f.content,'v29 SETUP: the document frame'),assert(f.scroll,'v29 SETUP: the scroll frame')
 local function Visible(s)
  s=tostring(s or ''):gsub('||','\1'):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
  return (s:gsub('\1','|'))
 end
 local CHAR,ONE=3.5,14
 local function Native(text,width)
  local per=math.max(1,math.floor((tonumber(width) or 585)/CHAR))
  local rows=0
  for line in (Visible(text)..'\n'):gmatch('(.-)\n') do rows=rows+math.max(1,math.ceil(#line/per)) end
  return rows*ONE
 end
 local scale=LM.RuntimeMetrics and LM.RuntimeMetrics() or 1
 local _,ROW=LM.ConservativeText(scale)
 local PAD=ROW+1
 local function Model(text,width) return LM.TextRows(Visible(text),tonumber(width) or 585,scale)*ROW end
 local byId={}
 for _,p in ipairs(Help.Pages) do byId[p.id]=p end
 assert(byId.orbs and byId.faq,'v29 SETUP: the Orbs and Questions pages')
 -- r1 timing isolation (ACTUAL_RED 2026-11-14T14:18:20Z): the frame baseline
 -- went 26 to 31 while H.Advance ran unrelated start-up callbacks (the
 -- unchanged 34 height code has no OnUpdate and makes no frame). That work is
 -- given time to finish, with the Reference hidden, BEFORE the baselines are
 -- taken; every no-growth and no-action assertion below is kept unchanged.
 -- Two attributed checks are added beside the global one: no frame appears
 -- during any Help.Show call (synchronous, so it can only be Help's), and no
 -- frame appears under the Reference window at all.
 Help.Hide();H.Advance(60)
 local before=#DocumentParts(true)
 local framesBefore,acts,sent=#H.frames,#H.actions,#H.sent
 local function HelpFrames()
  local n=0
  for _,fr in ipairs(H.frames) do
   local o,guard=fr,0
   while o and guard<64 do
    if o==f then n=n+1;break end
    local ok,p=pcall(function() return o:GetParent() end)
    o=ok and p or nil;guard=guard+1
   end
  end
  return n
 end
 local helpFramesBefore=HelpFrames()
 -- Every Help.Show in F goes through this counter (other fields: the module).
 local Module,showGrowth=Help,0
 Help=setmetatable({Show=function(id)
  local n=#H.frames;Module.Show(id);showGrowth=showGrowth+(#H.frames-n)
 end},{__index=Module})
 -- The queued-layout stand-in. SetText also keeps C's modelled storage (at
 -- most 8189 bytes stored per FontString), so F text checks the stored
 -- document under the same model; GetText reads what is stored.
 local LIMIT=8189
 local mode,reads,setAt,saved,stand='stable',0,{},{},{}
 for _,fs in ipairs(DocumentParts(true)) do
  saved[#saved+1]={fs=fs,height=rawget(fs,'GetStringHeight'),set=rawget(fs,'SetText')}
  local set=fs.SetText
  rawset(fs,'SetText',function(self,v,...)
   setAt[self]=H.now
   if type(v)=='string' and #v>LIMIT then v=v:sub(1,LIMIT) end
   return set(self,v,...)
  end)
  stand[fs]=function(self)
   reads=reads+1
   if mode=='absent' then return nil end
   if mode=='zero' then return 0 end
   if mode=='error' then error('synthetic GetStringHeight failure') end
   if mode=='nan' then return 0/0 end
   if mode=='huge' then return math.huge end
   if mode=='stale' and setAt[self]==H.now then return ONE end
   return Native(self:GetText() or '',self:GetWidth())
  end
  rawset(fs,'GetStringHeight',stand[fs])
 end
 -- The shown layout: each visible part's height, its settled wrapped text
 -- height and its top in the content (parts stand one under the other).
 local function Layout()
  local rows,y={},0
  for i,fs in ipairs(DocumentParts()) do
   local h=tonumber(fs:GetHeight()) or 0
   rows[i]={h=h,native=Native(fs:GetText() or '',fs:GetWidth()),top=y}
   y=y+h
  end
  return rows
 end
 local function Settled(tag)
  local rows=Layout()
  local viewH=tonumber(scroll:GetHeight()) or 0
  local contentH=tonumber(content:GetHeight()) or 0
  local clipped,gaps,worst=0,0,0
  for i,r in ipairs(rows) do
   if r.h<r.native then clipped=clipped+1 end
   if i<#rows then
    local gap=r.h-r.native
    if gap>worst then worst=gap end
    if gap>PAD then gaps=gaps+1 end
   end
  end
  local last=rows[#rows]
  local textEnd=last and (last.top+last.native) or 0
  local trailing=contentH-textEnd
  expect(#rows>0 and clipped==0 and contentH>=textEnd,
   tag..': no part is shorter than its wrapped text ('..clipped..' of '..#rows..'; content '..contentH..', text ends at '..textEnd..')')
  expect(gaps==0,tag..': no part reserves empty rows inside the document (worst inner gap '..worst..', allowed '..PAD..')')
  expect(contentH<=viewH or trailing<=viewH-ROW,
   tag..': at the scroll bottom the last line is in view (blank after the text '..trailing..', viewport '..viewH..', content '..contentH..')')
  expect(contentH<=math.max(viewH,textEnd+PAD+24),
   tag..': the content is the text plus small padding (content '..contentH..', text '..textEnd..', viewport '..viewH..')')
 end
 local orbsTitle=byId.orbs.title
 if type(L)=='table' and type(byId.orbs.titleKey)=='string' then
  local text,source=L.Text(byId.orbs.titleKey);if type(text)=='string' and source~='unavailable' then orbsTitle=text end
 end
 local orbsDoc=Help.FormatReference(orbsTitle,Help.PageText(byId.orbs))
 -- F stable: every page, once its frames have run.
 mode='stable'
 for _,p in ipairs(Help.Pages) do
  Help.Show(p.id);H.Advance(0.5)
  Settled('F stable '..p.id)
 end
 -- F stale: first read unwrapped; immediate safety, then settlement, then bounded work.
 mode='stale'
 Help.Show('faq');Help.Show('orbs')
 local clippedNow=0
 for _,r in ipairs(Layout()) do if r.h<r.native then clippedNow=clippedNow+1 end end
 expect(clippedNow==0,'F stale: right after showing, before any frame, no part is shorter than its settled wrapped text ('..clippedNow..')')
 H.Advance(0.5)
 Settled('F stale orbs, after the layout settles')
 reads=0
 H.Advance(2)
 local shown=#DocumentParts()
 expect(reads<=2*shown,'F stale: once settled, two seconds of frames do bounded height work ('..reads..' reads for '..shown..' parts)')
 Help.Show('faq');H.Advance(0.5)
 Settled('F stale faq, after a page switch settles')
 Help.Show('orbs');H.Advance(0.5)
 Settled('F stale orbs again')
 -- F invalid: no valid wrapped height at all. 'nomethod' removes the method
 -- itself (an absent GetStringHeight); 'absent' returns no value.
 for _,m in ipairs({'nomethod','absent','zero','error','nan','huge'}) do
  mode=m
  if m=='nomethod' then for fs in pairs(stand) do rawset(fs,'GetStringHeight',false) end end
  Help.Show('faq');Help.Show('orbs');H.Advance(0.5)
  if m=='nomethod' then for fs,fn in pairs(stand) do rawset(fs,'GetStringHeight',fn) end end
  local short,sum=0,0
  for _,fs in ipairs(DocumentParts()) do
   local h=tonumber(fs:GetHeight()) or 0
   sum=sum+h
   if h<Model(fs:GetText(),fs:GetWidth()) then short=short+1 end
  end
  expect(short==0 and (tonumber(content:GetHeight()) or 0)>=sum,
   'F '..m..': with no valid wrapped height every part keeps the conservative model height ('..short..' short; content '
   ..tostring(content:GetHeight())..', parts '..sum..')')
 end
 -- F text: the stored document is unchanged.
 mode='stable'
 Help.Show('faq');Help.Show('orbs');H.Advance(0.5)
 local stored=DocumentText()
 expect(stored==orbsDoc,'F text: the stored Orbs document is the complete formatted page (UTF-8, escaped pipes, order), unchanged by the height work ('
  ..#stored..' of '..#orbsDoc..' bytes)')
 expect(#DocumentParts(true)==before and #H.frames==framesBefore,
  'F reuse: the height work adds no FontString or frame ('..before..' to '..#DocumentParts(true)..' parts, '..framesBefore..' to '..#H.frames..' frames)')
 expect(showGrowth==0,'F reuse: no frame is made while Help shows a page ('..showGrowth..')')
 expect(HelpFrames()==helpFramesBefore,'F reuse: no frame is added under the Reference window ('..helpFramesBefore..' to '..HelpFrames()..')')
 -- Restore every stand-in.
 for _,m in ipairs(saved) do rawset(m.fs,'GetStringHeight',m.height);rawset(m.fs,'SetText',m.set) end
 Help.Hide()
 expect(#H.actions==acts and #H.sent==sent,'F: reading the Reference takes no game action and sends nothing')
 if #misses>0 then
  error('v29 Reference spacing: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0)
 end
end
-- v39 (C): the FAQ appends the eight accepted r3 groups after its original
-- seven (15 groups). Through the real Help.Show and the actual part pool
-- under the existing harness: the shown parts are a prefix of the pool, each
-- anchored under the one before; the joined shown text holds fifteen gold
-- question lines, the first new question right after the original last
-- answer, and the Random Roll answer as the page's last text; every part is
-- inside the scroll child, and at the scroll bottom the last line is in view.
-- The expected questions and the last sentence are restated here (FAQ_DRAFT
-- r3), not read from production. Harness model only; native wrap NOT_RUN.
do
 local Help=assert(Nexus.Help,'v39 SETUP: the Help module')
 local misses={}
 local function expect(v,m) if not v then misses[#misses+1]=m end end
 local OLD_LAST='Close this window (Close or Escape). Reading these pages changed no setting, assignment or Auto.'
 local FIRST_NEW="Why doesn't an Echo I can see count for my Wishlist?"
 local LAST='An assigned Wishlist always uses the normal rules instead.'
 Help.Show('start');Help.Show('faq');H.Advance(0.5)
 local w=assert(NexusHelpWindow,'v39 SETUP: the Help window')
 local pool=w.parts or {w.body}
 local order,hidden,shown=true,nil,{}
 for i,fs in ipairs(pool) do
  if fs:IsShown() then
   if hidden then order=false end
   if i>1 then
    local point,rel,relPoint=fs:GetPoint(1)
    if point~='TOPLEFT' or rel~=pool[i-1] or relPoint~='BOTTOMLEFT' then order=false end
   end
   shown[#shown+1]=fs
  else
   hidden=hidden or i
  end
 end
 expect(order and #shown>0,'v39 FAQ: the shown parts are a prefix of the pool, each under the one before')
 local texts={}
 for i,fs in ipairs(shown) do texts[i]=fs:GetText() or '' end
 local doc=table.concat(texts,'\n')
 local gold=0
 for line in (doc..'\n'):gmatch('(.-)\n') do
  if line:sub(1,10)=='|cffffd100' and line:sub(-2)=='|r' then gold=gold+1 end
 end
 expect(gold==15,'v39 FAQ: fifteen gold question lines are shown ('..gold..')')
 local oldAt=doc:find(OLD_LAST,1,true)
 local newAt=doc:find('|cffffd100'..FIRST_NEW..'|r',1,true)
 expect(oldAt~=nil and newAt~=nil and newAt>oldAt and doc:sub(oldAt+#OLD_LAST,newAt-1)=='\n\n\n',
  'v39 FAQ: the first new question follows the original last answer, one more blank line apart')
 expect(doc:sub(-#LAST)==LAST,'v39 FAQ: the Random Roll answer is the last shown text ("'..doc:sub(-60)..'")')
 local sum=0
 for _,fs in ipairs(shown) do sum=sum+(tonumber(fs:GetHeight()) or 0) end
 local content,view=tonumber(child:GetHeight()) or 0,tonumber(scroll:GetHeight()) or 0
 expect(sum>0 and content>=sum,'v39 FAQ: the scroll child holds every shown part ('..sum..' in '..content..')')
 expect(content<=view or content-sum<=view-17,
  'v39 FAQ: at the scroll bottom the last line is in view (blank after the text '..(content-sum)..', viewport '..view..')')
 Help.Hide()
 if #misses>0 then
  error('v39 FAQ extension: '..#misses..' expectation(s) missed:\n'..table.concat(misses,'\n'),0)
 end
end
print('PASS explicit Help layering, anchors, text dimensions, seven-page navigation and passive reopen')
