-- Native08 popup boundary model. Product renderer/controller/catalog stay real.
-- Models the reported DIALOG/1 popup, inherited child strata, and WoW's
-- per-dialog OnShow/OnHide dispatch. It does not claim native hit testing.
local D=dofile('tests/prototype/stop_sharing_support.lua')
local L={D=D,T=D.T}
function L.Begin()
 local original=dofile
 dofile=function(path)
  local result=original(path)
  if path=='tests/prototype/harness.lua' then
   local create=CreateFrame
   CreateFrame=function(kind,name,parent,template,...)
    local f=create(kind,name,parent,template,...);f.testTemplate=template
    if template=='UIPanelCloseButton' then
     f:SetScript('OnClick',function(self)self:GetParent():Hide()end)
    end
    return f
   end
  end
  return result
 end
 local H,C,id,button,restore=D.Begin();dofile=original
 local p=CreateFrame('Frame','StaticPopup3',UIParent)
 p:SetFrameStrata('DIALOG');p:SetFrameLevel(1);p:Hide()
 local untouched=CreateFrame('Frame','StaticPopup4',UIParent)
 untouched:SetFrameStrata('DIALOG');untouched:SetFrameLevel(1);untouched:Hide()
 p:SetScript('OnHide',function(self)
  local info=StaticPopupDialogs[self.which]
  if info and info.OnHide then info.OnHide(self) end
  if H.popup==self then H.popup=nil end
  self.which=nil;self.data=nil
 end)
 local function finish(accept)
  if not p:IsShown() then return end
  local info=assert(StaticPopupDialogs[p.which])
  local action=accept and info.OnAccept or info.OnCancel
  if action then action(p,p.data) end
  p:Hide()
 end
 for index=1,2 do
  local child=CreateFrame('Button','StaticPopup3Button'..index,p)
  child:SetFrameLevel(2)
  child.GetFrameStrata=function(self)return self.strata or self:GetParent():GetFrameStrata()end
  child:SetScript('OnClick',function()finish(index==1)end)
  p['button'..index]=child
 end
 StaticPopup_Show=function(which,a,b,data)
  if p:IsShown() and p.which~=which then p:Hide() end
  p.which=which;p.data=data;H.popup=p
  local info=assert(StaticPopupDialogs[which])
  p.button1:SetText(info.button1 or '');p.button2:SetText(info.button2 or '')
  p:Show()
  -- FrameXML dispatches the dialog callback even when the slot was shown.
  if info.OnShow then info.OnShow(p,data) end
  return p
 end
 StaticPopup_Hide=function(which)
  if p:IsShown() and p.which==which then p:Hide() end
 end
 H.AcceptPopup=function()p.button1:Click()end
 H.EscapePopup=function()
  local info=p:IsShown() and StaticPopupDialogs[p.which]
  if info and info.hideOnEscape then
   if info.OnCancel then info.OnCancel(p,p.data,'timeout') end
   p:Hide()
  end
 end
 local library=assert(NexusCommunityBuildsFrame)
 local close
 for _,f in ipairs(H.frames)do
  if f:GetParent()==library and f.testTemplate=='UIPanelCloseButton' then close=f end
 end
 assert(close,'actual Library close button with its native template behavior')
 return H,C,id,button,restore,p,library,close,untouched
end
local rank={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
function L.Above(p,library)
 assert(p:IsShown(),'actual named confirmation must remain shown')
 local function above(f)
  local a,b=assert(rank[f:GetFrameStrata()]),assert(rank[library:GetFrameStrata()])
  assert(a>b or a==b and f:GetFrameLevel()>library:GetFrameLevel(),
   'NATIVE08: confirmation and its buttons must be above the Library; popup='..
   f:GetFrameStrata()..'/'..f:GetFrameLevel()..' Library='..library:GetFrameStrata()..'/'..library:GetFrameLevel())
 end
 above(p);above(p.button1);above(p.button2)
 assert(p.button1:IsVisible() and p.button2:IsVisible(),'both normal confirmation buttons remain visible')
end
function L.Open(H,id,button,p,library)
 button:Click()
 assert(H.popup==p and p.which=='NEXUS_STOP_SHARING_BUILD' and p.data.id==id,'actual renderer exact-ID confirmation')
 L.Above(p,library)
 return p
end
function L.Restored(p,strata,level)
 assert(not p:IsShown() and p:GetFrameStrata()==strata and p:GetFrameLevel()==level,'popup slot restores its original layer on dismissal')
end
return L
