-- ui/ServerStatus.lua and the stock Project Ebonhold run frame.
--
-- #32: opening the Hardcore menu from the Nexus panel must never run a stock
-- control's click handler to find out what it does. The old path called
-- every clickable child of ProjectEbonholdPlayerRunFrame, best screen
-- position first, until HardmodeFrame appeared, so an unrelated control ran
-- whenever it scored higher. The identity of the stock Hardcore control is
-- not known offline, so no child handler is ever invoked; the menu opens
-- only through HardmodeFrame itself, and fails closed when it is absent.
--
-- The real module in a synthetic host (the server_hud_handoff shape).
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local function Clickable(name,x,y,log,effect)
 local b={name=name,x=x,y=y,scripts={}}
 b.scripts.OnClick=function(self)
  log[#log+1]=self.name
  if effect then effect() end
 end
 function b:GetScript(event) return self.scripts[event] end
 function b:GetCenter() return self.x,self.y end
 function b:GetChildren() return end
 return b
end
local function StockFrame(children)
 local root={shown=true,hooks={},hookInstalls=0,hookRuns=0,children=children or {}}
 function root:Hide() self.shown=false end
 function root:Show() self.shown=true;if self.hooks.OnShow then self.hooks.OnShow(self) end end
 function root:SetShown(v) if v then self:Show() else self:Hide() end end
 function root:IsShown() return self.shown end
 function root:SetAlpha() end
 function root:EnableMouse() end
 function root:HookScript(event,fn)
  self.hookInstalls=self.hookInstalls+1
  local previous=self.hooks[event]
  self.hooks[event]=function(...)
   self.hookRuns=self.hookRuns+1
   if previous then previous(...) end
   return fn(...)
  end
 end
 function root:GetScript() return nil end
 function root:GetRegions() return end
 function root:GetChildren() return unpack(self.children) end
 function root:GetLeft() return 0 end
 function root:GetBottom() return 0 end
 function root:GetWidth() return 100 end
 function root:GetHeight() return 100 end
 return root
end
local function HardFrame(shown)
 local f={shown=shown==true,showCalls=0,hideCalls=0}
 function f:IsShown() return self.shown end
 function f:Show() self.shown=true;self.showCalls=self.showCalls+1 end
 function f:Hide() self.shown=false;self.hideCalls=self.hideCalls+1 end
 function f:Raise() end
 return f
end
-- Chat lines about the Hardcore menu are collected; everything else prints.
local printed={}
local realPrint=print
print=function(msg,...)
 if tostring(msg):find('Hardcore menu',1,true) then printed[#printed+1]=tostring(msg);return end
 return realPrint(msg,...)
end
local function Host(root,hard)
 NexusDB={soulAshHudMode='nexus'}
 Nexus={Panel={VisibilityFacts=function() return {exists=true,shown=true,wanted=true,ready=true,committed=true} end}}
 UIParent={};EbonholdIntensityData=nil;HardmodeFrame=hard
 ProjectEbonholdPlayerRunFrame=root
 local frames={}
 function CreateFrame(kind,name,parent)
  local f={name=name,scripts={}}
  function f:RegisterEvent() end
  function f:SetScript(event,fn) self.scripts[event]=fn end
  frames[name]=f;return f
 end
 dofile('ui/ServerStatus.lua')
 Nexus.ServerStatus.Init()
 local scanner=assert(frames.NexusServerStatusScanner,'the scanner is created')
 return Nexus.ServerStatus,
  function() scanner.scripts.OnUpdate(scanner,1.0) end,
  function() scanner.scripts.OnEvent(scanner,'PLAYER_ENTERING_WORLD') end
end

-- 1. #32: two clickable stock children. The upper-right one, which the old
-- ranking tried first, is NOT the Hardcore control. Neither runs.
do
 local clicks={}
 local hard=HardFrame(false)
 local unrelated=Clickable('unrelated',95,95,clicks)
 local skull=Clickable('skull',50,50,clicks,function() hard.shown=true end)
 local status=Host(StockFrame({unrelated,skull}),hard)
 local opened=status.OpenHardcoreMenu()
 check(#clicks==0,'no stock click handler runs when the menu opens: '..table.concat(clicks,','))
 check(opened==true and hard.shown==true and hard.showCalls==1,
  'the menu opens through HardmodeFrame itself')
 -- Already open: the same call closes it, as before.
 check(status.OpenHardcoreMenu()==true and hard.shown==false and hard.hideCalls==1,
  'an open menu is closed by the same button')
 -- Repeated opens run no handler either.
 for _=1,5 do status.OpenHardcoreMenu() end
 check(#clicks==0,'repeated opens run no stock handler: '..table.concat(clicks,','))
end

-- 2. #32: HardmodeFrame does not exist. The call fails closed: no stock
-- handler runs, nothing is shown, and the player is told once where the
-- menu is.
do
 local clicks={}
 local unrelated=Clickable('unrelated',95,95,clicks)
 local other=Clickable('other',10,10,clicks)
 printed={}
 local status=Host(StockFrame({unrelated,other}),nil)
 check(status.OpenHardcoreMenu()==false,'without HardmodeFrame the call reports that nothing opened')
 check(#clicks==0,'and no stock handler ran: '..table.concat(clicks,','))
 check(#printed==1,'the player is told why: '..#printed)
 status.OpenHardcoreMenu()
 check(#printed==1,'and told only once per session: '..#printed)
end

print=realPrint
print('PASS server_status_click_and_hook checks='..checks)
