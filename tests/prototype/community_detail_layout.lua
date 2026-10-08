-- Open Build / Community detail layout. Natively the BEST RECORDS heading,
-- the Dummy and Lich King rows and the Details! note rendered below the
-- detail panel and the window: the panel follows the responsive layout
-- (about 410 px high at the default 1040x640 window, 290 px at the 520 px
-- minimum) while that content kept fixed offsets down to y=-512. The detail
-- now has a fixed heading, a measured scrolled body and the action row at
-- the bottom. Also the Share form's source menu (more sources than fit
-- scroll inside it, one line per row with its tooltip) and the Edit dialog
-- (its two actions used to overlap by 4 px; its note keeps every line).
--
-- Real TOC boot, catalog, projections and the real Community window, with
-- synthetic builds only: an 80-byte wide-glyph title (the posting limit), an
-- accented name, a 2000-byte description with explicit line breaks, a
-- 2024-byte unbroken link, 79 ordinary and six locked Echoes (the semantic
-- maximum), DPS records, no Details! addon. The window is checked at several
-- effective UI sizes and font models (tests/prototype/layout_geometry_support).
-- Geometry and text fit are offline models; native pixel fit is NOT TESTED.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local WIDE=string.rep('W',40)..string.rep('M',40)
local ACCENT='Valentin\195\169'
local parts={}
for i=1,40 do
 parts[#parts+1]=(i%5==0 and '\n' or '')..'Step '..i..': keep caf\195\169 uptime, then rotate the opener.'
end
local PARA=table.concat(parts,' ')
PARA=(PARA..' '..string.rep('end ',500)):sub(1,2000)
local LINK='https://example.invalid/'..string.rep('x',2000)
assert(#WIDE==80 and #PARA==2000 and #LINK==2024,'fixture text sizes')

local fx=L.New({players={
 {name='PrototypeTester',class='MAGE',isLocal=true,variant=1,ordinary=79,locked=6,dps={dummy=61000,lk=62000},title=WIDE},
 {name=ACCENT,class='MAGE',variant=2,ordinary=79,locked=6,dps={dummy=50000},title=WIDE},
 {name='Short',class='PRIEST',variant=3,ordinary=4,locked=0,title='Short build'},
}})
local db=F.Database({version=2})
fx:Install(db)
local own,remote,short=fx.players[1],fx.players[2],fx.players[3]
for _,p in ipairs({own,remote}) do
 local b=db.communityBuilds[p.buildId]
 b.description,b.link=PARA,LINK
end
-- Share sources: five Saved Builds and twelve Wishlists with long names,
-- more than the source menu's 300 px show at once.
local SOURCE='Source '..string.rep('W',30)..' caf\195\169 plan'
local H=F.Boot(db,function(h)
 h.playerLevel=60
 local slots={}
 for i=1,5 do slots[i]={name=(SOURCE..' '..i):sub(1,48),verified=true,echoes={{spellId=200001+i,quality=0,stacks=1}}} end
 for i=1,12 do slots[100+i]={name=(SOURCE..' W'..i):sub(1,48),verified=false,echoes={{spellId=200010+i,quality=1,stacks=1}}} end
 h.perks.serverBuildSlots=slots
end)
for _=1,400 do H.Advance(.05,.05) end
check(not (Nexus.DpsCapture.IsDetailsAvailable and Nexus.DpsCapture.IsDetailsAvailable()),'fixture: Details! is not installed')

local actionsBefore=#H.actions
local frame,p

local function Open(id)
 Nexus.CommunityBuilds.ShowBuild(id)
 for _=1,4000 do
  H.Advance(.05,.05)
  frame=NexusCommunityBuildsFrame;p=frame and frame._detailPanel
  if p and p:IsShown() and p._nexusShownId==id then break end
 end
 check(p and p:IsShown() and p._nexusShownId==id,'the detail of '..id..' is shown')
 -- UIPanelCloseButton's own size (the harness gives every frame 100x20).
 p.closeBtn:SetSize(32,32)
 return p
end

local function Settle()
 Nexus.CommunityBuilds.Refresh()
 for _=1,20 do H.Advance(.05,.05) end
end

local function FullText(fs) return G.Visible(fs:GetText()) end

-- Every check of one shown detail in one viewport and font model.
local function Verify(label,expect)
 local m=G.model
 local root=frame
 local panel=G.Rect(p,root)
 local window={0,0,frame:GetWidth(),frame:GetHeight()}
 check(G.Inside(panel,window),label..': the detail panel '..G.Text(panel)..' is inside the window '..G.Text(window))
 -- Heading: one line each, clear of the icon and the close button, and the
 -- complete title and byline in the header tooltip when shortened.
 local close,title,author=G.Rect(p.closeBtn,root),G.Rect(p.title,root),G.Rect(p.author,root)
 local icon=G.Rect(p.classIcon,root)
 check(G.Inside(title,panel) and G.Inside(author,panel),label..': title and byline inside the panel')
 check(G.Apart(title,close) and G.Apart(author,close) and G.Apart(title,icon) and G.Apart(author,icon),
  label..': title and byline clear of the class icon and close button')
 check(p.title:GetHeight()>=m.line and p.author:GetHeight()>=m.line,label..': title and byline each hold a full line ('..p.title:GetHeight()..', '..p.author:GetHeight()..')')
 -- Actions: inside, apart, below the scrolled body, each wide enough for its label.
 local view=G.Rect(p.bodyScroll,root)
 check(G.Inside(view,panel),label..': the scrolled body '..G.Text(view)..' is inside the panel '..G.Text(panel))
 check(view[2]>=author[4] and view[2]>=icon[4],label..': the body starts below the heading')
 local buttons={}
 for _,b in ipairs({p.lockBtn,p.retryShareBtn,p.editBtn,p.deleteBtn}) do
  if b:IsShown() then
   local r=G.Rect(b,root)
   check(G.Inside(r,panel),label..': action "'..b:GetText()..'" '..G.Text(r)..' inside the panel')
   check(r[2]>=view[4],label..': action "'..b:GetText()..'" below the scrolled body')
   check(b:GetWidth()>=G.Length(G.Visible(b:GetText()))*m.char+20,label..': action "'..b:GetText()..'" is wide enough for its label')
   check(b:GetHeight()>=m.line+4,label..': action "'..b:GetText()..'" is tall enough for its label')
   for _,o in ipairs(buttons) do check(G.Apart(r,o[2]),label..': actions "'..b:GetText()..'" and "'..o[1]..'" do not overlap') end
   buttons[#buttons+1]={b:GetText(),r}
  end
 end
 for _,want in ipairs(expect.buttons) do
  local found=false
  for _,b in ipairs(buttons) do if b[1]==want then found=true end end
  check(found,label..': action "'..want..'" is shown')
 end
 -- Body: every shown element inside the body width and height, apart from
 -- each other, every wrapped text as tall as its lines.
 local body=p.body
 check(body:GetWidth()<=view[3]-view[1],label..': the body is no wider than its viewport')
 local scroll=p.bodyScroll
 scroll:SetVerticalScroll(0)
 local top=G.Rect(body,root)
 local items={}
 for _,r in ipairs(G.Shown(body)) do
  local rr=G.Rect(r,root)
  local rel={rr[1]-top[1],rr[2]-top[2],rr[3]-top[1],rr[4]-top[2]}
  check(rel[1]>=0 and rel[2]>=0 and rel[3]<=body:GetWidth()+0.5 and rel[4]<=body:GetHeight()+0.5,
   label..': body element '..tostring(r.kind)..' '..G.Text(rel)..' inside the body '..body:GetWidth()..'x'..body:GetHeight())
  if r.kind=='FontString' then
   local rows=G.Rows(r:GetText(),r:GetWidth(),m.char)
   check(r:GetHeight()>=rows*m.line,label..': text "'..FullText(r):sub(1,24)..'" keeps all '..rows..' lines ('..r:GetHeight()..' px)')
  elseif r.kind=='Button' then
   check(r:GetWidth()>=G.Length(G.Visible(r:GetText()))*m.char+20,label..': body button "'..r:GetText()..'" is wide enough for its label')
  end
  items[#items+1]={r,rel}
 end
 for i=1,#items do for j=i+1,#items do
  local a,b=items[i],items[j]
  check(G.Apart(a[2],b[2]),label..': body elements '..tostring(a[1].kind)..' '..G.Text(a[2])..' and '..tostring(b[1].kind)..' '..G.Text(b[2])..' do not overlap')
 end end
 local icons=0
 for _,ic in ipairs(p.echoIcons) do if ic:IsShown() then icons=icons+1 end end
 check(icons==expect.icons,label..': all '..expect.icons..' Echo icons are shown ('..icons..')')
 -- Scroll range: a readable viewport, and the last line is reachable and
 -- lies inside it.
 check(view[4]-view[2]>=3*m.line,label..': the scrolled body shows at least three lines ('..(view[4]-view[2])..' px)')
 local range=math.max(0,body:GetHeight()-(view[4]-view[2]))
 scroll:SetVerticalScroll(range)
 local last=expect.last
 local lr=G.Rect(last,root)
 check(lr[2]>=view[2]-0.5 and lr[4]<=view[4]+0.5,label..': at the end of the scroll range the last line '..G.Text(lr)..' is inside the viewport '..G.Text(view))
 check(G.Inside(lr,panel) and G.Inside(lr,window),label..': the last line is inside the panel and the window')
 scroll:SetVerticalScroll(0)
 print('COMMUNITY_DETAIL_LAYOUT',label,'panel',G.Text(panel),'view',G.Text(view),'content',body:GetHeight(),'range',range)
end

local VIEWPORTS={
 {name='1920x1080 effective 1366x768',w=1366,h=768},
 {name='4:3 effective 1024x768',w=1024,h=768},
 {name='1040x680',w=1040,h=680},
 {name='800x600',w=800,h=600},
 {name='below the 760x520 minimum',w=700,h=500},
}
local MODELS={G.MODELS.default,G.MODELS.px16,G.MODELS.small,G.MODELS.double}

-- Opening the window runs the existing import of the synthetic Saved Builds
-- (it adds their catalog and evidence rows over several openings). The data
-- this view renders is compared: the three builds' records and everything
-- else in the bundle except that import's own maps and counter.
local IMPORT={communityBuilds=true,loadoutEvidence=true,transactionGeneration=true}
local function Rendered()
 local bundle,out=NexusDB.authorityBundle,{}
 for k,v in pairs(bundle) do if not IMPORT[k] then out[k]=v end end
 for _,q in ipairs(fx.players) do
  out['build:'..q.buildId]=bundle.communityBuilds and bundle.communityBuilds[q.buildId] or false
 end
 return F.Serialize(out)
end
local catalogBefore=Rendered()
for _,q in ipairs(fx.players) do
 check(type(NexusDB.authorityBundle.communityBuilds)=='table' and NexusDB.authorityBundle.communityBuilds[q.buildId]~=nil,
  'fixture: the compared record of '..q.buildId..' is in the saved bundle')
end

local function Expect(id)
 if id==own.buildId then
  return {buttons={'Copy into Editor','Edit Build','Stop Sharing'},icons=79,last=p.detailsNote}
 elseif id==remote.buildId then
  return {buttons={'Copy into Editor'},icons=79,last=p.detailsNote}
 end
 return {buttons={'Copy into Editor'},icons=4,last=p.detailsNote}
end

-- 1. Every viewport and font model, own and remote builds, and a short build.
for _,m in ipairs(MODELS) do
 G.UseFont(m)
 for _,v in ipairs(VIEWPORTS) do
  UIParent:SetSize(v.w,v.h)
  for _,id in ipairs({own.buildId,remote.buildId,short.buildId}) do
   Open(id);Settle()
   check(p.detailsNote:IsShown(),'fixture: the Details! note is shown')
   Verify(m.name..' / '..v.name..' / '..id,Expect(id))
  end
 end
end

-- 2. A change while the window is open: the layout follows the new size and
-- font without reopening, and the scroll position stays inside the range.
G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768)
Open(own.buildId);Settle()
local tall=p:GetHeight()
p.bodyScroll:SetVerticalScroll(10000)
UIParent:SetSize(800,500);Settle()
check(p:GetHeight()<tall,'a smaller UI shortens the open panel ('..tall..' -> '..p:GetHeight()..')')
Verify('open, then 800x500',Expect(own.buildId))
G.UseFont(G.MODELS.double);Settle()
Verify('open, then font scale 2',Expect(own.buildId))
G.UseFont(G.MODELS.default);UIParent:SetSize(1366,768);Settle()

-- 3. Full text: the description, link and records are complete in their
-- widgets; a shortened title and byline are complete in the header tooltip.
do
 Open(remote.buildId);Settle()
 check(FullText(p.desc):find(G.Visible(PARA):sub(1,200),1,true) and FullText(p.desc):sub(-40)==G.Visible(PARA):sub(-40),
  'the whole 2000-byte description is in the body')
 check(p.linkBox:_NexusRawText()==LINK,'the whole link is in its copy field')
 check(FullText(p.dummyRecord):find('Training Dummy',1,true) and FullText(p.lkRecord):find('Lich King',1,true),'both record rows are filled')
 local tip=GameTooltip
 local saved={SetOwner=tip.SetOwner,AddLine=tip.AddLine,Show=tip.Show,Hide=tip.Hide}
 local lines
 tip.SetOwner=function() lines={} end
 tip.AddLine=function(_,t) lines[#lines+1]=tostring(t) end
 tip.Show=function() end;tip.Hide=function() end
 lines=nil
 p.headerHit:GetScript('OnEnter')(p.headerHit)
 check(lines and lines[1]==WIDE and lines[2]==p.author:GetText() and lines[2]:find(ACCENT,1,true),
  'the header tooltip carries the full title and byline: '..table.concat(lines or {},' / '))
 Open(short.buildId);Settle()
 lines=nil
 p.headerHit:GetScript('OnEnter')(p.headerHit)
 check(lines==nil,'a title that fits shows no header tooltip')
 for k,v in pairs(saved) do tip[k]=v end
end

-- 4. Share form and Edit dialog (16 px face). The source list scrolls inside
-- its menu with one line per row; the Edit actions are apart and its note fits.
do
 G.UseFont(G.MODELS.px16);UIParent:SetSize(1366,768)
 Open(own.buildId);Settle()
 Nexus.CommunityBuilds.ShowPostBuild()
 local post=assert(NexusPostPopup,'the Share form opens')
 post._postWishlistBtn:Click()
 local menu
 for _,c in ipairs(post.children) do if c._list and c:IsShown() then menu=c end end
 assert(menu,'the source menu opens')
 local rows={}
 for _,b in ipairs(menu._list.children) do if b.kind=='Button' and b:IsShown() then rows[#rows+1]=b end end
 check(#rows>=14,'fixture: more sources than the menu shows at once: '..#rows)
 check(menu:GetHeight()<=300 and menu._list:GetHeight()>=12+#rows*22,'the menu stays 300 px or less; its list holds every row')
 menu:SetWidth(334)
 local box=G.Rect(menu,post)
 local function LastInside()
  local r=G.Rect(rows[#rows],post)
  return r[2]>=box[2]-0.5 and r[4]<=box[4]+0.5
 end
 check(not LastInside(),'the last source starts below the visible menu')
 for _=1,#rows do menu._scroll:GetScript('OnMouseWheel')(menu._scroll,-1) end
 check(LastInside(),'scrolling the menu brings the last source inside it')
 menu._scroll:GetScript('OnMouseWheel')(menu._scroll,1000)
 check(menu._scroll:GetVerticalScroll()==0,'and back to the first')
 local tip=GameTooltip
 local saved={SetOwner=tip.SetOwner,AddLine=tip.AddLine,Show=tip.Show,Hide=tip.Hide}
 local lines
 tip.SetOwner=function() lines={} end;tip.AddLine=function(_,t) lines[#lines+1]=tostring(t) end
 tip.Show=function() end;tip.Hide=function() end
 for i,b in ipairs(rows) do
  local fs=b.regions[1]
  fs:SetWidth(334-12-12) -- the width its two anchors give it
  check(fs:GetHeight()<=b:GetHeight(),'source row '..i..' keeps one line')
  lines=nil;b:GetScript('OnEnter')(b);b:GetScript('OnLeave')(b)
  if G.Length(G.Visible(fs:GetText()))*G.model.char>fs:GetWidth() then
   check(lines and lines[1]==fs:GetText(),'shortened source row '..i..' is complete in its tooltip')
  end
 end
 for k,v in pairs(saved) do tip[k]=v end
 menu:Hide();post:Hide()
 -- The Edit dialog of the owner's build.
 Open(own.buildId);Settle()
 p.editBtn:Click()
 local edit=assert(NexusEditPopup,'the Edit dialog opens')
 local echo,save,note
 for _,c in ipairs(edit.children) do
  if c.kind=='Button' and c:GetText()=='Use Active Wishlist Echoes' then echo=c end
  if c.kind=='Button' and c:GetText()=='Save Details' then save=c end
 end
 note=edit._editLockText
 local er,sr=G.Rect(echo,edit),G.Rect(save,edit)
 check(G.Apart(er,sr),'the Edit actions do not overlap '..G.Text(er)..' '..G.Text(sr))
 for _,b in ipairs({echo,save}) do
  check(b:GetWidth()>=G.Length(b:GetText())*G.model.char+12,'"'..b:GetText()..'" fits its button')
 end
 local n=G.Rows(note:GetText(),note:GetWidth(),G.model.char)
 local nr=G.Rect(note,edit)
 check(note:GetHeight()>=n*G.model.line and nr[4]<=er[2],'the Edit note keeps all '..n..' lines above the actions')
 Nexus.CommunityBuilds.ToggleEditPopup(own.buildId)
 check(not edit:IsShown(),'the Edit dialog closes without saving')
 G.UseFont(G.MODELS.default)
end

-- 5. Display only: no data change or game action from any of this.
check(Rendered()==catalogBefore,'the rendered builds, DPS and other saved data are unchanged by rendering')
check(#H.actions==actionsBefore,'no game action')
Nexus.CommunityBuilds.Hide()
print('PASS community_detail_layout checks='..checks..'; native pixel fit NOT TESTED')
