-- Actual renderer geometry and reachability with real model/controller.
-- Only WoW font alignment setters are recorded at the synthetic API boundary.
local H=dofile('tests/prototype/harness.lua')
local create=CreateFrame
CreateFrame=function(...)
 local f=create(...);local font=f.CreateFontString
 f.CreateFontString=function(self,...)
  local r=font(self,...)
  r.SetWordWrap=function(self,v)self.wordWrap=v end
  r.SetJustifyH=function(self,v)self.justifyH=v end
  r.SetJustifyV=function(self,v)self.justifyV=v end
  return r
 end
 return f
end
local entries={}
for i=1,85 do
 local id=290000+i
 H.AddEcho(id,string.format('Echo %03d ',i)..string.rep('Long name ',12),0,1)
 entries[i]={spellId=id,quality=0,stacks=1,locked=i>79}
end
H.Boot()
local backing,settings,account={},{},{}
local store={State=function()return backing end,Settings=function()return settings end}
local A=Nexus.GameAdapter;A.Init({},store)
local model=Nexus.WishlistModel.New()
local c=Nexus.WishlistInternals.Controller.New({model=model,store=store,accountRoot=function()return account end,notify=function()end})
c.Initialize(A);c.BeginNewWishlist();assert(c.LoadPendingEchoes(entries))
local r=Nexus.WishlistInternals.Renderer.New({controller=c,family=model.Family,draftKey=model.DraftKey,echoListTotal=model.EchoListTotal})
local frame=r.Prepare();r.ShowFrame();r.Refresh()
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local footer,save,area
for _,f in ipairs(frame.regions)do
 if f:GetText():find('Rolled copies:',1,true)then footer=f end
end
for _,f in ipairs(frame.children)do
 if f.kind=='Button' and f:GetText()=='Create Wishlist' then save=f end
 if f.scripts.OnMouseWheel and f.width==332 then area=f end
end
assert(footer and save and area,'actual Selected Echoes footer/list/Save control')
check(area:GetHeight()==408,'Selected Echoes reserves 17 rows (408px)')
check(footer:GetWidth()==332 and footer:GetHeight()==28,'footer reserves 332x28')
check(footer.wordWrap==true and footer.justifyH=='LEFT' and footer.justifyV=='TOP','footer explicitly wraps and aligns left/top')
-- Resolve the actual anchors. Harness GetTop/GetBottom are placeholder values.
local function rect(obj)
 local p=obj.points[1];local parent=obj.parent
 local anchor,relative,relativePoint,x,y
 if type(p[2])=='number' then anchor,relative,relativePoint,x,y=p[1],parent,p[1],p[2],p[3]
 else anchor,relative,relativePoint,x,y=p[1],p[2] or parent,p[3],p[4] or 0,p[5] or 0 end
 check(relative==frame,'list/footer/Save share the editor coordinate space')
 local top=relativePoint:find('TOP') and frame:GetHeight()+y or y
 if anchor:find('BOTTOM')then top=top+obj:GetHeight()end
 return top,top-obj:GetHeight(),x
end
local listTop,listBottom,listX=rect(area)
local footerTop,footerBottom,footerX=rect(footer)
local saveTop,saveBottom,saveX=rect(save)
check(listBottom-footerTop==8,'8px between list and footer')
check(footerBottom-saveTop==6,'6px between footer and Save')
check(listX==674 and footerX==674 and saveX==674,'pane widths and left edges align')
local function lines(first,second)
 local text=footer:GetText();local a,b=text:match('^([^\n]+)\n([^\n]+)$')
 check(a==first and b==second,'exact two deliberate summary lines: '..text)
 -- Harness uses a conservative 6px ASCII glyph width. Bullet is one glyph.
 for _,line in ipairs({a,b})do
  local ascii=line:gsub(' \226\128\162 ',' * ')
  check(#ascii*6<=footer:GetWidth(),'summary line fits fixed footer width')
 end
end
lines('Rolled copies: 79/79','Locked targets: 6/6  \226\128\162  85 Echo/quality entries')
H.locked={{spellId=200080,stacks=5},{spellId=200081,stacks=1}}
H.Notify();A.Poll();r.Refresh()
lines('Currently locked: 6/6  \226\128\162  Rolled copies: 79/79','Locked targets: 6/6  \226\128\162  85 Echo/quality entries')
H.locked={};H.Notify();A.Poll();r.Refresh()
local function visible()
 local t={};for _,row in ipairs(area.children)do
  if row.data and row:IsShown()then t[#t+1]=row.data.spellId end
 end;return t
end
check(#visible()==17 and visible()[1]==290001,'first full window and long row names')
for _=1,40 do area.scripts.OnMouseWheel(area,-1)end
local v=visible()
check(#v==17 and v[1]==290069 and v[17]==290085,'wheel clamps at last full window; final entry reachable')
local seen={};c.SetPickOffset(0);r.Refresh()
for _=1,40 do
 for _,id in ipairs(visible())do seen[id]=true end
 area.scripts.OnMouseWheel(area,-1)
end
for i=1,85 do check(seen[290000+i],'every entry reachable '..i)end
-- Oversized restored offset, then search/removal shrink while scrolled.
c.SetPickOffset(999);r.Refresh();v=visible()
check(#v==17 and v[17]==290085,'oversized offset clamps in actual renderer')
c.SetSearch('Echo 085');r.Refresh();v=visible()
check(#v==1 and v[1]==290085,'search shrinks scrolled list and clamps to top')
lines('Rolled copies: 79/79','Locked targets: 6/6  \226\128\162  85 Echo/quality entries')
c.SetSearch('');r.Refresh()
c.BeginNewWishlist();c.LoadPendingEchoes({entries[1]});r.Refresh();v=visible()
check(#v==1 and v[1]==290001,'smaller draft clamps to its first entry')
lines('Rolled copies: 1/79','Locked targets: 0/6  \226\128\162  1 Echo/quality entries')
c.BeginNewWishlist();r.Refresh()
check(#visible()==0,'empty draft has no stranded rows')
lines('Rolled copies: 0/79','Locked targets: 0/6  \226\128\162  0 Echo/quality entries')
print('PASS wishlist_footer_layout checks='..checks)
