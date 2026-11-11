-- Real TOC/HUD/mini handlers; synthetic services and font-width model only.
-- Native pixels, input, scaling and FPS remain NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local H=F.Boot(F.Database(),function(h)
 F.OrbService(h)
 CreateFont=function(name)
  local f={path='Fonts\\FRIZQT__.TTF',size=12,flags=''}
  function f:SetFont(path,size,flags)self.path,self.size,self.flags=path,size,flags;return true end
  function f:GetFont()return self.path,self.size,self.flags end
  _G[name]=f;return f
 end
 local create=CreateFrame
 CreateFrame=function(...)
  local f=create(...)
  local makeString=f.CreateFontString
  f.CreateFontString=function(self,...)
   local r=makeString(self,...)
   r.SetFontObject=function(self,font)self.font=type(font)=='string' and _G[font] or font end
   r.GetStringWidth=function(self)
    return #(self:GetText() or '')*math.max(7,.7*(self.font and self.font.size or 10))
   end
   return r
  end
  if f:GetObjectType()=='Button' then
   local fs=f:CreateFontString(nil,'OVERLAY')
   f.GetFontString=function()return fs end
   f.SetNormalFontObject=function(_,font)fs:SetFontObject(font)end
  end
  return f
 end
end)
Nexus.DisableOrdinaryAutomation()
Nexus.Panel.Show()
local model={status='ready',level=40,auto=false,paused=true,cards={},recommendation='',
 progress={wishlistName='Synthetic Orb navigation',total=6,owned=0,missing={},shed={},toLock={},unknownTomes={}},
 orbGuidance={state='orb-state',text='Inspect Orb status before continuing.',openOrbs=true,blockers={}},
 serverStatus={tier='Synthetic difficulty',ash='12345',gain='12',intensity=.5}}
check(Nexus.Panel.Render(model),'HUD accepts the synthetic Orb guidance model')
local hud=NexusPanel
local miniButton,open=hud._orbMiniBtn,hud._orbsBtn
check(miniButton and miniButton:IsShown() and open:IsShown(),'both passive Orb controls are visible together')
check(miniButton:GetText()=='Orb mini panel','default-scale label identifies the Orb mini panel')
local card
for _,f in ipairs(H.frames)do if f._nexusThemeExempt and f:GetParent()==hud then card=f end end
check(card~=nil,'protected difficulty/Soul Ash card remains present')
local function cardGeometry()
 local out={card:GetWidth(),card:GetHeight(),card:GetNumPoints()}
 for _,r in ipairs(card.regions)do
  out[#out+1]={r:GetText(),r:GetWidth(),r:GetHeight(),r:GetNumPoints()}
 end
 return F.Serialize(out)
end
local preserved=cardGeometry()
local settings=F.Serialize(NexusDB.settings)
local actions=#H.actions
check(not Nexus.OrbPanel.MiniShown(),'HUD navigation does not open the mini panel automatically')
miniButton:Click()
check(NexusOrbMini and Nexus.OrbPanel.MiniShown(),'HUD click opens the existing mini panel')
local mini=NexusOrbMini
local frameCount=#H.frames
for _=1,12 do mini.close:Click();miniButton:Click()end
check(#H.frames==frameCount and NexusOrbMini==mini,'repeated close/open reuses the existing mini panel')
check(hud:IsShown() and cardGeometry()==preserved,'navigation leaves the HUD and protected card geometry intact')
local escapeCount=0
for _,name in ipairs(UISpecialFrames)do if name=='NexusOrbMini'then escapeCount=escapeCount+1 end end
check(escapeCount==1,'repeated access adds no duplicate Escape registration')
check(#H.actions==actions and F.Serialize(NexusDB.settings)==settings,'opening cannot spend, authorize a run or change settings')
local lines={}
GameTooltip.AddLine=function(_,text)lines[#lines+1]=text end
miniButton:GetScript('OnEnter')(miniButton)
check(lines[1]=='Orb mini panel' and lines[2]:find('starts or spends nothing',1,true),'tooltip identifies the compact label and passive behavior')
miniButton:GetScript('OnLeave')(miniButton)
check(not GameTooltip:IsShown(),'tooltip closes on leave')
mini.close:Click();open:Click()
check(NexusOrbPanel and NexusOrbPanel:IsShown() and not Nexus.OrbPanel.MiniShown(),'existing Open Orbs handler still opens only the full window')
check(#H.actions==actions,'existing full-window navigation also spends nothing')

for _,scale in ipairs({.75,1,1.25,1.5,2})do
 for _,uiScale in ipairs({.65,1,1.5})do
  NexusFontNormal:SetFont('Fonts\\FRIZQT__.TTF',12*scale,'')
  NexusFontSmall:SetFont('Fonts\\FRIZQT__.TTF',10*scale,'')
  -- Approved panel cleanup (secondary floor 11): the main panel's secondary
  -- text, this button's label included, is its own 11-unit font object; it
  -- follows the same synthetic scale here as the shared fonts above.
  if NexusFontSecondary then NexusFontSecondary:SetFont('Fonts\\FRIZQT__.TTF',11*scale,'') end
  UIParent.GetEffectiveScale=function()return uiScale end
  for _,withCards in ipairs({false,true})do
   model.cards=withCards and {{text='Synthetic card'}} or {}
   check(Nexus.Panel.Render(model),'layout updates for font/UI scale and card visibility')
   local area=open:GetParent()
   local point,parent,relative,x,y=miniButton:GetPoint()
   check(point=='RIGHT' and parent==open and relative=='LEFT' and x<0 and y==0,'mini control is immediately left of Open Orbs')
   local _,openParent,_,right,bottom=open:GetPoint()
   local openLeft=area:GetWidth()+right-open:GetWidth()
   local miniRight=openLeft+x
   local miniLeft=miniRight-miniButton:GetWidth()
   check(openParent==area and miniLeft>=2 and miniRight<openLeft,'separate hit targets fit inside the existing HUD width')
   check(miniButton:GetHeight()==open:GetHeight(),'the two controls share a row height')
   local fit=miniButton._nexusMiniFit
   check(fit and fit.fits and fit.width+20<=miniButton:GetWidth(),'font-width model fits the label with end-cap clearance')
   local char=Nexus.LayoutMetrics.ConservativeText(scale)
   local available=hud:GetWidth()-24-open:GetWidth()-6
   local expected=math.ceil(14*char)+20<=available and 'Orb mini panel' or 'Mini'
   check(miniButton:GetText()==expected,'full label is used unless the actual wider HUD leaves too little space')
   local _,_,_,_,recY=hud._rollRec:GetPoint()
   local buttonTop=area:GetHeight()-bottom-open:GetHeight()
   check(-recY+hud._rollRec:GetHeight()<=buttonTop,'the button row does not cover the guidance text')
   local probe=miniButton._nexusMiniProbe
   local font=miniButton._nexusMiniFont
   local count=#H.frames
   Nexus.Panel.Render(model)
   check(miniButton._nexusMiniProbe==probe and miniButton._nexusMiniFont==font and #H.frames==count,'unchanged renders reuse font, probe and frames')
  end
 end
end
model.orbGuidance.openOrbs=false
check(Nexus.Panel.Render(model),'guidance can withdraw navigation')
check(not open:IsShown() and not miniButton:IsShown(),'mini access follows the existing Open Orbs visibility')
check(NexusFontSmall.size==20 and NexusFontNormal.size==24,'fitting does not resize shared owned fonts')
check(#H.actions==actions and Nexus.RecomputeStats().autoEnabled==false,'all navigation and modeled layouts leave automation OFF and actions unchanged')
print('PASS HUD Orb mini access: '..checks..' checks; source/font model only, native pixels NOT_RUN')
