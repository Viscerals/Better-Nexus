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
-- D7 an offline reload starts collapsed and Show details gives the same face.
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
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('native_details_measurement')

-- Observation only, installed before the addon loads (the harness keeps
-- none of these): no-wrap, vertical justification, a SetAllPoints target,
-- the font object set and the template a FontString was made with.
local function Instrument()
 local RM=G.RegionMethods()
 RM.SetWordWrap=function(self,on) self._wordWrap=on end
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
-- Every line of the face lies whole inside the column's box, one under the
-- other: the column's own line at its top (justified to the top), each
-- further row at the column's left with a box at least its measured line;
-- each is one no-wrap line; the box lies inside its layout box and the panel.
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
   if r[1]~=c[1] or r[4]-r[2]<h-0.01 or row._justifyV~='TOP' then ok=false end
  end
  if top<cursor-0.01 or top+h>c[4]+0.01 or h<=0 or row._wordWrap~=false
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
-- The face, its fit and its layout for the open Details of the last render.
local function CheckFace(tag,needFace,extraFace)
 local need,shed,n=Columns()
 if not C.expect(n==2,tag..': both name columns have their one-line rows',n) then return end
 local layout=NexusPanel._responsiveLayout
 if not C.setup(layout and layout.boxes.needed and layout.boxes.shed,tag..': fixture: the name columns are laid out') then return end
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

C.scenario('D1 default text: two names and +3 / +5 more, every line whole; the column is the measured stack',function()
 Use(G.MODELS.default)
 local before=Effects()
 local p=Open(Model('default'))
 if not C.setup(p~=nil and P._playDetails==true,'D1: fixture: Details is open on a build in progress') then return end
 local need,shed,layout=CheckFace('D1',NEED_FACE,EXTRA_FACE)
 if not need then return end
 local labelGap=math.max(3,math.floor(layout.gap/2))
 local stack=math.max(layout.small*3,3*MODEL.line)
 C.expect(layout.boxes.needed.h==layout.small+labelGap+stack and layout.boxes.shed.h==layout.boxes.needed.h
  and stack>layout.small*3,
  'D1: each column is its heading plus the three measured lines, taller than the modelled rows, with no extra band',
  layout.boxes.needed.h..' = '..layout.small..'+'..labelGap..'+'..stack)
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
    local labelGap=math.max(3,math.floor(layout.gap/2))
    C.expect(layout.boxes.needed.h==layout.small+labelGap+3*MODEL.line,
     tag..': the column holds three 17-unit lines',layout.boxes.needed.h)
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
 local labelGap=math.max(3,math.floor(layout.gap/2))
 C.expect(layout.boxes.needed.h==layout.small+labelGap+math.max(layout.small*3,3*MODEL.line),
  'D3: each column is its heading plus the three measured 125% lines',layout.boxes.needed.h)
 local small=Nexus.LayoutMetrics.FontObject('small')
 local same=need._font==small and shed._font==small
 for _,col in ipairs({need,shed}) do
  for index=2,#col._nexusRows do if col._nexusRows[index]._font~=small then same=false end end
 end
 C.expect(same,'D3: the added rows use the same owned small font object as their column',small)
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

Nexus.DisableOrdinaryAutomation()
C.finish('(Details name rows in stated text models; native glyphs, line height and fit NOT RUN)')
