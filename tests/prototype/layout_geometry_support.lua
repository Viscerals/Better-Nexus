-- Offline geometry for layout fixtures. The harness stores anchors and sizes
-- but has no layout engine and no font renderer. This support resolves the
-- stored anchors of a frame tree into rectangles the way the client does
-- (x to the right and y down from the root's top-left corner; a scroll child
-- moves up by its frame's vertical scroll) and answers text measurement
-- from a stated font model: greedy word wrap of visible characters at a
-- per-character width, a word longer than a line broken across lines.
-- A model is a regression aid; it is not native font measurement, and the
-- native client remains the only proof of pixel fit.
local G={}

-- size: the size NexusFontNormal reports, from which the runtime font scale
-- is read. The 16 px replacement face keeps the 12 px size it reports (a
-- wider, taller face that the font scale does not show); the scaled models
-- report their size.
G.MODELS={
 default={name='default',char=5.5,line=12,size=12},  -- the default face (quickstart_layout_fit)
 px16={name='16px face',char=7.0,line=17,size=12},   -- a 16 px replacement face (quickstart_layout_fit)
 small={name='0.75 scale',char=4.2,line=10,size=9},  -- the smallest supported font scale
 double={name='2.0 scale',char=11.0,line=26,size=24},-- the largest supported font scale
}

local function Visible(text)
 return (tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('||','|'))
end
local function Length(text) return #(text:gsub('[\128-\191]','')) end
G.Visible,G.Length=Visible,Length

function G.Rows(text,width,char)
 text=Visible(text)
 if text=='' then return 0 end
 local perLine=math.max(1,math.floor(width/char))
 local rows=0
 for line in (text..'\n'):gmatch('(.-)\n') do
  rows=rows+1
  local used=0
  for word in line:gmatch('%S+') do
   local n=Length(word)
   local gap=used>0 and 1 or 0
   if used>0 and used+gap+n>perLine then rows=rows+1;used=0;gap=0 end
   while n>perLine do rows=rows+1;n=n-perLine end
   used=used+gap+n
  end
 end
 return rows
end

-- The harness keeps every region method in one table; it is reached through
-- the metatable of any region (no harness file is changed).
local function RegionMethods()
 local index=getmetatable(UIParent).__index
 for i=1,20 do
  local name,value=debug.getupvalue(index,i)
  if name==nil then break end
  if name=='regionMethods' then return value end
 end
 error('harness region methods not found')
end

-- Text measurement and the runtime font size follow the model from now on.
function G.UseFont(model)
 local methods=RegionMethods()
 G.model=model
 methods.GetStringHeight=function(self)
  return G.Rows(self.text,tonumber(self.width) or 0,model.char)*model.line
 end
 methods.GetStringWidth=function(self) return Length(Visible(self.text))*model.char end
 methods.GetTextWidth=function(self) return Length(Visible(self.text))*model.char end
 methods.GetFont=function() return 'Fonts\\FRIZQT__.TTF',model.size,'' end
 -- The harness has no CreateFont, so the addon's own font object, from
 -- which LayoutMetrics reads the runtime font scale, is supplied here.
 if not _G.NexusFontNormal then CreateFrame('Font','NexusFontNormal') end
end

local function Anchor(region)
 local out={}
 for i=1,region:GetNumPoints() do
  local a=region.points[i]
  local point,rel,relPoint,x,y=a[1],a[2],nil,0,0
  if type(rel)=='number' then rel,relPoint,x,y=nil,point,a[2],a[3]
  else
   if type(rel)=='string' then rel=_G[rel] end
   if type(a[3])=='string' then relPoint,x,y=a[3],a[4] or 0,a[5] or 0
   elseif type(a[3])=='number' then relPoint,x,y=point,a[3],a[4] or 0
   else relPoint=point end
  end
  out[i]={point=point,rel=rel or region:GetParent(),relPoint=relPoint,x=x,y=y}
 end
 return out
end

-- {left,top,right,bottom} of region relative to root.
function G.Rect(region,root)
 if region==root then return {0,0,root:GetWidth(),root:GetHeight()} end
 local parent=region:GetParent()
 if parent and parent.scrollChild==region then
  local p=G.Rect(parent,root)
  local top=p[2]-parent:GetVerticalScroll()
  return {p[1],top,p[1]+region:GetWidth(),top+region:GetHeight()}
 end
 local anchors=Anchor(region)
 assert(#anchors>0,'region has no anchor: '..tostring(region:GetName() or region.kind))
 local l,t,r,b,cx,cy
 for _,a in ipairs(anchors) do
  local rr=G.Rect(a.rel,root)
  local ax=a.relPoint:find('LEFT') and rr[1] or a.relPoint:find('RIGHT') and rr[3] or (rr[1]+rr[3])/2
  local ay=a.relPoint:find('TOP') and rr[2] or a.relPoint:find('BOTTOM') and rr[4] or (rr[2]+rr[4])/2
  ax,ay=ax+a.x,ay-a.y
  if a.point:find('LEFT') then l=ax elseif a.point:find('RIGHT') then r=ax else cx=ax end
  if a.point:find('TOP') then t=ay elseif a.point:find('BOTTOM') then b=ay else cy=ay end
 end
 local w,h=region:GetWidth(),region:GetHeight()
 if not l then l=r and r-w or cx-w/2 end
 if not r then r=l+w end
 if not t then t=b and b-h or cy-h/2 end
 if not b then b=t+h end
 return {l,t,r,b}
end

function G.Inside(a,b,slack)
 slack=slack or 0
 return a[1]>=b[1]-slack and a[2]>=b[2]-slack and a[3]<=b[3]+slack and a[4]<=b[4]+slack
end
function G.Apart(a,b)
 return a[3]<=b[1] or b[3]<=a[1] or a[4]<=b[2] or b[4]<=a[2]
end
function G.Text(r) return string.format('[%.0f,%.0f %.0fx%.0f]',r[1],r[2],r[3]-r[1],r[4]-r[2]) end

-- Shown regions and frames below a frame (the harness lists a created
-- FontString or Texture both as a region and as a child).
function G.Shown(root)
 local out,seen={},{}
 local function Walk(f)
  for _,list in ipairs({f.regions or {},f.children or {}}) do
   for _,c in ipairs(list) do
    if c:IsShown() and not seen[c] then
     seen[c]=true;out[#out+1]=c
     if c.kind~='FontString' and c.kind~='Texture' then Walk(c) end
    end
   end
  end
 end
 Walk(root)
 return out
end

return G
