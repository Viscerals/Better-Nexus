-- The "Automation Wishlist" selector tooltip stays readable while the Wishlist
-- picker is open (native C3 finding on 27aaeec: the open picker covered the
-- lower half of the selector tooltip, its warning text).
--
-- MODELED GEOMETRY, NOT NATIVE PIXELS. This test drives the real Journal
-- selector, picker, row, gear and Unassign handlers, but every rectangle below
-- comes from a small model defined in this file:
--   * screen: UIParent is 1920 x 1080 UI units, origin bottom-left;
--   * frame rectangles are resolved from the SetPoint anchors and sizes that
--     the real code sets; the picker, the association panel and GameTooltip
--     are clamped to the screen (the picker and panel call
--     SetClampedToScreen(true); native tooltips are clamped);
--   * GameTooltip: SetOwner(owner, "ANCHOR_TOP") puts the tooltip BOTTOM at
--     the owner TOP; "ANCHOR_RIGHT" (3.3.5) puts the tooltip BOTTOMLEFT at the
--     owner TOPRIGHT; "ANCHOR_NONE" keeps any earlier points (conservative:
--     the code must clear them) and uses the explicit SetPoint calls. Its size
--     is computed by Show() from the current lines with a word-wrap model (38
--     characters per wrapped line, 17 units a line, 10 units of padding, 268
--     units wide when a line wraps), calibrated roughly against the native C3
--     screenshot; before Show() GetWidth answers the previous tooltip's size;
--   * scale: every modeled frame has the effective scale UI_SCALE, and
--     GameTooltip has UI_SCALE * TIP_SCALE (both 1 unless a case sets them).
--     GameTooltip sizes and offsets are in its own units, TIP_SCALE times
--     larger in UIParent units. UIParent stays 1920 x 1080 of its own units;
--   * deferred layout: in one case the picker's GetLeft/GetRight/GetTop/
--     GetBottom/GetCenter answer nil after SetPoint until the next rendered
--     frame (render()), as for a frame whose layout is not yet resolved;
--   * draw order: the higher strata draws above; in the same strata the
--     higher frame level draws above. GameTooltip is TOOLTIP strata, level 1;
--     the picker is TOOLTIP strata, level 50, so the picker draws above it.
-- Invariants: while the picker is shown, the selector tooltip rectangle does
-- not intersect the picker rectangle and lies on the screen. The pre-existing
-- row, gear and Unassign tooltips (native PASS) are checked on their text area
-- (the rectangle inset by the 10-unit tooltip padding), because ANCHOR_RIGHT on
-- a row that ends 6 units inside the picker overlaps only the tooltip border.
-- Native pixel visibility of the corrected tooltip is NOT established here.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_journal_picker.lua')
dofile=originalDofile
assert(H)
local T=dofile('tests/prototype/startup_support.lua')
local A=Nexus.GameAdapter
-- A failure reports the line that called check, not this line.
local checks=0;local function check(v,m) if not v then error(m,2) end;checks=checks+1 end

------------------------------------------------------------------------
-- Geometry model
------------------------------------------------------------------------
local SW,SH=1920,1080
local PAD,CHARS,LINE_H,WRAP_W=10,38,17,268
local UI_SCALE,TIP_SCALE=1,1
local function setScales(ui,tip) UI_SCALE,TIP_SCALE=ui,tip end
local deferLayout,layoutPending=false,false
local function render() layoutPending=false end
local regionMethods
do
 local index=getmetatable(UIParent).__index
 for i=1,20 do
  local name,value=debug.getupvalue(index,i)
  if name=='regionMethods' then regionMethods=value;break end
  if name==nil then break end
 end
end
assert(type(regionMethods)=='table','MODEL: harness region methods reachable')
local journal=assert(ProjectEbonholdEchoJournal,'SETUP: journal frame exists')
local picker=assert(NexusWishlistOnlyPicker,'SETUP: picker was built by the chained fixture')
local clamped={}
clamped[picker]=true;clamped[GameTooltip]=true
local function within(f,root)
 while f do if f==root then return true end;f=f.parent end
 return false
end
local function modeled(f)
 return f==UIParent or f==GameTooltip or within(f,journal) or within(f,picker)
end
local function hpart(p) return p:find('LEFT') and 'l' or p:find('RIGHT') and 'r' or 'c' end
local function vpart(p) return p:find('TOP') and 't' or p:find('BOTTOM') and 'b' or 'm' end
local function parse(f,p)
 local point,rel,relPoint,x,y=p[1],p[2],nil,0,0
 if rel==nil then rel,relPoint=f.parent,point
 elseif type(rel)=='number' then rel,relPoint,x,y=f.parent,point,p[2],p[3] or 0
 else
  if type(rel)=='string' then rel=_G[rel] end
  if type(p[3])=='string' then relPoint,x,y=p[3],p[4] or 0,p[5] or 0
  elseif type(p[3])=='number' then relPoint,x,y=point,p[3],p[4] or 0
  else relPoint=point end
 end
 return point,rel,relPoint,x,y
end
local function span(c,low,high,mid,size)
 if c[low] and c[high] then return c[low],c[high] end
 if c[low] and c[mid] then return c[low],c[low]+2*(c[mid]-c[low]) end
 if c[high] and c[mid] then return c[high]-2*(c[high]-c[mid]),c[high] end
 if c[low] then return c[low],c[low]+size end
 if c[high] then return c[high]-size,c[high] end
 if c[mid] then return c[mid]-size/2,c[mid]+size/2 end
end
local Rect
function Rect(f,depth)
 depth=(depth or 0)+1;assert(depth<40,'MODEL: anchor cycle')
 if f==UIParent then return {l=0,r=SW,b=0,t=SH} end
 if not f or not modeled(f) or #f.points==0 then return nil end
 local hc,vc={},{}
 local s=f==GameTooltip and TIP_SCALE or 1
 for _,p in ipairs(f.points)do
  local point,rel,relPoint,x,y=parse(f,p)
  local rr=Rect(rel,depth);if not rr then return nil end
  local ax=({l=rr.l,r=rr.r,c=(rr.l+rr.r)/2})[hpart(relPoint)]
  local ay=({t=rr.t,b=rr.b,m=(rr.t+rr.b)/2})[vpart(relPoint)]
  hc[hpart(point)]=ax+x*s;vc[vpart(point)]=ay+y*s
 end
 local l,r=span(hc,'l','r','c',(f.width or 0)*s)
 local b,t=span(vc,'b','t','m',(f.height or 0)*s)
 if not l or not b then return nil end
 if clamped[f] then
  if r>SW then l,r=l-(r-SW),SW end
  if l<0 then l,r=0,r-l end
  if t>SH then b,t=b-(t-SH),SH end
  if b<0 then b,t=0,t-b end
 end
 return {l=l,r=r,b=b,t=t}
end
H.ModelRect=Rect
-- Geometry reads answer from the model for modeled frames only, in the
-- frame's own units (GameTooltip: divided by TIP_SCALE).
local function own(self,v) return self==GameTooltip and v/TIP_SCALE or v end
for name,fn in pairs({
 GetLeft=function(r) return r.l end,GetRight=function(r) return r.r end,
 GetTop=function(r) return r.t end,GetBottom=function(r) return r.b end,
 GetCenter=function(r) return (r.l+r.r)/2,(r.b+r.t)/2 end,
})do
 local original=regionMethods[name]
 regionMethods[name]=function(self,...)
  if self==picker and layoutPending then return nil end
  local r=modeled(self) and Rect(self)
  if r then
   if self==GameTooltip then r={l=own(self,r.l),r=own(self,r.r),b=own(self,r.b),t=own(self,r.t)} end
   return fn(r)
  end
  return original(self,...)
 end
end
local originalWidth,originalHeight=regionMethods.GetWidth,regionMethods.GetHeight
regionMethods.GetWidth=function(self)
 local r=modeled(self) and Rect(self);if r then return own(self,r.r-r.l) end;return originalWidth(self)
end
regionMethods.GetHeight=function(self)
 local r=modeled(self) and Rect(self);if r then return own(self,r.t-r.b) end;return originalHeight(self)
end
local originalScale=regionMethods.GetEffectiveScale
regionMethods.GetEffectiveScale=function(self)
 if modeled(self) then return UI_SCALE*(self==GameTooltip and TIP_SCALE or 1) end
 return originalScale(self)
end
-- Deferred layout: a new picker anchor is unresolved until the next frame.
local basePoint=regionMethods.SetPoint
function picker:SetPoint(...)
 if deferLayout then layoutPending=true end
 return basePoint(self,...)
end

-- GameTooltip model. Mutators that would change its layering are recorded.
local tipCalls={owner=0,layering={}}
local tt=GameTooltip
tt.strata='TOOLTIP';tt.frameLevel=1;tt.width,tt.height=0,0;tt.points={}
local baseShow,baseHide=regionMethods.Show,regionMethods.Hide
function tt:SetOwner(owner,anchor)
 tipCalls.owner=tipCalls.owner+1
 self.owner,self.anchor,self.lines=owner,anchor,{}
 if anchor~='ANCHOR_NONE' then self.points={} end
 if anchor=='ANCHOR_TOP' then self.points={{'BOTTOM',owner,'TOP',0,0}}
 elseif anchor=='ANCHOR_RIGHT' then self.points={{'BOTTOMLEFT',owner,'TOPRIGHT',0,0}}
 elseif anchor~='ANCHOR_NONE' then error('MODEL: unmodeled tooltip anchor '..tostring(anchor)) end
end
function tt:GetOwner() return self.owner end
function tt:IsOwned(f) return self.owner==f end
function tt:ClearLines() self.lines={} end
function tt:AddLine(text,r,g,b,wrap)
 self.lines=self.lines or {}
 self.lines[#self.lines+1]={text=tostring(text),r=r,g=g,b=b,wrap=wrap==true}
end
function tt:NumLines() return #(self.lines or {}) end
local function wrapped(text)
 local n,len=1,0
 for word in text:gmatch('%S+')do
  if len==0 then len=#word elseif len+1+#word<=CHARS then len=len+1+#word else n,len=n+1,#word end
 end
 return n
end
function tt:Show()
 local rows,w,wraps=0,0,false
 for _,line in ipairs(self.lines or {})do
  if line.wrap then wraps=true;rows=rows+wrapped(line.text)
  else rows=rows+1;w=math.max(w,#line.text*7+2*PAD) end
 end
 self.width=wraps and math.max(w,WRAP_W) or w
 self.height=rows*LINE_H+2*PAD
 baseShow(self)
end
function tt:Hide() baseHide(self) end
for _,name in ipairs({'SetFrameStrata','SetFrameLevel','SetParent','SetScale','SetToplevel','SetClampedToScreen','SetClampRectInsets'})do
 tt[name]=function(self,...) tipCalls.layering[#tipCalls.layering+1]=name end
end
local tipStrata,tipLevel,tipParent=tt:GetFrameStrata(),tt:GetFrameLevel(),tt:GetParent()

local STRATA={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local function drawsAbove(a,b)
 local sa,sb=STRATA[a:GetFrameStrata()] or 3,STRATA[b:GetFrameStrata()] or 3
 if sa~=sb then return sa>sb end
 return a:GetFrameLevel()>b:GetFrameLevel()
end
local function intersects(a,b) return a.l<b.r and b.l<a.r and a.b<b.t and b.b<a.t end
local function inset(r,d) return {l=r.l+d,r=r.r-d,b=r.b+d,t=r.t-d} end
local function onScreen(r) return r.l>=0 and r.r<=SW and r.b>=0 and r.t<=SH end
local function fmt(r) return r and string.format('l=%g r=%g b=%g t=%g',r.l,r.r,r.b,r.t) or 'nil' end

------------------------------------------------------------------------
-- Fixture helpers
------------------------------------------------------------------------
local selector=assert(NexusActiveWishlistSelector,'SETUP: selector exists')
local function place(left,top)
 journal:ClearAllPoints();journal:SetPoint('TOPLEFT',UIParent,'TOPLEFT',left,-top);journal:SetSize(990,570)
end
local function refresh() journal:Show();Nexus.JournalTab.RefreshAssociations() end
local function open()
 refresh()
 if picker:IsShown() then selector:Click() end
 selector:Click()
 check(picker:IsShown(),'actual selector opens its picker')
 return picker
end
local function close() if picker:IsShown() then selector:Click() end end
local function rows()
 local out={}
 for _,r in ipairs(picker.children)do if r.nameButton and r:IsVisible() then out[#out+1]=r end end
 return out
end
local function row(name)
 for _,r in ipairs(rows())do if r.nameButton.text:GetText():find(name,1,true)then return r end end
 error('picker row missing: '..name)
end
local function enter(f) assert(f:GetScript('OnEnter'),'control has a tooltip handler')(f) end
local function leave(f) local fn=f:GetScript('OnLeave');if fn then fn(f) end end
local function lines()
 local out={}
 for i,l in ipairs(tt.lines or {})do out[i]={text=l.text,r=l.r,g=l.g,b=l.b,wrap=l.wrap} end
 return out
end
local SELECTOR_LINES={
 'Automation Wishlist',
 'Assigns a wishlist reference to the Saved Build currently selected in the server dropdown. '
  ..'Assigning by itself does not change any Saved Build.',
 'With Auto ON, Nexus may replace the active Saved Build with a finished run that '
  ..'has more overall Wishlist progress, or equal progress after cleanup or an even swap of requested '
  ..'copies. At level 80 after a finished run, Auto checks again right away when you change the assignment. '
  ..'Saving edits to the assigned Wishlist can also lead to a replacement without a new run.',
 'The replaced build may hold an Echo you value, even one obtained with Orbs: '
  ..'Orb investment is not compared. Keep Auto OFF to leave the Saved Build unchanged.',
}
local function selectorWording(label)
 check(#tt.lines==#SELECTOR_LINES,label..': selector tooltip keeps its four lines')
 for i,text in ipairs(SELECTOR_LINES)do
  check(tt.lines[i].text==text,label..': selector tooltip line '..i..' is byte-identical')
 end
end

-- Hover never assigns, saves, uploads, changes a setting or exposes Orbs.
local baseActions=#H.actions
local function snapshot()
 return {actions=#H.actions,spend=H.Count('orb-spend'),save=H.Count('save'),upload=H.Count('upload'),
  db=H.Clone(NexusDB),assigned=H.Clone(A.AssignedWishlist()),settings=H.Clone(Nexus.Store.Settings())}
end
local function unchangedSince(s,label)
 check(#H.actions==s.actions and H.Count('orb-spend')==s.spend and H.Count('save')==s.save
  and H.Count('upload')==s.upload,label..': hover submits no action, save, upload or Orb spend')
 check(T.Equal(s.db,NexusDB),label..': hover writes nothing to the saved root')
 check(T.Equal(s.assigned,A.AssignedWishlist()),label..': hover assigns nothing')
 check(T.Equal(s.settings,Nexus.Store.Settings()),label..': hover changes no setting')
 local status=Nexus.OrbRuntime.Status()
 check(not status.running and not status.pending and status.spent==0 and status.reserved==0,label..': hover creates no Orb exposure')
end

-- Tooltip checks. The strict check is for the selector tooltip.
local function tipRect(label)
 check(tt:IsShown(),label..': tooltip is shown')
 local r=Rect(tt);check(r,label..': tooltip position resolves in the model')
 -- Leftover points from an earlier anchor would stretch the tooltip.
 check(math.abs((r.r-r.l)-tt.width*TIP_SCALE)<1e-6 and math.abs((r.t-r.b)-tt.height*TIP_SCALE)<1e-6,
  label..': tooltip keeps its own size (no conflicting anchor points, '..fmt(r)..')')
 return r
end
local function selectorTipBesidePicker(label)
 local r,p=tipRect(label),Rect(picker)
 print('SELECTOR_TIP',label,'anchor',tt.anchor,'tooltip',fmt(r),'picker',fmt(p),'selector',fmt(Rect(selector)))
 check(tt:GetOwner()==selector,label..': the selector owns its tooltip')
 check(drawsAbove(picker,tt),'MODEL premise: the open picker draws above GameTooltip')
 check(onScreen(r),label..': selector tooltip lies on the screen ('..fmt(r)..')')
 check(not intersects(r,p),label..': selector tooltip must not intersect the open picker (tooltip '..fmt(r)..', picker '..fmt(p)..')')
 selectorWording(label)
 return r,p
end
local function selectorTipTop(label)
 local r,s=tipRect(label),Rect(selector)
 print('SELECTOR_TIP',label,'anchor',tt.anchor,'tooltip',fmt(r),'selector',fmt(s))
 check(tt:GetOwner()==selector and tt.anchor=='ANCHOR_TOP' and #tt.points==1,label..': closed picker keeps ANCHOR_TOP on the selector')
 local p=tt.points[1]
 check(p[1]=='BOTTOM' and p[2]==selector and p[3]=='TOP' and p[4]==0 and p[5]==0,label..': ANCHOR_TOP geometry unchanged')
 check(onScreen(r),label..': whole selector tooltip on screen ('..fmt(r)..')')
 selectorWording(label)
end
local function textClearOfPicker(label)
 local r,p=tipRect(label),Rect(picker)
 print('PICKER_TIP',label,'anchor',tt.anchor,'tooltip',fmt(r),'picker',fmt(p))
 check(onScreen(r),label..': tooltip lies on the screen')
 check(not intersects(inset(r,PAD*TIP_SCALE),p),label..': tooltip text area must not intersect the open picker')
end
local function layeringUntouched(label)
 check(#tipCalls.layering==0,label..': GameTooltip strata, level, parent, scale and clamp are never changed ('..table.concat(tipCalls.layering,',')..')')
 check(tt:GetFrameStrata()==tipStrata and tt:GetFrameLevel()==tipLevel and tt:GetParent()==tipParent,label..': GameTooltip layering is as before')
end

------------------------------------------------------------------------
-- 1. Default placement (journal header near the screen top, as in C3).
------------------------------------------------------------------------
place(15,125);refresh();close()
check(A.AssignedWishlist().name=='Plan B','SETUP: fixture starts with Plan B assigned')
local before=snapshot()
enter(selector);selectorTipTop('picker closed')
local closedLines=lines()
local closedRect=Rect(tt)
leave(selector);check(not tt:IsShown(),'leaving the selector hides its tooltip')

-- Reproduce the C3 geometry: the ANCHOR_TOP tooltip does not fit above the
-- selector, the screen clamp moves it down over the picker's area.
local s=Rect(selector)
print('C3_MODEL','selector',fmt(s),'room above',SH-s.t,'tooltip height',closedRect.t-closedRect.b,'closed tooltip',fmt(closedRect))

open()
enter(selector);selectorTipBesidePicker('picker open, selector hover')
check(T.Equal(closedLines,lines()),'open and closed selector tooltips have identical lines and colours')
leave(selector);check(not tt:IsShown(),'leaving the selector hides its tooltip (picker open)')
check(picker:IsShown(),'hovering the selector does not toggle the picker')

-- Row, gear and Unassign tooltips while the picker is open (native PASS).
for _,r in ipairs(rows())do
 enter(r.nameButton);textClearOfPicker('row '..r.nameButton.text:GetText())
 check(tt.lines[1].text=='Assign Wishlist','row tooltip title unchanged');leave(r.nameButton)
 check(not tt:IsShown(),'leaving a row hides its tooltip')
 enter(r.gear);textClearOfPicker('gear');check(#tt.lines==1 and tt.lines[1].text=='Edit wishlist','gear tooltip unchanged')
 leave(r.gear);check(not tt:IsShown(),'leaving a gear hides its tooltip')
end
enter(picker.clearRow);textClearOfPicker('Unassign')
check(tt.lines[1].text=='Unassign Wishlist' and tt.lines[2].text=='Keeps the Wishlist; stops using it for this loadout.'
 and tt.lines[3].text=='Does not change or restore the Saved Build.','Unassign tooltip unchanged')
leave(picker.clearRow);check(not tt:IsShown(),'leaving Unassign hides its tooltip')
-- After another control owned the tooltip, the selector places it again.
enter(selector);selectorTipBesidePicker('selector after row hover');leave(selector)
check(picker:IsShown(),'hovers keep the picker open')
unchangedSince(before,'hover pass 1')

-- 2. Repeated reopen: the same placement every time.
for i=1,4 do
 open()
 enter(selector);selectorTipBesidePicker('reopen '..i);leave(selector)
 enter(row('Plan A').nameButton);textClearOfPicker('reopen '..i..' row');leave(row('Plan A').nameButton)
 close();check(not picker:IsShown(),'reopen '..i..': selector closes the picker')
 enter(selector);selectorTipTop('reopen '..i..' closed');leave(selector)
end
unchangedSince(before,'reopen passes')

-- 3. Toggling the picker while the mouse stays on the selector.
refresh();close()
enter(selector);selectorTipTop('toggle: before click')
selector:Click();check(picker:IsShown(),'toggle: click opens the picker')
selectorTipBesidePicker('toggle: opened under the mouse')
selector:Click();check(not picker:IsShown(),'toggle: click closes the picker')
selectorTipTop('toggle: closed under the mouse')
selector:Click();selectorTipBesidePicker('toggle: reopened under the mouse')
leave(selector);check(not tt:IsShown(),'toggle: leaving hides the tooltip')
close()
unchangedSince(before,'toggle pass')

-- 4. Cleanup: hide the journal, reopen. (Closing the picker under a row or
-- Unassign tooltip is checked in section 6, where the clicks may assign.)
open()
enter(selector);selectorTipBesidePicker('before journal hide')
local owners=tipCalls.owner
journal:Hide()
local panelHide=NexusLoadoutAssociationPanel:GetScript('OnHide')
panelHide(NexusLoadoutAssociationPanel) -- the client runs a child's OnHide when its parent hides
check(not picker:IsShown(),'hiding the journal closes the picker')
check(tipCalls.owner==owners,'closing a hidden selector\'s picker does not re-show its tooltip')
leave(selector) -- the client sends OnLeave when the frame under the mouse hides
check(not tt:IsShown(),'hidden journal: the selector tooltip is hidden')
open();enter(selector);selectorTipBesidePicker('after journal reopen');leave(selector);close()
check(not tt:IsShown(),'cleanup: tooltip hidden after leave')
layeringUntouched('cleanup')
unchangedSince(before,'cleanup pass')

------------------------------------------------------------------------
-- 5. Right screen edge: no room right of the picker.
------------------------------------------------------------------------
place(SW-990,125);refresh();close()
local p=open()
local pr=Rect(p)
print('RIGHT_EDGE','picker',fmt(pr),'room right',SW-pr.r,'room left',pr.l)
check(SW-pr.r<WRAP_W,'SETUP: the picker lacks room on its right')
-- A short tooltip first: the selector must measure its own tooltip after
-- Show(), not the previous tooltip's size.
enter(row('Plan A').gear);check(tt.lines[1].text=='Edit wishlist' and SW-pr.r>=tt:GetWidth()+4,'SETUP: the gear tooltip would fit right of the picker')
leave(row('Plan A').gear)
enter(selector);local r=selectorTipBesidePicker('right edge, picker open after a gear tooltip')
check(r.r<=pr.l,'right edge: the tooltip sits left of the picker')
leave(selector)
selector:Click();enter(selector);selectorTipTop('right edge, picker closed')
selector:Click();selectorTipBesidePicker('right edge, toggled open under the mouse');leave(selector);close()
-- The picker's position is not yet resolved when the click opens it under
-- the mouse: the side comes from the selector's left edge and picker width.
deferLayout=true
enter(selector);selectorTipTop('right edge, deferred layout, picker closed')
selector:Click()
check(picker:IsShown() and picker:GetLeft()==nil and picker:GetRight()==nil,'MODEL: the picker position is unknown right after the click')
r=selectorTipBesidePicker('right edge, deferred layout, toggled open under the mouse')
check(r.r<=Rect(picker).l,'right edge, deferred layout: the tooltip sits left of the picker')
render();deferLayout=false
leave(selector);close()
-- The default placement uses the right side.
place(15,125);open();enter(selector)
r=selectorTipBesidePicker('default placement side')
check(r.l>=Rect(picker).r,'default placement: the tooltip sits right of the picker')
leave(selector);close()
-- UI scale 0.75 and a tooltip scale of 1.25 (for example a tooltip-scale
-- addon): the tooltip width is converted into UIParent units. Here the
-- converted width does not fit right of the picker, the unconverted width
-- and the inverted conversion would.
place(SW-300-805,125);setScales(0.75,1.25)
p=open();pr=Rect(p)
print('SCALED','picker',fmt(pr),'room right',SW-pr.r,'tooltip own width',WRAP_W,'in UIParent units',WRAP_W*TIP_SCALE)
check(SW-pr.r<WRAP_W*TIP_SCALE+4 and SW-pr.r>=WRAP_W+4 and SW-pr.r>=WRAP_W/TIP_SCALE+4,
 'SETUP: only the converted width lacks room on the right')
enter(selector);r=selectorTipBesidePicker('scaled tooltip, picker open')
check(r.r<=pr.l,'scaled tooltip: the tooltip sits left of the picker')
leave(selector);close();setScales(1,1)
unchangedSince(before,'right-edge pass')
layeringUntouched('right-edge pass')

------------------------------------------------------------------------
-- 6. Selection behaviour is unchanged.
------------------------------------------------------------------------
check(#H.actions==baseActions,'no gameplay action before the selection checks')
-- The fixture keeps loadout 1's stored 'Plan A' design plan beside the server
-- 'Plan A' row, so a uniquely named server row identifies the click exactly.
local rolled=H.Clone(H.perks.serverBuildSlots[101].echoes)
H.perks.serverBuildSlots[103]={name='Plan C',verified=false,echoes=H.Clone(rolled)}
H.Notify();A.Poll()
open();local planC=row('Plan C').nameButton
enter(planC);planC:Click()
check(not picker:IsShown() and A.AssignedWishlist().name=='Plan C','a row click assigns exactly that row and closes the picker')
check(tt:IsShown() and tt:GetOwner()~=selector and tt.lines[1].text=='Assign Wishlist',
 'closing the picker under a row tooltip does not hand the tooltip to the selector')
leave(planC)
check(Nexus.Store.State().loadoutWishlists[2].slot==103,'the stored assignment keeps the clicked server slot')
open()
local marked={}
for _,x in ipairs(rows())do if x.nameButton.text:GetText():find('[Selected]',1,true)then marked[#marked+1]=x end end
check(#marked==1 and marked[1]==row('Plan C'),'exactly the assigned row carries [Selected]')
enter(selector);selectorTipBesidePicker('after selection');leave(selector)
-- A stale open row is refused and changes nothing.
local stale=row('Plan B')
for slot,name in pairs({[101]='Plan A',[102]='Plan B',[103]='Plan C'})do
 local e=H.Clone(rolled);e[1].spellId=e[1].spellId+700+slot
 H.perks.serverBuildSlots[slot]={name=name,verified=false,echoes=e}
end
H.Notify();A.Poll()
local storedBefore=H.Clone(Nexus.Store.State().loadoutWishlists[2])
local messages={};local originalPrint=print
print=function(...)
 local parts={};for i=1,select('#',...)do parts[#parts+1]=tostring((select(i,...)))end
 messages[#messages+1]=table.concat(parts,' ');originalPrint(...)
end
stale.nameButton:Click()
print=originalPrint
local refused=false
for _,m in ipairs(messages)do if m:find('wishlist changed; refresh and try again',1,true)then refused=true end end
check(refused,'a stale row is refused with "wishlist changed; refresh and try again"')
check(picker:IsShown(),'a refused selection keeps the picker open')
check(T.Equal(storedBefore,Nexus.Store.State().loadoutWishlists[2]),'a refused selection keeps the stored assignment')
-- Unassign clicked while its own tooltip is shown.
enter(picker.clearRow);picker.clearRow:Click()
check(not picker:IsShown() and A.AssignedWishlist().state=='unassigned','Unassign clears the assignment and closes the picker')
check(tt:IsShown() and tt:GetOwner()~=selector and tt.lines[1].text=='Unassign Wishlist',
 'closing the picker under the Unassign tooltip does not hand the tooltip to the selector')
leave(picker.clearRow)
close()
check(#H.actions==baseActions and H.Count('orb-spend')==0,'no gameplay action or Orb spend in the whole test')
layeringUntouched('end')
print('PASS selector tooltip beside the open picker (modeled geometry, not native pixels); closed picker keeps ANCHOR_TOP; row/gear/Unassign/selection unchanged; checks='..checks)
