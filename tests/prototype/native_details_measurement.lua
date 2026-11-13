-- The expanded Play Details name columns after native acceptance of
-- test.163009: at default scale, with many distinct missing or extra Echoes,
-- STILL NEEDED / EXTRA COPIES showed only the first name, with neither the
-- second name nor "+N more". The face was one no-wrap FontString holding
-- "first\nsecond\n+N more" in a box modelled at three small rows (33 units at
-- default scale). Whether the client drew one line because of no-wrap, its
-- line height or that box is not established, so each line is now its own
-- one-line FontString, measured at its final font and width and stacked by
-- those heights, and the layout reserves that measured stack.
-- D1 default text, five missing and seven extra distinct synthetic names: the
--    first two names, then "+3 more" / "+5 more" (arithmetic checked here),
--    every line whole inside its column and hover, the hovers list every
--    name, the four counts are unchanged and the column is exactly the
--    measured stack (no blank band);
-- D2 a taller face and names holding a line break, under both readings of
--    no-wrap (explicit breaks kept, or only the first line drawn);
-- D3 125% text: the rows use the column's own scaled font object;
-- D4 Show / Hide details with those names: the top holds and the section
--    grows downward, or clamps at the screen edge; Hide details collapses the
--    four counts and every name row (the added rows included); the original
--    difficulty card stays exempt and unchanged;
-- D5 the held physical top across a fit-scale change at font scale 2;
-- D6 fewer names: no suffix for two, "+1 more" for three, the empty text for
--    none, and no stale row from a longer list; the completed view hides them;
-- D7 an offline reload starts collapsed and Show details gives the same face;
-- D8 names far longer than a column, a long "+N more - Show all" row and a
--    long To lock list: every row wraps inside its column and is whole, the
--    three columns are side by side and one measured height, and Hide details
--    gives all of it back.
-- The approved compact panel stands the name columns two across, and three
-- with To lock (every model here has a To lock list), so a column is a half
-- or a third of the block. A row wider than its column wraps inside it: each
-- row is measured at its wrapped height in the column's own width, the rows
-- under it start lower by that, and the layout reserves the tallest column.
-- Independent Spec review of the compact panel (R1): the columns had been
-- narrowed while every row stayed one no-wrap line, so the client shortened a
-- long name and the "+N more - Show all" row. D1 to D7 therefore state a row
-- as one that wraps in its column (it was: one no-wrap line) and a column as
-- its measured wrapped rows (it was: three one-line rows); D8 is new.
-- D9 the headings over the columns: a heading wider than its column wraps
--    inside it and is whole there, the heading row is the tallest heading,
--    the names start under it, a block whose headings all fit keeps the
--    one-line row, and Hide details gives all of it back.
-- Owner decision for the compact Details columns (v8): the approved rule
-- that nothing is cut comes before the one-line heading rule of issue #143.
-- STILL NEEDED, EXTRA COPIES and LOCKED TARGETS wrap inside their columns
-- like the rows under them, each is measured in its column's width, and the
-- row they share is the tallest of them, never under one line. D1 to D8
-- therefore state the heading row from the headings' own need in the text
-- model in use (it was: one line, whatever the heading needed), and every
-- face check also asks each heading whole in its column; D9 is new.
-- Text measurement is the stated model of layout_geometry_support (a fixed
-- line height per model, greedy wrap), extended here with what SetWordWrap
-- (false) means: either explicit line breaks are kept ("newlines") or only
-- the first line is drawn ("first"). A CONTROL shows that under each model
-- the former single string in its three-row box could not show all three
-- lines, so the checks discriminate. A model is not the client's font
-- renderer: native glyphs, line height, clipping and fit are NOT RUN.
-- Categories (view_regression_support): EXPECT is behaviour added by this
-- correction (predicted from source to fail at a9ff2eda: no separate rows,
-- no measured stack; not executed by the author), GUARD already held and must
-- keep holding, SETUP is the fixture.
-- Main-panel visual correction (font height): the heading over each name
-- column is one line of the secondary text at the height the client measures
-- for it (layout.lineSmall: 12, 17 and 15 units in the default, 16 px and
-- 125% models here), where it was the modelled small row (11, 11 and 14),
-- which was lower than its own line in each of these models. D1, D2 and D3
-- stated a column's height with that modelled row; they state it with the
-- measured line now. The name rows' own measured stack is unchanged.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('native_details_measurement')

-- Observation only, installed before the addon loads (the harness keeps
-- none of these): word wrap and the wrap inside a word, vertical
-- justification, a SetAllPoints target, the font object set and the template
-- a FontString was made with.
local function Instrument()
 local RM=G.RegionMethods()
 RM.SetWordWrap=function(self,on) self._wordWrap=on end
 RM.SetNonSpaceWrap=function(self,on) self._nonSpaceWrap=on end
 RM.SetJustifyV=function(self,v) self._justifyV=v end
 RM.SetAllPoints=function(self,rel) self._allPoints=rel or self:GetParent() end
 RM.SetFontObject=function(self,font) self._font=font end
 local make=rawget(RM,'CreateFontString')
 RM.CreateFontString=function(self,name,layer,template,...)
  local r=make(self,name,layer,template,...)
  r._template,r._font=template,template
  return r
 end
end
local function Before(h) F.OrbService(h);Instrument() end

local MODEL,NOWRAP
local TEXT125={name='125% text',char=6.9,line=15,size=15}
local function Lines(text)
 local n=1
 for _ in tostring(text):gmatch('\n') do n=n+1 end
 return n
end
local function Height(self)
 local text=tostring(self.text or '')
 if G.Visible(text)=='' then return 0 end
 if self._wordWrap==false then return (NOWRAP=='first' and 1 or Lines(text))*MODEL.line end
 return G.Rows(text,tonumber(self.width) or 0,MODEL.char)*MODEL.line
end
local function Use(model,noWrap)
 MODEL,NOWRAP=model,noWrap or 'newlines'
 G.UseFont(model)
 G.RegionMethods().GetStringHeight=Height
end

local H=F.Boot(F.Database(),Before)
local P=Nexus.Panel
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true),
  'warning='..tostring(Nexus.OverwriteWarning.IsOpen()==true)},' ')
end

-- Wholly synthetic names, all distinct; one carries a quality breakdown,
-- which the face drops and the hover keeps.
local MISSING={'Cinder Lattice x2 (Rare:x2 Epic:x1)','Hollow Bell','Rime Warden','Quill of Embers','Stoneveil Aegis'}
local EXTRA={'Ashen Tithe','Gloam Lantern','Brine Oath','Sable Thorn','Vesper Coil','Duskmantle Cord','Ironpetal Ward'}
-- Written out here, not taken from the code: two names, then the rest counted.
-- Owner-approved item 7 (#174): the EXTRA COPIES count row also names its
-- button, "+N more - Show all", which opens the complete list.
local NEED_FACE={'Cinder Lattice x2','Hollow Bell','+3 more'}
local EXTRA_FACE={'Ashen Tithe','Gloam Lantern','+5 more - Show all'}
local NEED_HOVER={'Cinder Lattice x2','Rare:x2 Epic:x1','Hollow Bell','Rime Warden','Quill of Embers','Stoneveil Aegis'}

local function Model(tag,o)
 o=o or {}
 return {status='ready',level=40,auto=false,cards={},recommendation='',serverStatus=o.serverStatus,
  progress={wishlistName='Synthetic Details '..tag,total=o.total or 12,owned=o.owned or 5,
   missing=o.missing or MISSING,shed=o.shed or EXTRA,toLock=o.toLock or {'Gravecall Chorus'},
   unknownTomes={'Frostwake Sigil'}}}
end
local function SameList(a,b)
 if #a~=#b then return false end
 for i=1,#a do if a[i]~=b[i] then return false end end
 return true
end
local function ShownText()
 local out={}
 for _,r in ipairs(G.Shown(NexusPanel)) do
  if r.kind=='FontString' then out[#out+1]=V.Plain(r:GetText() or '') end
 end
 return table.concat(out,' | ')
end
local function StatusCard()
 for _,f in ipairs(H.frames) do
  if f._nexusThemeExempt and f:GetParent()==NexusPanel and f.intensityBar then return f end
 end
end
-- The two name columns (STILL NEEDED first, as created), by their rows.
local function Columns()
 local cols={}
 for _,r in ipairs(NexusPanel.regions) do
  if r.kind=='FontString' and type(r._nexusRows)=='table' and r._nexusRows[1]==r then cols[#cols+1]=r end
 end
 return cols[1],cols[2],#cols
end
-- The hover frame laid over a column (Panel's HitFrame: SetAllPoints).
local function Hit(column)
 for _,c in ipairs(NexusPanel.children) do if c._allPoints==column then return c end end
end
local function Face(column)
 local out={}
 for _,row in ipairs(column and column._nexusRows or {}) do
  if row:IsShown() and V.Plain(row:GetText() or '')~='' then out[#out+1]=row end
 end
 return out
end
local function FaceText(column)
 local t={}
 for i,row in ipairs(Face(column)) do t[i]=V.Plain(row:GetText()) end
 return t
end
local function AnyRowShown(column)
 for _,row in ipairs(column and column._nexusRows or {}) do if row:IsShown() then return true end end
 return false
end
-- Every row of the face lies whole inside the column's box, one under the
-- other: the column's own row at its top (justified to the top), each
-- further row at the column's left and as wide as the column, with a box at
-- least its measured height; the box lies inside its layout box and the
-- panel. Each row is a name of its own (no line break in its text) that
-- wraps inside the column: its measured height is that of its wrapped
-- lines, so a row wider than the column is whole, not cut to one line.
-- (Each row was one no-wrap line, which this check stated: `_wordWrap` had to
-- be false. In the narrow compact columns that cut a long row; R1.)
local function Fit(column,box)
 local c=G.Rect(column,NexusPanel)
 local ok=column._justifyV=='TOP'
 local cursor,parts=c[2],{}
 for i,row in ipairs(Face(column)) do
  local h=row:GetStringHeight()
  local top=c[2]
  if i>1 then
   local r=G.Rect(row,NexusPanel)
   top=r[2]
   if r[1]~=c[1] or r[4]-r[2]<h-0.01 or row._justifyV~='TOP' or math.abs((r[3]-r[1])-(c[3]-c[1]))>0.01 then ok=false end
  end
  if top<cursor-0.01 or top+h>c[4]+0.01 or h<=0 or row._wordWrap~=true
   or tostring(row:GetText()):find('[\r\n]') then ok=false end
  cursor=top+h
  parts[#parts+1]=string.format('%s@%.0f+%.0f',V.Plain(row:GetText()),top,h)
 end
 if not (box and c[1]>=box.x-0.01 and c[2]>=box.y-0.01 and c[3]<=box.x+box.w+0.01
  and c[4]<=box.y+box.h+0.01 and c[4]<=NexusPanel:GetHeight()+0.01) then ok=false end
 return ok,table.concat(parts,' ')..' in '..G.Text(c)
end
-- The hover lists every given fragment.
local function HoverHas(column,fragments)
 local hit=Hit(column)
 if not hit then return false,'no hover over the column' end
 local all=table.concat(V.TooltipLines(hit:GetScript('OnEnter'),hit),'\n')
 for _,s in ipairs(fragments) do if not all:find(s,1,true) then return false,s end end
 return true
end
local function Disjoint(layout)
 local names,ok={},true
 for name in pairs(layout.boxes) do names[#names+1]=name end
 table.sort(names)
 for i=1,#names do
  local a=layout.boxes[names[i]]
  if a.x<0 or a.y<0 or a.x+a.w>layout.width or a.y+a.h>layout.height then ok=false end
  for j=i+1,#names do if Nexus.LayoutMetrics.Overlap(a,layout.boxes[names[j]]) then ok=false end end
 end
 return ok
end
-- The former face: the same lines joined by line breaks in one no-wrap
-- string, in the modelled box of three small rows. How many lines it could
-- show in the current text model.
local function OldFaceLines(face,small)
 local drawn=NOWRAP=='first' and 1 or #face
 return math.min(drawn,math.floor(small*3/MODEL.line))
end
local function Open(m)
 P._playDetails=false;P._detailsHold=nil
 if not P.Render(m) then return nil end
 P._playDetails=true
 if not P.Render(m) then return nil end
 return NexusPanel._play
end
-- The headings over the name columns, by their layout box: the reviewed
-- English, written out here, not taken from the code.
local HEADINGS={needed='STILL NEEDED',shed='EXTRA COPIES',toLock='LOCKED TARGETS'}
local function HeadingLabel(text)
 for _,r in ipairs(NexusPanel.regions) do
  if r.kind=='FontString' and r:IsShown() and r:GetText()==text then return r end
 end
end
-- What the heading row needs in the text model in use: the tallest of the
-- laid-out headings, each wrapped in its own column's width, never under one
-- measured line of the secondary text (layout.lineSmall). Also the lines
-- that tallest heading takes. From the written headings and the layout
-- boxes' widths, so it states what the headings need, not what the panel
-- gave them.
local function HeadingNeed(layout)
 local rows=1
 for name,text in pairs(HEADINGS) do
  local box=layout.boxes[name]
  if box then rows=math.max(rows,G.Rows(text,box.w,MODEL.char)) end
 end
 return math.max(layout.lineSmall,rows*MODEL.line),rows
end
-- Every laid-out heading is whole in its column: it shows its heading, it
-- wraps inside the column (it was one no-wrap line, which the client
-- shortened when the column was narrower: the owner's v8 decision), its box
-- is the column's width at the column's top and as tall as the one heading
-- row, and that row holds the lines this heading needs there.
local function Headings(layout)
 local row=tonumber(layout.detailHeadingH)
 if not row then return false,'the layout has no heading row' end
 local ok,parts=true,{}
 for _,name in ipairs({'needed','shed','toLock'}) do
  local box=layout.boxes[name]
  if box then
   local label=HeadingLabel(HEADINGS[name])
   if not label then return false,HEADINGS[name]..' is not shown' end
   local r=G.Rect(label,NexusPanel)
   local need=math.max(1,G.Rows(HEADINGS[name],box.w,MODEL.char))*MODEL.line
   if label._wordWrap~=true or math.abs(r[1]-box.x)>0.01 or math.abs(r[2]-box.y)>0.01
    or math.abs((r[3]-r[1])-box.w)>0.01 or math.abs((r[4]-r[2])-row)>0.01 or need>row+0.01 then ok=false end
   parts[#parts+1]=HEADINGS[name]..' '..G.Text(r)..' needs '..need
  end
 end
 return ok,table.concat(parts,' / ')..' in a heading row of '..tostring(row)
end
-- The face, its fit and its layout for the open Details of the last render.
local function CheckFace(tag,needFace,extraFace)
 local need,shed,n=Columns()
 if not C.expect(n==2,tag..': both name columns have their rows',n) then return end
 local layout=NexusPanel._responsiveLayout
 if not C.setup(layout and layout.boxes.needed and layout.boxes.shed,tag..': fixture: the name columns are laid out') then return end
 -- The headings over the columns, and the names right under their row.
 do
  local whole,detail=Headings(layout)
  local row=tonumber(layout.detailHeadingH) or 0
  local nr,sr=G.Rect(need,NexusPanel),G.Rect(shed,NexusPanel)
  C.expect(whole and math.abs(nr[2]-(layout.boxes.needed.y+row))<0.01 and math.abs(sr[2]-(layout.boxes.shed.y+row))<0.01,
   tag..': every heading is whole in its column, wrapped in its width in the one heading row, and the names start right under that row',detail)
 end
 C.expect(SameList(FaceText(need),needFace),tag..': STILL NEEDED shows '..table.concat(needFace,' / '),
  table.concat(FaceText(need),' / '))
 C.expect(SameList(FaceText(shed),extraFace),tag..': EXTRA COPIES shows '..table.concat(extraFace,' / '),
  table.concat(FaceText(shed),' / '))
 local ok,detail=Fit(need,layout.boxes.needed)
 C.expect(ok,tag..': every STILL NEEDED line is drawn whole in its column, one under the other',detail)
 ok,detail=Fit(shed,layout.boxes.shed)
 C.expect(ok,tag..': every EXTRA COPIES line is drawn whole in its column, one under the other',detail)
 local hn,hs=Hit(need),Hit(shed)
 C.guard(hn and hn:IsShown() and hs and hs:IsShown(),tag..': each column keeps its shown hover over its whole box')
 C.guard(Disjoint(layout),tag..': every layout box is inside the panel and apart from the others')
 if #needFace==3 then
  C.setup(OldFaceLines(needFace,layout.small)<3,
   tag..': CONTROL: in this text model the former single no-wrap string could not show all three lines',
   OldFaceLines(needFace,layout.small)..' of 3 ('..MODEL.name..', '..NOWRAP..')')
 end
 return need,shed,layout
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
do
 local seen,distinct={},0
 for _,list in ipairs({MISSING,EXTRA}) do for _,name in ipairs(list) do if not seen[name] then seen[name]=true;distinct=distinct+1 end end end
 C.setup(#MISSING==5 and #EXTRA==7 and distinct==12,'fixture: five missing and seven extra names, all distinct')
 C.setup('+'..(#MISSING-2)..' more'==NEED_FACE[3] and '+'..(#EXTRA-2)..' more - Show all'==EXTRA_FACE[3],
  'fixture: the expected suffixes are the remaining counts (5-2, 7-2)')
end

-- The approved compact Details lists (design draft "Nexus compact panel"): a
-- name column is its heading's line and, right under it, its names. The
-- heading's row is the draft's 18 pixels where it stands, or its own measured
-- line when that needs more; the names are the draft's three 18-pixel lines,
-- or their measured stack when that needs more. One draft pixel is 284 / 420
-- unit x the layout's font scale. (A column was the heading's line, a label
-- gap of half the layout gap and the stack, which D1 to D3 stated.)
-- The heading row is what the headings need (HeadingNeed above): one
-- measured line while every heading fits its column on one line, which is
-- the condition that stood here (the row was held to layout.lineSmall
-- whatever the headings needed), and the tallest heading's wrapped lines
-- when one wraps. A row of wrapped lines is taller than the draft's 18
-- pixels, so it must then be exactly that need.
local function Column(layout,stack)
 local unit=284/420*(tonumber(layout.scale) or 1)
 local function Drawn(px,units) return units==math.floor(px*unit) or units==math.ceil(px*unit) end
 local heading=tonumber(layout.detailHeadingH)
 if not heading then return false end
 local head=HeadingNeed(layout)
 local names=layout.boxes.needed.h-heading
 return head>=layout.lineSmall and heading>=head and (heading==head or Drawn(18,heading))
  and names>=stack and (names==stack or Drawn(54,names))
end
-- The measured stack of a column in the text model in use: each shown row
-- wrapped in `width` (the rows wrap inside their column), one under the
-- other. The To lock column is one wrapping text: its names in its own
-- width. Tallest: the tallest of the three, which the layout must reserve
-- under the headings (the columns are one height). The widths are the layout
-- boxes' own, and the rows' texts are checked against the expected faces
-- beside every use (CheckFace), so this states what the columns need, not
-- what the panel gave them.
local function Stack(column,width)
 local h=0
 for _,row in ipairs(Face(column)) do h=h+math.max(1,G.Rows(row:GetText() or '',width,MODEL.char))*MODEL.line end
 return h
end
local function LockStack(width)
 local text=NexusPanel.toLockText
 if not (text and text:IsShown() and G.Visible(text:GetText() or '')~='') then return 0 end
 return math.max(1,G.Rows(text:GetText() or '',width,MODEL.char))*MODEL.line
end
local function Tallest(need,shed,layout)
 local b=layout.boxes
 return math.max(Stack(need,b.needed.w),Stack(shed,b.shed.w),b.toLock and LockStack(b.toLock.w) or 0)
end
C.scenario('D1 default text: two names and +3 / +5 more, every line whole; the column is the measured stack',function()
 Use(G.MODELS.default)
 local before=Effects()
 local p=Open(Model('default'))
 if not C.setup(p~=nil and P._playDetails==true,'D1: fixture: Details is open on a build in progress') then return end
 local need,shed,layout=CheckFace('D1',NEED_FACE,EXTRA_FACE)
 if not need then return end
 -- The measured stack: the rows of the tallest column, each wrapped in its
 -- column's width, never under three lines. (It was three one-line rows,
 -- max(3 small rows, 3 measured lines), which this check stated; a row that
 -- is wider than its third of the block now takes the lines it needs.)
 -- "Taller than the modelled rows" is still asked of three measured lines
 -- themselves (3 x the model's line against 3 small rows), as it was, so a
 -- wrapped row cannot stand in for it.
 local stack=Tallest(need,shed,layout)
 -- The heading's row is its measured line (main-panel visual correction:
 -- layout.lineSmall, 12 units in this model; it was the modelled 11-unit
 -- small row, which this check stated). The column: Column above.
 C.expect(layout.lineSmall==math.max(layout.small,MODEL.line) and Column(layout,stack)
  and layout.boxes.shed.h==layout.boxes.needed.h and stack>=3*MODEL.line and 3*MODEL.line>layout.small*3,
  'D1: each column is its heading\'s line and, right under it, the measured rows of the tallest column, taller than the modelled rows, with no extra band',
  layout.boxes.needed.h..' for '..tostring(layout.lineSmall)..' and '..stack)
 local text=ShownText()
 C.expect(not text:find('Rime Warden',1,true) and not text:find('Brine Oath',1,true)
  and not text:find('(Rare',1,true),'D1: the face shows only the first two names, without the quality breakdown',text)
 local ok,miss=HoverHas(need,NEED_HOVER)
 C.guard(ok,'D1: the STILL NEEDED hover lists every missing name and the quality breakdown',miss)
 ok,miss=HoverHas(shed,EXTRA)
 C.guard(ok,'D1: the EXTRA COPIES hover lists every extra name',miss)
 C.guard(V.Plain(p.needed:GetText())=='Still needed  7 copies' and V.Plain(p.extra:GetText())=='Extra copies  7 listed'
  and V.Plain(p.tomes:GetText())=='Missing tomes  1 Echo' and V.Plain(p.locked:GetText())=='Locked targets  1 to lock',
  'D1: the four counts are unchanged',table.concat({V.Plain(p.needed:GetText()),V.Plain(p.extra:GetText())},' | '))
 C.guard(Effects()==before,'D1: rendering and opening Details saves, sends, acts and asks nothing and leaves Auto',Effects())
 P._playDetails=false;P.Render(Model('default'))
end)

C.scenario('D2 a taller face and names with a line break, under both readings of no-wrap',function()
 local missing={'Rime\nWarden (Rare:x1)','Hollow Bell','Quill of Embers','Stoneveil Aegis','Cinder Lattice x2'}
 local shed={'Gloam\r\nLantern','Ashen Tithe','Brine Oath','Sable Thorn','Vesper Coil','Duskmantle Cord','Ironpetal Ward'}
 for _,reading in ipairs({'newlines','first'}) do
  local tag='D2 '..reading
  Use(G.MODELS.px16,reading)
  local before=Effects()
  local p=Open(Model('tall '..reading,{missing=missing,shed=shed}))
  if C.setup(p~=nil,tag..': fixture: Details is open') then
   local need,sh,layout=CheckFace(tag,{'Rime Warden','Hollow Bell','+3 more'},{'Gloam Lantern','Ashen Tithe','+5 more - Show all'})
   if need then
    -- Under a heading as tall as its own 17-unit line (layout.lineSmall;
    -- it was the modelled 11-unit small row, which this check stated).
    -- The rows are 17-unit lines: three at least, and every line a row
    -- needs when it wraps in its column (it was exactly three one-line
    -- rows, 3 x 17, which this check stated).
    local stack=Tallest(need,sh,layout)
    C.expect(layout.lineSmall==MODEL.line and stack>=3*MODEL.line and stack%MODEL.line==0 and Column(layout,stack),
     tag..': the column holds its rows\' measured 17-unit lines under its 17-unit heading',layout.boxes.needed.h..' for '..stack)
    local ok,miss=HoverHas(need,{'Warden','Rare:x1','Hollow Bell','Quill of Embers','Stoneveil Aegis','Cinder Lattice x2'})
    C.guard(ok,tag..': the hover keeps every missing name',miss)
    ok,miss=HoverHas(sh,{'Lantern','Ashen Tithe','Brine Oath','Sable Thorn','Vesper Coil','Duskmantle Cord','Ironpetal Ward'})
    C.guard(ok,tag..': the hover keeps every extra name',miss)
   end
  end
  C.guard(Effects()==before,tag..': nothing is saved, sent or acted on',Effects())
 end
 Use(G.MODELS.default)
 P._playDetails=false;P.Render(Model('default'))
end)

C.scenario('D3 125% text: the same face in the scaled font, every line whole',function()
 Use(TEXT125)
 local p=Open(Model('125'))
 if not C.setup(p~=nil and NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.scale==1.25,
  'D3: fixture: Details is open at font scale 1.25',NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.scale) then return end
 local need,shed,layout=CheckFace('D3',NEED_FACE,EXTRA_FACE)
 if not need then return end
 -- The heading's row is its measured 15-unit line (layout.lineSmall; it was
 -- the modelled 14-unit small row, which this check stated). The rows are
 -- the tallest column's measured 125% lines, never under three of them or
 -- three small rows (it was exactly max(3 small rows, 3 measured lines):
 -- three one-line rows).
 local stack=Tallest(need,shed,layout)
 C.expect(layout.lineSmall==math.max(layout.small,MODEL.line) and stack>=3*MODEL.line
  and Column(layout,math.max(layout.small*3,stack)),
  'D3: each column is its heading\'s line and, right under it, the measured 125% lines of its tallest column',
  layout.boxes.needed.h..' for '..stack)
 -- Approved panel cleanup (secondary floor 11): the main panel's secondary
 -- text, these columns included, is its own 11-unit font object, not the
 -- shared 10-unit small one. What is protected is unchanged: the added rows
 -- use the same font object as their column.
 local small=Nexus.LayoutMetrics.FontObject('secondary')
 local same=need._font==small and shed._font==small
 for _,col in ipairs({need,shed}) do
  for index=2,#col._nexusRows do if col._nexusRows[index]._font~=small then same=false end end
 end
 C.expect(same,'D3: the added rows use the same owned secondary font object as their column',small)
 Use(G.MODELS.default)
 P._playDetails=false;P.Render(Model('default'))
end)

C.scenario('D4 Show / Hide details with many names: held top, downward growth or edge clamp, everything collapses',function()
 Use(G.MODELS.default)
 local ss={tier='Heroic +2',ash='1,240',gain='20',intensity=250,intensityMax=500}
 local m=Model('toggle',{serverStatus=ss})
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 UIParent:SetSize(1366,768)
 local realRefresh=P.Refresh
 P.Refresh=function() return P.Render(m) end
 local function Corner()
  local pt=NexusPanel.points[1]
  if not (pt and #NexusPanel.points==1 and pt[1]=='TOPLEFT' and pt[2]==UIParent and pt[3]=='BOTTOMLEFT') then return nil end
  return pt[4],pt[5]
 end
 local function Track(left,top,scale)
  NexusPanel.GetLeft=function() local x=Corner();return x or left end
  NexusPanel.GetTop=function() local _,y=Corner();return y or top end
  NexusPanel.GetEffectiveScale=function() return scale end
 end
 local ok,err=pcall(function()
  P._playDetails=false;P._detailsHold=nil
  P.Render(m)
  local p=NexusPanel._play
  if not C.setup(type(p)=='table' and p.details:IsShown(),'D4: fixture: Show details is offered') then return end
  local card=StatusCard()
  if not C.setup(card~=nil and card:IsShown(),'D4: fixture: the original difficulty card is shown') then return end
  local cardH=card:GetHeight()
  local closedH=NexusPanel:GetHeight()
  local row=G.Rect(p.details,NexusPanel)
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',900,600)
  Track(900,600,1)
  local quiet=Effects()
  p.details:Click()
  local x,y=Corner()
  C.expect(P._playDetails==true and NexusPanel:GetHeight()>closedH and x==900 and y==600 and P._detailsGrowth
   and P._detailsGrowth.direction=='down','D4: Show details keeps the top and grows downward',
   tostring(x)..','..tostring(y)..' h='..NexusPanel:GetHeight())
  local row2=G.Rect(p.details,NexusPanel)
  C.expect(row2[1]==row[1] and row2[2]==row[2],'D4: the Details button keeps its place',G.Text(row)..' / '..G.Text(row2))
  CheckFace('D4',NEED_FACE,EXTRA_FACE)
  C.guard(card:IsShown() and card._nexusThemeExempt==true and card:GetHeight()==cardH,
   'D4: the difficulty card stays exempt from the theme at its height')
  p.details:Click()
  x,y=Corner()
  C.expect(P._playDetails==false and NexusPanel:GetHeight()==closedH and x==900 and y==600,
   'D4: Hide details keeps the top and gives the whole height back',tostring(x)..','..tostring(y)..' h='..NexusPanel:GetHeight())
  local need,shed=Columns()
  C.expect(not AnyRowShown(need) and not AnyRowShown(shed) and not p.needed:IsShown() and not p.tomes:IsShown()
   and not p.extra:IsShown() and not p.locked:IsShown(),
   'D4: Hide details hides all four counts and every name row, the added rows included')
  local text,leak=ShownText(),nil
  for _,s in ipairs({'Cinder Lattice','Hollow Bell','Ashen Tithe','Gloam Lantern','+3 more','+5 more','STILL NEEDED','EXTRA COPIES'}) do
   if text:find(s,1,true) then leak=s end
  end
  C.expect(leak==nil,'D4: no name, suffix or heading of the section stays shown',leak)
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',900,closedH+10)
  p.details:Click()
  x,y=Corner()
  local openH=NexusPanel:GetHeight()
  C.expect(openH>closedH+10 and x==900 and y==openH and P._detailsGrowth and P._detailsGrowth.direction=='clamped',
   'D4: with no room below, the panel rises only until its bottom meets the edge and reports clamped',
   tostring(y)..' / '..openH)
  CheckFace('D4 clamped',NEED_FACE,EXTRA_FACE)
  p.details:Click()
  C.guard(Effects()==quiet,'D4: Show / Hide details saved nothing (panelX / panelY included), sent or acted on nothing',Effects())
 end)
 P.Refresh=realRefresh
 NexusPanel.GetLeft,NexusPanel.GetTop,NexusPanel.GetEffectiveScale=nil,nil,nil
 P._playDetails=false;P._detailsHold=nil
 NexusPanel:ClearAllPoints();NexusPanel:SetPoint('RIGHT',UIParent,'RIGHT',-40,0)
 UIParent:SetSize(w0,h0)
 C.setup(ok,'D4: fixture: the toggle scenario ran',err)
end)

C.scenario('D5 font scale 2: the held physical top across the fit-scale change, with every line whole',function()
 local ss={tier='Heroic +2',ash='1,240',gain='20',intensity=250,intensityMax=500}
 local m=Model('scale2',{serverStatus=ss})
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local realRefresh=P.Refresh
 P.Refresh=function() return P.Render(m) end
 local function Corner()
  local pt=NexusPanel.points[1]
  if not (pt and #NexusPanel.points==1 and pt[1]=='TOPLEFT' and pt[2]==UIParent and pt[3]=='BOTTOMLEFT') then return nil end
  return pt[4],pt[5]
 end
 local ok,err=pcall(function()
  Use(G.MODELS.double)
  UIParent:SetSize(1366,768)
  NexusPanel:SetScale(1)
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',100,700)
  NexusPanel.GetEffectiveScale=function(self) return self:GetScale() end
  NexusPanel.GetLeft=function() local x=Corner();return x end
  NexusPanel.GetTop=function() local _,y=Corner();return y end
  P._detailsHold=nil
  P._playDetails=true;P.Render(m)
  local openH=NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.height
  P._playDetails=false;P.Render(m)
  local closedH=NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.height
  local p=NexusPanel._play
  if not C.setup(type(p)=='table' and p.details:IsShown() and openH and closedH and openH>closedH+2,
   'D5: fixture: the expanded layout is taller than the collapsed one at font scale 2',tostring(closedH)..' / '..tostring(openH)) then return end
  local uiH=768
  if not (closedH+24<=uiH and uiH<openH+24) then uiH=math.max(480,math.floor((closedH+openH)/2)+24) end
  UIParent:SetSize(1366,uiH)
  P.Render(m)
  if not C.setup(closedH+24<=uiH and uiH<openH+24 and math.abs(NexusPanel:GetScale()-1)<0.001,
   'D5: fixture: the collapsed panel fits at scale 1 and the expanded one needs less',
   closedH..' / '..openH..' in '..uiH..' at '..tostring(NexusPanel:GetScale())) then return end
  local top=uiH-12
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',100,top)
  local quiet=Effects()
  p.details:Click()
  local x,y=Corner()
  local s=NexusPanel:GetScale()
  C.setup(P._playDetails==true and s<0.999,'D5: fixture: Show details fitted the expanded panel below scale 1',s)
  C.expect(x~=nil and math.abs(x*s-100)<0.01 and math.abs(y*s-top)<0.01 and P._detailsGrowth
   and P._detailsGrowth.direction=='down','D5: Show details keeps the physical top while the fit scale drops',
   tostring(x and x*s)..','..tostring(y and y*s)..' at '..s)
  CheckFace('D5',NEED_FACE,EXTRA_FACE)
  p.details:Click()
  x,y=Corner();s=NexusPanel:GetScale()
  C.expect(P._playDetails==false and math.abs(s-1)<0.001 and x~=nil and math.abs(x*s-100)<0.01 and math.abs(y*s-top)<0.01,
   'D5: Hide details keeps the physical top while the scale returns to 1',tostring(x)..','..tostring(y)..' at '..s)
  local need,shed=Columns()
  C.expect(NexusPanel:GetHeight()==closedH and not AnyRowShown(need) and not AnyRowShown(shed),
   'D5: and gives back the whole section, every name row hidden',NexusPanel:GetHeight())
  C.guard(Effects()==quiet,'D5: nothing is saved, sent or acted on',Effects())
 end)
 P.Refresh=realRefresh
 NexusPanel.GetLeft,NexusPanel.GetTop,NexusPanel.GetEffectiveScale=nil,nil,nil
 P._playDetails=false;P._detailsHold=nil
 Use(G.MODELS.default)
 UIParent:SetSize(w0,h0)
 NexusPanel:SetScale(1)
 NexusPanel:ClearAllPoints();NexusPanel:SetPoint('RIGHT',UIParent,'RIGHT',-40,0)
 C.setup(ok,'D5: fixture: the scale scenario ran',err)
end)

C.scenario('D6 fewer names: no suffix for two, +1 more for three, the empty text for none, no stale row; the completed view hides them',function()
 Use(G.MODELS.default)
 local before=Effects()
 local cases={
  {'three',{'Hollow Bell','Rime Warden','Quill of Embers'},{'Ashen Tithe','Gloam Lantern','Brine Oath'},
   {'Hollow Bell','Rime Warden','+1 more'},{'Ashen Tithe','Gloam Lantern','+1 more - Show all'}},
  {'two',{'Hollow Bell','Rime Warden'},{'Ashen Tithe','Gloam Lantern'},
   {'Hollow Bell','Rime Warden'},{'Ashen Tithe','Gloam Lantern'}},
  {'none',{},{'Ashen Tithe'},{'No remaining demand'},{'Ashen Tithe'}},
 }
 -- From the long lists first, so a shorter list must clear the rows it no
 -- longer uses.
 C.setup(Open(Model('long'))~=nil,'D6: fixture: the long lists are shown first')
 for _,case in ipairs(cases) do
  local tag='D6 '..case[1]
  if C.setup(Open(Model('short '..case[1],{missing=case[2],shed=case[3]}))~=nil,tag..': fixture: Details is open') then
   CheckFace(tag,case[4],case[5])
   local text=ShownText()
   C.expect(not text:find('+3 more',1,true) and not text:find('+5 more',1,true) and not text:find('Cinder Lattice',1,true),
    tag..': no row of the longer lists stays shown',text)
  end
 end
 -- A completed build: no progress section, no name row.
 P._playDetails=true
 C.setup(P.Render(Model('complete',{owned=12,toLock={}}))==true,'D6: fixture: a completed build renders')
 local need,shed=Columns()
 C.guard(not AnyRowShown(need) and not AnyRowShown(shed),'D6: the completed view shows no name row')
 P._playDetails=false;P.Render(Model('default'))
 C.guard(Effects()==before,'D6: nothing is saved, sent or acted on',Effects())
end)

C.scenario('D7 an offline reload starts collapsed; Show details gives the same face',function()
 H=F.Reload(Before)
 C.setup(Nexus.StartupStatus().coreReady==true,'D7: fixture: the reloaded addon is ready')
 Nexus.DisableOrdinaryAutomation()
 P=Nexus.Panel
 Use(G.MODELS.default)
 P.Show()
 local m=Model('reload')
 if not C.setup(P.Render(m)==true and NexusPanel._play~=nil,'D7: fixture: the reloaded panel renders') then return end
 local need,shed=Columns()
 C.guard(P._playDetails~=true and not AnyRowShown(need) and not AnyRowShown(shed),
  'D7: Details is memory only: after the reload no name row is shown')
 local before=Effects()
 C.setup(Open(m)~=nil,'D7: fixture: Show details after the reload')
 CheckFace('D7',NEED_FACE,EXTRA_FACE)
 P._playDetails=false;P.Render(m)
 C.guard(Effects()==before,'D7: showing and hiding the names after the reload saves, sends and acts on nothing',Effects())
end)

-- R1 (independent Spec review of the compact panel): the name columns are a
-- third of the block with a To lock list, and every row was one no-wrap
-- line, so a name or a "+N more - Show all" row wider than its column was
-- shortened by the client and only the hover kept it whole.
-- D8: two names several times as wide as a column in each list, twelve
-- extra copies ("+10 more - Show all") and three names to lock, at default
-- text and in the taller 16 px face.
-- EXPECT (each fails at eef1608f, where To lock is a row of its own under
-- two columns, and failed while the rows did not wrap, when each was given
-- one line): every long name and the Show all row take the lines they need
-- in their column; every row lies whole in its column (CheckFace: Fit); the
-- rows and the To lock names may also break inside a word longer than the
-- column; the To lock names are whole in their own column; the three columns
-- are side by side, apart and of one height, the tallest column's wrapped
-- rows, no more and no less; the panel is taller by exactly that and Hide
-- details gives all of it back.
-- GUARD (held before and after): the hovers list every complete name, the
-- Show all button covers its whole row, and nothing is saved, sent or acted
-- on. A text model is not the client's renderer: native wrapping, glyphs and
-- fit are NOT RUN.
C.scenario('D8 names far longer than a column: every row wraps and is whole, in three columns of one measured height',function()
 local missing={'Resonance of the Unbroken Covenant of the Northern Reach x2 (Rare:x2 Epic:x1)',
  'Hollow Bell of the Ashen Choir Eternal','Rime Warden','Quill of Embers'}
 local extra={'Cinderbound Lattice of the Sunken Reliquary Vault','Gloam Lantern of the Seventh Drowned Bell Tower',
  'Brine Oath','Sable Thorn','Vesper Coil','Duskmantle Cord','Ironpetal Ward','Ashen Tithe','Stoneveil Aegis',
  'Hollow Bell','Rime Warden','Quill of Embers'}
 local lock={'Gravecall Chorus of the Thousand Hollow Voices','Ember Vow of the Last Unbroken Lantern','Frostwake Sigil'}
 -- Written out here, not taken from the code: two names, then the rest
 -- counted; the To lock names are one text, a comma between them.
 local needFace={'Resonance of the Unbroken Covenant of the Northern Reach x2','Hollow Bell of the Ashen Choir Eternal','+2 more'}
 local extraFace={'Cinderbound Lattice of the Sunken Reliquary Vault','Gloam Lantern of the Seventh Drowned Bell Tower','+10 more - Show all'}
 local lockFace='Gravecall Chorus of the Thousand Hollow Voices, Ember Vow of the Last Unbroken Lantern, +1 more'
 C.setup(#missing-2==2 and #extra-2==10 and #lock-2==1,'D8: fixture: the expected suffixes are the remaining counts (4-2, 12-2, 3-2)')
 local function Lines(text,width) return math.max(1,G.Rows(text,width,MODEL.char)) end
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16}) do
  local tag='D8 '..tostring(model.name)
  Use(model)
  local before=Effects()
  -- The short lists of D1, open: what the long lists are compared with.
  local shortTail,shortNames
  if C.setup(Open(Model('short '..tostring(model.name)))~=nil and NexusPanel._responsiveLayout
   and NexusPanel._responsiveLayout.boxes.needed~=nil,tag..': fixture: Details is open on the short lists') then
   local sl=NexusPanel._responsiveLayout
   shortTail,shortNames=sl.height-(sl.boxes.needed.y+sl.boxes.needed.h),sl.boxes.needed.h
  end
  local m=Model('long '..tostring(model.name),{missing=missing,shed=extra,toLock=lock})
  P._playDetails=false;P._detailsHold=nil
  C.setup(P.Render(m)==true,tag..': fixture: the long lists render with Details closed')
  local closedH=NexusPanel:GetHeight()
  if C.setup(Open(m)~=nil and shortTail~=nil,tag..': fixture: Details is open on the long lists') then
   local need,shed,layout=CheckFace(tag,needFace,extraFace)
   if need then
    local b=layout.boxes
    C.expect(b.toLock~=nil and b.needed.x==layout.inset and b.needed.x+b.needed.w<=b.shed.x
     and b.shed.x+b.shed.w<=b.toLock.x and b.toLock.x+b.toLock.w==layout.width-layout.inset
     and b.shed.y==b.needed.y and b.toLock.y==b.needed.y and b.shed.h==b.needed.h and b.toLock.h==b.needed.h,
     tag..': Still needed, Extra copies and To lock are three columns side by side between the body\'s insets, apart and of one height',
     b.toLock and (b.needed.x..'+'..b.needed.w..' / '..b.shed.x..'+'..b.shed.w..' / '..b.toLock.x..'+'..b.toLock.w) or 'no To lock column')
    if C.setup(b.toLock~=nil and Lines(needFace[1],b.needed.w)>1 and Lines(needFace[2],b.needed.w)>1
     and Lines(extraFace[1],b.shed.w)>1 and Lines(extraFace[2],b.shed.w)>1 and Lines(extraFace[3],b.shed.w)>1
     and Lines(lockFace,b.toLock.w)>1,
     tag..': fixture: in this text model both long names of each list, the Show all row and the To lock names each need more than one line in their column',
     b.needed.w..' / '..b.shed.w..' / '..tostring(b.toLock and b.toLock.w)) then
     local nr,sr=need._nexusRows,shed._nexusRows
     C.expect(nr[1]:GetStringHeight()>=2*MODEL.line and nr[2]:GetStringHeight()>=2*MODEL.line
      and sr[1]:GetStringHeight()>=2*MODEL.line and sr[2]:GetStringHeight()>=2*MODEL.line and sr[3]:GetStringHeight()>=2*MODEL.line,
      tag..': each long name and the "+10 more - Show all" row takes the lines it needs in its column, more than one',
      nr[1]:GetStringHeight()..' '..nr[2]:GetStringHeight()..' / '..sr[1]:GetStringHeight()..' '..sr[2]:GetStringHeight()..' '..sr[3]:GetStringHeight())
     local lockText=NexusPanel.toLockText
     local inWord=lockText._nonSpaceWrap==true
     for _,col in ipairs({need,shed}) do
      for _,row in ipairs(col._nexusRows) do if row._nonSpaceWrap~=true then inWord=false end end
     end
     C.expect(inWord,tag..': every name row and the To lock names may also break inside a word longer than the column (a long single word is not cut)')
     local t=G.Rect(lockText,NexusPanel)
     C.expect(V.Plain(lockText:GetText() or '')==lockFace and lockText:IsShown() and lockText._wordWrap==true
      and math.abs(t[1]-b.toLock.x)<0.01 and math.abs((t[3]-t[1])-b.toLock.w)<0.01
      and t[2]>=b.toLock.y+layout.detailHeadingH-0.01 and t[4]<=b.toLock.y+b.toLock.h+0.01
      and (t[4]-t[2])+0.01>=LockStack(b.toLock.w) and LockStack(b.toLock.w)>MODEL.line,
      tag..': the To lock names are whole in their own column: wrapped in its width, under its heading, in a box as tall as their lines',
      G.Text(t)..' for '..LockStack(b.toLock.w)..': '..V.Plain(lockText:GetText() or ''))
     local stack=Tallest(need,shed,layout)
     C.expect(stack>3*MODEL.line and Column(layout,stack) and b.needed.h-layout.detailHeadingH==stack,
      tag..': the columns are as tall as the tallest one\'s wrapped rows under the heading, no more and no less',
      b.needed.h..' for a heading of '..tostring(layout.detailHeadingH)..' and '..stack)
     C.expect(layout.height-(b.needed.y+b.needed.h)==shortTail and b.needed.h>shortNames and NexusPanel:GetHeight()==layout.height,
      tag..': the panel is taller by what the columns need: everything under them keeps its distance from them',
      (layout.height-(b.needed.y+b.needed.h))..' / '..tostring(shortTail)..', columns '..b.needed.h..' / '..tostring(shortNames))
    end
    local ok,miss=HoverHas(need,{needFace[1],'Rare:x2 Epic:x1',needFace[2],'Rime Warden','Quill of Embers'})
    C.guard(ok,tag..': the STILL NEEDED hover lists every missing name and the quality breakdown',miss)
    ok,miss=HoverHas(shed,extra)
    C.guard(ok,tag..': the EXTRA COPIES hover lists every extra name',miss)
    local lockHit=NexusPanel.toLockHit
    local lockTip=lockHit and table.concat(V.TooltipLines(lockHit:GetScript('OnEnter'),lockHit),'\n') or ''
    C.guard(lockTip:find(lock[1],1,true)~=nil and lockTip:find(lock[2],1,true)~=nil and lockTip:find(lock[3],1,true)~=nil,
     tag..': the To lock hover lists every name to lock',lockTip)
    -- The Show all button stands on the "+10 more - Show all" row's own
    -- box, corner to corner, so it covers every line of a wrapped row.
    local link,row3=NexusPanel._extraAllBtn,shed._nexusRows[3]
    local covers=false
    if link and link:IsShown() and link:GetNumPoints()==2 then
     local p1,r1,rp1,x1,y1=link:GetPoint(1)
     local p2,r2,rp2,x2,y2=link:GetPoint(2)
     local rr=G.Rect(row3,NexusPanel)
     covers=p1=='TOPLEFT' and r1==row3 and rp1=='TOPLEFT' and x1==0 and y1==0
      and p2=='BOTTOMRIGHT' and r2==row3 and rp2=='BOTTOMRIGHT' and x2==0 and y2==0
      and (rr[4]-rr[2])+0.01>=row3:GetStringHeight()
    end
    C.guard(covers,tag..': the Show all button covers its whole row, at the height that row has')
    P._playDetails=false
    C.setup(P.Render(m)==true,tag..': fixture: Details closed again')
    local need2,shed2=Columns()
    C.expect(NexusPanel:GetHeight()==closedH and not AnyRowShown(need2) and not AnyRowShown(shed2)
     and not NexusPanel.toLockText:IsShown(),
     tag..': Hide details gives the whole section back: the closed height, with no name row and no To lock name shown',
     NexusPanel:GetHeight()..' / '..closedH)
   end
  end
  P._playDetails=false;P._detailsHold=nil
  P.Render(Model('default'))
  C.guard(Effects()==before,tag..': nothing is saved, sent or acted on',Effects())
 end
 Use(G.MODELS.default)
 P._playDetails=false;P.Render(Model('default'))
end)

-- Owner decision for the compact Details columns (v8): the approved rule
-- that nothing is cut comes before the one-line heading rule of issue #143.
-- D9 states a face in which each reviewed English heading is wider than its
-- third of the block and fits its half of a two-column block (9.5 units a
-- character: 12 and 14 characters against the columns' widths, which the
-- fixture checks as its own facts before it asserts anything).
-- EXPECT (each fails at eef1608f, and failed while the heading row was one
-- line whatever a heading needed): with a To lock column every heading
-- takes its two lines, wraps inside its column, may break inside a longer
-- word and stands at the top of one heading row that is exactly those two
-- lines; the names of all three columns start right under that row; what
-- stands under the columns keeps its distance from them; Hide details gives
-- the closed height back; and in a block whose headings fit again they
-- stand in the middle of a one-line row again.
-- GUARD (held before and after): headings that all fit one line keep the
-- one-line heading row; each heading's own hover still gives the complete
-- heading; nothing is saved, sent or acted on. A text model is not the
-- client's renderer: native wrapping, glyphs and fit are NOT RUN.
C.scenario('D9 headings wider than their column wrap inside it and are whole; the heading row is the tallest heading and the names start under it',function()
 -- Stated by this scenario, like TEXT125 above; not a client font.
 local WIDE={name='wide face',char=9.5,line=17,size=12}
 Use(WIDE)
 local before=Effects()
 local m=Model('wide headings')
 P._playDetails=false;P._detailsHold=nil
 C.setup(P.Render(m)==true,'D9: fixture: the panel renders with Details closed')
 local closedH=NexusPanel:GetHeight()
 local tail3
 if C.setup(Open(m)~=nil,'D9: fixture: Details is open with a To lock list, in the wide face') then
  local need,shed,layout=CheckFace('D9',NEED_FACE,EXTRA_FACE)
  if need then
   local b=layout.boxes
   local function Rows(name) return b[name] and G.Rows(HEADINGS[name],b[name].w,MODEL.char) or 0 end
   if C.setup(b.toLock~=nil and Rows('needed')==2 and Rows('shed')==2 and Rows('toLock')==2,
    'D9: fixture: in this face each of the three headings needs two lines in its third of the block',
    Rows('needed')..' / '..Rows('shed')..' / '..Rows('toLock')..' in '..b.needed.w) then
    local head,rows=HeadingNeed(layout)
    C.expect(rows==2 and head==2*MODEL.line and layout.detailHeadingH==head and layout.detailHeadingTall==true,
     'D9: the heading row is exactly the two lines the headings need, no more and no less',tostring(layout.detailHeadingH)..' for '..head)
    local state,why=true,''
    for _,name in ipairs({'needed','shed','toLock'}) do
     local label=HeadingLabel(HEADINGS[name])
     if not (label and label._wordWrap==true and label._nonSpaceWrap==true and label._justifyV=='TOP'
      and label:GetStringHeight()==2*MODEL.line) then
      state=false
      why=why..' '..HEADINGS[name]..': '..tostring(label and label._wordWrap)..'/'..tostring(label and label._nonSpaceWrap)..'/'..tostring(label and label._justifyV)
     end
    end
    C.expect(state,'D9: each heading wraps inside its column, may also break inside a longer word, takes its two lines and stands at the top of the row',why)
    local t=G.Rect(NexusPanel.toLockText,NexusPanel)
    C.expect(math.abs(t[2]-(b.toLock.y+head))<0.01,'D9: the To lock names start right under the heading row, as the other names do',G.Text(t))
    C.expect(Column(layout,Tallest(need,shed,layout)) and b.shed.h==b.needed.h and b.toLock.h==b.needed.h and NexusPanel:GetHeight()==layout.height,
     'D9: each column is that heading row and, right under it, the tallest column\'s measured rows; the three are one height and the panel is the layout\'s',
     b.needed.h..' for a heading row of '..head)
    tail3=layout.height-(b.needed.y+b.needed.h)
   end
   local hover,miss=true,''
   for _,pair in ipairs({{NexusPanel._needLabelHit,HEADINGS.needed},{NexusPanel._shedLabelHit,HEADINGS.shed},{NexusPanel.toLockHit,HEADINGS.toLock}}) do
    local hit=pair[1]
    local lines=hit and table.concat(V.TooltipLines(hit:GetScript('OnEnter'),hit),'\n') or ''
    if not lines:find(pair[2],1,true) then hover=false;miss=miss..' '..pair[2] end
   end
   C.guard(hover,'D9: each heading\'s own hover still gives the complete heading',miss)
   P._playDetails=false
   C.setup(P.Render(m)==true,'D9: fixture: Details closed again')
   C.expect(NexusPanel:GetHeight()==closedH and HeadingLabel(HEADINGS.needed)==nil and HeadingLabel(HEADINGS.shed)==nil
    and HeadingLabel(HEADINGS.toLock)==nil,
    'D9: Hide details gives the whole section back: the closed height, with no heading shown',NexusPanel:GetHeight()..' / '..closedH)
  end
 end
 -- The same face without a To lock list: two columns, each heading on one line.
 local two=Model('wide headings, two columns',{toLock={}})
 if C.setup(Open(two)~=nil,'D9: fixture: Details is open without a To lock list, in the same face') then
  local need,shed,layout=CheckFace('D9 two columns',NEED_FACE,EXTRA_FACE)
  if need then
   local b=layout.boxes
   C.setup(b.toLock==nil and G.Rows(HEADINGS.needed,b.needed.w,MODEL.char)==1 and G.Rows(HEADINGS.shed,b.shed.w,MODEL.char)==1,
    'D9: fixture: without a To lock column each heading fits one line of its half of the block',b.needed.w)
   C.guard(layout.detailHeadingTall~=true and layout.detailHeadingH<2*MODEL.line and Column(layout,Tallest(need,shed,layout)),
    'D9: headings that all fit one line keep the one-line heading row',tostring(layout.detailHeadingH))
   local a,s=HeadingLabel(HEADINGS.needed),HeadingLabel(HEADINGS.shed)
   C.expect(a~=nil and s~=nil and a._justifyV=='MIDDLE' and s._justifyV=='MIDDLE',
    'D9: in the one-line row the headings stand in its middle again, as they did before a heading wrapped',
    tostring(a and a._justifyV)..' / '..tostring(s and s._justifyV))
   C.expect(tail3~=nil and layout.height-(b.needed.y+b.needed.h)==tail3,
    'D9: what stands under the columns keeps its distance from them, under the two-line heading row as under the one-line row',
    tostring(tail3)..' / '..(layout.height-(b.needed.y+b.needed.h)))
  end
 end
 P._playDetails=false;P._detailsHold=nil
 Use(G.MODELS.default)
 P.Render(Model('default'))
 C.guard(Effects()==before,'D9: nothing is saved, sent or acted on',Effects())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Details name rows in stated text models; native glyphs, line height and fit NOT RUN)')
