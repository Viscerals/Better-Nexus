-- Wishlist editor menus and selectors: fixed rows keep one line. The menu
-- row labels were anchored left and right inside 22 px rows with no height,
-- so a long Wishlist name with its "Saved Build: ..." and "not a Saved
-- Build" notes wrapped to several lines over the neighbouring rows, and the
-- management header wrapped over its first row. Now each row label is one
-- line at the row height (the client shortens the rest) and the complete
-- label is in the row's tooltip while shortened; the management header wraps
-- to its measured height above the rows. Nothing selects, assigns, removes
-- or sends. (The candidate-assignment buttons use the same helper; the
-- harness models no template button text, so they are not measured here.)
--
-- Real boot, real editor, real menus; synthetic plans (48-byte wide and
-- accented names, the raw name limit) and synthetic Saved Build names. The
-- harness does not size a label from its two anchors, so the test sets
-- that width from the resolved anchors, as the client would. Text widths
-- come from the font models of tests/prototype/layout_geometry_support.lua;
-- native pixel fit is NOT TESTED.
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local function Name(i) return ('W'..i..' '..string.rep('M',30)..' caf\195\169 plan'):sub(1,48) end
local function Echoes(n)
 local rows={}
 for index=1,12 do rows[#rows+1]={spellId=310000+index+n,quality=2,stacks=1,locked=false} end
 return rows
end
local SAVED='Saved '..string.rep('W',26)..' \195\169'
local H=F.Boot(F.Database({mutate=function(db)
 local map={}
 for index=1,12 do
  -- Indexes above the Saved Build range are kept and labelled as not a Saved Build.
  map[index<=5 and index or (index+200)]={slot=100+index,name=Name(index),
   echoes=Echoes(index),assignmentId='assigned:'..index,designTargets={}}
 end
 db.chars[F.NAME].loadoutWishlists=map
end}),function(h)
 local slots={}
 for i=1,5 do slots[i]={name=SAVED..i,verified=true,echoes={{spellId=201172,quality=0,stacks=1}}} end
 h.perks.serverBuildSlots=slots
 h.perks.serverActiveSlot=1
end)
for _=1,40 do H.Advance(.05,.05) end
Nexus.WishlistEditor.Show()
local actions,sent=#H.actions,#H.sent
local frame=NexusEditorFrame or assert(NexusWishlistEditorSwitchButton):GetParent()

local tip=GameTooltip
local saved={SetOwner=tip.SetOwner,AddLine=tip.AddLine,Show=tip.Show,Hide=tip.Hide}
local lines
tip.SetOwner=function() lines={} end
tip.AddLine=function(_,t) if lines then lines[#lines+1]=tostring(t) end end
tip.Show=function() end;tip.Hide=function() end

local function Rows(menu)
 local out={}
 for _,r in ipairs(menu.rows or {}) do if r:IsShown() then out[#out+1]=r end end
 return out
end

local function VerifyMenu(label,menu,header)
 local m=G.model
 local box=G.Rect(menu,frame)
 local rows=Rows(menu)
 check(#rows>0,label..': rows are shown')
 local headerRect
 if header then
  headerRect=G.Rect(header,frame)
  local n=G.Rows(header:GetText(),header:GetWidth(),m.char)
  check(header:GetHeight()>=n*m.line,label..': the header keeps all '..n..' lines')
  check(G.Inside(headerRect,box),label..': the header is inside the menu')
 end
 local shortened=0
 for i,row in ipairs(rows) do
  local r=G.Rect(row,frame)
  check(G.Inside(r,box),label..': row '..i..' '..G.Text(r)..' inside the menu '..G.Text(box))
  if headerRect then check(G.Apart(r,headerRect),label..': row '..i..' is below the header') end
  for j=i+1,#rows do check(G.Apart(r,G.Rect(rows[j],frame)),label..': rows '..i..' and '..j..' do not overlap') end
  local fs=row._label
  local lr=G.Rect(fs,frame)
  fs:SetWidth(lr[3]-lr[1]) -- the width the client takes from the two anchors
  check(fs:GetHeight()<=row:GetHeight() and fs:GetHeight()>=math.min(m.line,row:GetHeight()),
   label..': row '..i..' label is one line at the row height ('..fs:GetHeight()..')')
  check(G.Inside(G.Rect(fs,frame),r),label..': row '..i..' label stays inside its row')
  lines=nil
  local enter=row:GetScript('OnEnter')
  if enter then enter(row) end
  local leave=row:GetScript('OnLeave')
  if leave then leave(row) end
  if G.Length(G.Visible(fs:GetText()))*m.char>fs:GetWidth() then
   shortened=shortened+1
   check(lines and lines[1]==fs:GetText(),label..': shortened row '..i..' shows its complete label in a tooltip')
  else
   check(lines==nil,label..': a row that fits shows no tooltip')
  end
 end
 print('WISHLIST_MENU_LABEL_LAYOUT',label,'menu',G.Text(box),'rows',#rows,'shortened',shortened)
 return shortened
end

for _,m in ipairs({G.MODELS.default,G.MODELS.px16}) do
 G.UseFont(m)
 -- The Wishlist switch list: names, Saved Build notes and the index note.
 NexusWishlistEditorSwitchButton:Click()
 local menu=NexusWishlistEditorSwitchMenu
 check(menu:IsShown(),'the switch list opens')
 local notes=0
 for _,row in ipairs(Rows(menu)) do
  if (row._label:GetText() or ''):find('is not a Saved Build',1,true) then notes=notes+1 end
 end
 check(notes>0,'fixture: a plan stored under an index that is not a Saved Build is listed')
 check(VerifyMenu(m.name..' / switch list',menu)>0,'fixture: long labels are shortened')
 NexusWishlistEditorSwitchButton:Click()
 -- The management list: the measured header above the rows.
 NexusWishlistEditorManageButton:Click()
 menu=NexusWishlistManageMenu
 check(menu:IsShown(),'the management list opens')
 VerifyMenu(m.name..' / management list',menu,menu.header)
 NexusWishlistEditorManageButton:Click()
 -- The Saved Build selector rows.
 local selector
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and tostring(f:GetText() or ''):find('Saved Build: ',1,true) then selector=f end
 end
 if selector then
  selector:Click()
  menu=NexusWishlistEditorLoadoutMenu
  check(menu and menu:IsShown(),'the Saved Build selector opens')
  VerifyMenu(m.name..' / Saved Build selector',menu)
  selector:Click()
 end
end

for k,v in pairs(saved) do tip[k]=v end

-- The 1040 px editor on a 4:3 UI (1024 px wide at scale 1) is scaled to fit;
-- on a wide UI it keeps scale 1.
do
 local w,h=UIParent:GetWidth(),UIParent:GetHeight()
 frame:Hide();UIParent:SetSize(1024,768);Nexus.WishlistEditor.Show()
 local s=frame:GetScale()
 check(frame:IsShown() and s<1 and frame:GetWidth()*s<=1024-24+0.01 and frame:GetHeight()*s<=768,'a 1024 px UI scales the editor to fit: '..s)
 frame:Hide();UIParent:SetSize(1920,1080);Nexus.WishlistEditor.Show()
 check(frame:GetScale()==1,'a 1920 px UI keeps scale 1')
 UIParent:SetSize(w,h)
end
check(#H.actions==actions,'opening and hovering the menus takes no game action')
check(#H.sent==sent,'and sends nothing')
print('PASS wishlist_menu_label_layout checks='..checks..'; native pixel fit NOT TESTED')
