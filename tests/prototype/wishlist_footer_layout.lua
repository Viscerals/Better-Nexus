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
 if f:GetText():find('Planned rolled copies:',1,true)then footer=f end
end
-- M3: the Save control is labelled by its effect (Create & assign, else Create
-- unassigned; legacy Create Wishlist). It is created before the Create
-- unassigned alternative beside it, so the first match of the first label
-- present is the apply button.
for _,label in ipairs({'Create & assign','Create unassigned','Create Wishlist'})do
 for _,f in ipairs(frame.children)do
  if f.kind=='Button' and f:GetText()==label then save=f;break end
 end
 if save then break end
end
for _,f in ipairs(frame.children)do
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
lines('Planned rolled copies: 79/79','Locked targets: 6/6  \226\128\162  85 Echo/quality entries')
H.locked={{spellId=200080,stacks=5},{spellId=200081,stacks=1}}
H.Notify();A.Poll();r.Refresh()
-- Two occupied locked records (holding 5 and 1 copies) occupy two of the six
-- slots: "Currently locked" counts records, not the six held copies.
lines('Currently locked: 2/6  \226\128\162  Planned rolled copies: 79/79','Locked targets: 6/6  \226\128\162  85 Echo/quality entries')
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
lines('Planned rolled copies: 79/79','Locked targets: 6/6  \226\128\162  85 Echo/quality entries')
c.SetSearch('');r.Refresh()
c.BeginNewWishlist();c.LoadPendingEchoes({entries[1]});r.Refresh();v=visible()
check(#v==1 and v[1]==290001,'smaller draft clamps to its first entry')
lines('Planned rolled copies: 1/79','Locked targets: 0/6  \226\128\162  1 Echo/quality entries')
c.BeginNewWishlist();r.Refresh()
check(#visible()==0,'empty draft has no stranded rows')
lines('Planned rolled copies: 0/79','Locked targets: 0/6  \226\128\162  0 Echo/quality entries')

-- #47 F2: the Plan alternatives entry stays clear of the save-result line,
-- its hover area, Assign now, Import/Export and its other neighbours. Each
-- rectangle is resolved from the anchors of real production controls by the
-- shared geometry support; native pixels, z-order and click precedence are
-- NOT_RUN. A real controller save through a synthetic host boundary gives a
-- truthful result row in both widths: unassigned with Assign now, and not
-- saved without it. Positive controls run before any disjointness check.
local G=dofile('tests/prototype/layout_geometry_support.lua')
local gmodel,gstate,gaccount,grows=Nexus.WishlistModel.New(),{},{},{}
for i=1,3 do grows[291000+i]={spellId=291000+i,name='Geometry '..i,quality=0,maxStack=5,groupId=0} end
local gcatalog,uploads,uploadOk={rows=grows},0,true
local gc=Nexus.WishlistInternals.Controller.New({model=gmodel,accountRoot=function()return gaccount end,
 store={State=function()return gstate end,Settings=function()return {} end},notify=function()end})
gc.Initialize({Catalog=function()return gcatalog end,WishlistKey=function()return 'geometry' end,
 Slots=function()return {activeSlot=0,maxSlots=5,bySlot={}} end,
 UploadWishlist=function()uploads=uploads+1;return uploadOk end})
local gr=Nexus.WishlistInternals.Renderer.New({controller=gc,family=gmodel.Family,
 draftKey=gmodel.DraftKey,echoListTotal=gmodel.EchoListTotal})
local gframe=gr.Prepare();gr.ShowFrame()
gc.BeginNewWishlist();gc.AddPending(grows[291001]);gr.SetNameText('Geometry plan');gr.Refresh()
local function gchild(pred)
 for _,f in ipairs(gframe.children)do if pred(f)then return f end end
end
local function gnamed(name)return gchild(function(f)return f:GetName()==name end)end
local function glabelled(text)return gchild(function(f)return f.kind=='Button' and f:GetText()==text end)end
local function gresult()
 for _,t in ipairs(gframe.regions)do
  local s=G.Visible(t:GetText())
  if t.kind=='FontString' and t:IsShown() and (s:find('^Saved') or s:find('^Not saved'))then return t,s end
 end
end
local function ghover(text)
 return gchild(function(f)local p=f.points[1]
  return f.kind=='Frame' and p~=nil and p[2]==text and f:GetScript('OnEnter')~=nil end)
end
local function gsave()
 local button=gchild(function(f)return f.kind=='Button' and f:IsVisible() and f:GetText()=='Create unassigned' end)
 check(button~=nil,'a shown Create unassigned control')
 H.popup=nil;button:Click()
 local popup=H.popup;StaticPopup_Hide()
 check(popup~=nil and popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','Create unassigned asks for its own confirmation')
 return popup
end
local whole=G.Rect(gframe,gframe)
local function control(f,label)
 check(f~=nil,label..' exists')
 check(f:IsVisible() and f:GetWidth()>0 and f:GetHeight()>0,label..' is shown with a nonzero size')
 local box=G.Rect(f,gframe)
 check(box[3]>box[1] and box[4]>box[2] and G.Inside(box,whole),label..' resolves inside the editor '..G.Text(box))
 return box
end
local popup=gsave()
check(gc.AcceptApply(popup.data)==true and uploads==1,'one accepted upload through the synthetic host')
gr.Refresh()
local text,line=gresult()
check(line~=nil and line:find('Not assigned',1,true)~=nil,'a truthful unassigned save result is shown: '..tostring(line))
local importBtn,exportBtn=glabelled('Import'),glabelled('Export')
local assignBtn,planBtn=gnamed('NexusWishlistAssignNowButton'),gnamed('NexusFlexiblePlanEntry')
local importBox,exportBox=control(importBtn,'Import'),control(exportBtn,'Export')
local textBox=control(text,'save-result line')
local hoverBox=control(text and ghover(text),'save-result hover area')
local assignBox=control(assignBtn,'Assign now')
local displayBox=control(glabelled('Display Settings'),'Display Settings')
local listBox=control(gchild(function(f)return f.scripts.OnMouseWheel and f.width==332 end),'Selected Echoes list')
local toggleBox=control(gchild(function(f)local p=f.points[1]
 return f.kind=='CheckButton' and p~=nil and type(p[2])=='table' and p[2].kind=='Button' end),
 'locked-slot automation toggle')
local planBox=control(planBtn,'Plan alternatives')
importBtn:Click()
check(H.popup~=nil and H.popup.which=='NEXUS_IMPORT_WISHLIST','Import still opens its paste dialog')
StaticPopup_Hide();exportBtn:Click()
check(H.popup~=nil and H.popup.which=='NEXUS_EXPORT_WISHLIST','Export still opens its copy dialog')
StaticPopup_Hide()
local openChooser,opens=Nexus.WishlistEditor.OpenFlexiblePlanChooser,0
Nexus.WishlistEditor.OpenFlexiblePlanChooser=function()opens=opens+1 end
planBtn:Click();Nexus.WishlistEditor.OpenFlexiblePlanChooser=openChooser
check(opens==1,'Plan alternatives still opens the session chooser')
-- A synthetic Echo Journal route boundary observes the original Assign now.
local journal,routed=Nexus.JournalTab,nil
Nexus.JournalTab={CanOpenBuilds=function()return true end,OpenBuilds=function(v)routed=v end}
assignBtn:Click();Nexus.JournalTab=journal
check(routed==true and not gframe:IsShown() and uploads==1,
 'Assign now still closes the editor for the Echo Journal chooser and uploads nothing')
gr.ShowFrame();gr.Refresh()
check(gresult()==text and G.Visible(text:GetText())==line and assignBtn:IsVisible(),
 'the reopened editor shows the same result and Assign now')
print('OBSERVED Plan alternatives '..G.Text(planBox)..' result '..G.Text(textBox)..' Assign now '..G.Text(assignBox))
local function clear(label,box)
 check(G.Apart(planBox,box),'Plan alternatives '..G.Text(planBox)..' is clear of '..label..' '..G.Text(box))
end
clear('Import',importBox);clear('Export',exportBox);clear('the save-result line',textBox)
clear('the save-result hover area',hoverBox);clear('Assign now',assignBox)
clear('Display Settings',displayBox);clear('the Selected Echoes list',listBox)
clear('the locked-slot automation toggle',toggleBox)
check(G.Apart(textBox,assignBox) and G.Apart(assignBox,importBox) and G.Apart(importBox,exportBox),
 'the result line, Assign now, Import and Export keep separate places')
uploadOk=false;gr.SetNameText('Refused plan');gr.Refresh()
popup=gsave()
check(gc.AcceptApply(popup.data)==false and uploads==2,'the synthetic host refuses the second upload')
gr.Refresh()
text,line=gresult()
check(line~=nil and line:find('^Not saved')~=nil and not assignBtn:IsShown(),
 'a truthful not-saved result is shown without Assign now: '..tostring(line))
check(importBtn:IsVisible() and exportBtn:IsVisible() and planBtn:IsVisible(),
 'Import, Export and Plan alternatives stay shown beside a not-saved result')
textBox=control(text,'full-width save-result line')
hoverBox=control(text and ghover(text),'full-width save-result hover area')
check(textBox[3]>assignBox[1],'the not-saved line takes the width Assign now otherwise shares')
clear('the full-width save-result line',textBox);clear('the full-width save-result hover area',hoverBox)
check(G.Apart(textBox,importBox),'the full-width result line stays clear of Import')
print('PASS wishlist_footer_layout checks='..checks)
