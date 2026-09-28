-- ui/ServerStatus.lua and the stock Project Ebonhold run frame.
--
-- #32: opening the Hardcore menu from the Nexus panel must never run a stock
-- control's click handler to find out what it does. The old path called
-- every clickable child of ProjectEbonholdPlayerRunFrame, best screen
-- position first, until HardmodeFrame appeared, so an unrelated control ran
-- whenever it scored higher.
--
-- The Project Ebonhold contract (modules/torment/hardmode.lua and
-- modules/playerRun/player_run_ui.lua of the installed addon): HardmodeFrame
-- is created only inside the addon's private toggle, which also asks the
-- server for the current tier and the Soul Ash pool and rebuilds the panel.
-- The one control that runs it is published as ProjectEbonhold.HardmodeButton,
-- a child of the run HUD's header frame. So HardmodeFrame:Show() alone opens
-- nothing before the first toggle (the reported "cannot open") and shows a
-- stale tier after it. Nexus calls the published control's handler, only
-- when it sits in the run HUD, and no other handler.
--
-- #33: the OnShow hook that keeps the stock HUD hidden is installed once per
-- frame OBJECT. The client chains hooks and never removes them, so a hook
-- added again on every world entry kept stacking on the same frame.
--
-- The real module in a synthetic host (the server_hud_handoff shape). The
-- toggle below models the contract; it is not the Project Ebonhold source.
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
 function b:GetParent() return self.parent end
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
 function root:GetParent() return nil end
 function root:GetLeft() return 0 end
 function root:GetBottom() return 0 end
 function root:GetWidth() return 100 end
 function root:GetHeight() return 100 end
 for _,c in ipairs(root.children) do c.parent=root end
 return root
end
-- A header frame inside the root holding the given buttons.
local function Header(root,buttons)
 local h={children=buttons,parent=root,scripts={}}
 function h:GetParent() return self.parent end
 function h:GetChildren() return unpack(self.children) end
 function h:GetScript() return nil end
 for _,b in ipairs(buttons) do b.parent=h end
 root.children[#root.children+1]=h
 return h
end
-- The modelled Project Ebonhold side: server state, requests, lazy panel.
local function Ebonhold(root,log,opts)
 opts=opts or {}
 local pe={tier=1,requests={},builds={}}
 local panel=nil
 local function Toggle()
  if not panel then
   panel={shown=false,builtTier=nil}
   function panel:IsShown() return self.shown end
   function panel:Show() self.shown=true end
   function panel:Hide() self.shown=false end
   HardmodeFrame=panel
  end
  if panel.shown then panel:Hide();return end
  pe.requests[#pe.requests+1]='REQUEST_HARDMODE_DATA'
  pe.requests[#pe.requests+1]='REQUEST_PRESTIGE_DATA'
  panel:Show()
  panel.builtTier=pe.tier;pe.builds[#pe.builds+1]=pe.tier
 end
 pe.Toggle=Toggle
 local skull=Clickable('skull',50,50,log,function() if not opts.noToggle then Toggle() end end)
 Header(root,{skull})
 ProjectEbonhold={HardmodeButton=skull}
 return pe,skull
end
-- Chat lines about the Hardcore menu are collected; everything else prints.
local printed={}
local realPrint=print
print=function(msg,...)
 if tostring(msg):find('Hardcore menu',1,true) then printed[#printed+1]=tostring(msg);return end
 return realPrint(msg,...)
end
local function Host(root)
 NexusDB={soulAshHudMode='nexus'}
 Nexus={Panel={VisibilityFacts=function() return {exists=true,shown=true,wanted=true,ready=true,committed=true} end}}
 UIParent={};EbonholdIntensityData=nil;HardmodeFrame=nil;ProjectEbonhold=nil
 reportedErrors={}
 geterrorhandler=function() return function(err) reportedErrors[#reportedErrors+1]=tostring(err) end end
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

-- 1. The reported case: first open in a session, stock HUD hidden by Nexus.
-- HardmodeFrame does not exist yet; only the published control creates it.
-- The upper-right unrelated control, which the old ranking tried first,
-- never runs.
do
 local clicks={};printed={}
 local unrelated=Clickable('unrelated',95,95,clicks)
 local root=StockFrame({unrelated})
 local status,tick=Host(root)
 local pe=Ebonhold(root,clicks)
 tick()
 check(root.shown==false,'fixture: Nexus hides the stock HUD')
 check(HardmodeFrame==nil,'fixture: no panel before the first toggle')
 local opened=status.OpenHardcoreMenu()
 check(opened==true and HardmodeFrame and HardmodeFrame.shown==true,'the Nexus control opens the Hardcore panel')
 check(table.concat(clicks,',')=='skull','only the published Hardcore control ran: '..table.concat(clicks,','))
 check(table.concat(pe.requests,',')=='REQUEST_HARDMODE_DATA,REQUEST_PRESTIGE_DATA',
  'opening asks for the current tier and Soul Ash pool: '..table.concat(pe.requests,','))
 check(root.shown==false,'the stock HUD stays hidden')
 check(#printed==0,'nothing is printed when the menu opens')
 -- Already open: the same call closes it through the same toggle.
 check(status.OpenHardcoreMenu()==true and HardmodeFrame.shown==false,'an open menu is closed by the same button')
 check(#pe.requests==2,'closing requests nothing')
 check(table.concat(clicks,',')=='skull,skull','and no other handler ran: '..table.concat(clicks,','))
end

-- 2. The panel exists from an earlier open and the tier changed on the
-- server while it was closed: opening rebuilds it for the current tier.
do
 local clicks={};printed={}
 local root=StockFrame()
 local status=Host(root)
 local pe=Ebonhold(root,clicks)
 pe.Toggle();pe.Toggle()
 check(HardmodeFrame and HardmodeFrame.shown==false and HardmodeFrame.builtTier==1,'fixture: built for tier 1, closed')
 pe.tier=3
 check(status.OpenHardcoreMenu()==true and HardmodeFrame.shown==true,'the panel opens')
 check(HardmodeFrame.builtTier==3,'for the current tier, not the stale one: '..tostring(HardmodeFrame.builtTier))
 check(#pe.requests==4,'with a fresh request: '..#pe.requests)
end

-- 3. The published control is not the one in the run HUD: its handler never
-- runs, nothing opens, and the player is told once. The same holds for a
-- button without a handler, a handler that raises, a handler that changes
-- nothing, a missing run HUD and a ProjectEbonhold table that raises on read.
do
 local cases={
  {'a button outside the run HUD',function(root,clicks)
    Ebonhold(root,clicks)
    ProjectEbonhold.HardmodeButton=Clickable('impostor',99,99,clicks)
    ProjectEbonhold.HardmodeButton.parent={GetParent=function() return {} end}
   end,{}},
  {'a button without a handler',function(root,clicks)
    local _,skull=Ebonhold(root,clicks);skull.scripts.OnClick=nil
   end,{}},
  {'a handler that raises',function(root,clicks)
    local _,skull=Ebonhold(root,clicks)
    skull.scripts.OnClick=function() clicks[#clicks+1]='raised';error('boom') end
   end,{'raised'}},
  {'a handler that changes nothing',function(root,clicks)
    Ebonhold(root,clicks,{noToggle=true})
   end,{'skull'}},
  {'no run HUD',function(root,clicks)
    Ebonhold(root,clicks);ProjectEbonholdPlayerRunFrame=nil
   end,{}},
  {'a ProjectEbonhold table that raises',function(root,clicks)
    ProjectEbonhold=setmetatable({},{__index=function() error('hostile') end})
   end,{}},
  {'a button whose GetParent raises',function(root,clicks)
    local _,skull=Ebonhold(root,clicks)
    skull.GetParent=function() error('hostile parent') end
   end,{}},
 }
 for _,c in ipairs(cases) do
  local clicks={};printed={}
  local unrelated=Clickable('unrelated',95,95,clicks)
  local root=StockFrame({unrelated})
  local status=Host(root)
  c[2](root,clicks)
  local ok,opened=pcall(status.OpenHardcoreMenu)
  check(ok,c[1]..': the call does not raise: '..tostring(opened))
  check(opened==false,c[1]..': reports that nothing opened')
  check(HardmodeFrame==nil or HardmodeFrame.shown~=true,c[1]..': no panel is shown')
  check(table.concat(clicks,',')==table.concat(c[3],','),c[1]..': handlers run: '..table.concat(clicks,','))
  check(#printed==1,c[1]..': the player is told why: '..#printed)
  status.OpenHardcoreMenu()
  check(#printed==1,c[1]..': and told only once per session: '..#printed)
 end
end

-- 4. An open panel with no identified control is still closed by the Nexus
-- control; nothing is requested, built or clicked.
do
 local clicks={};printed={}
 local unrelated=Clickable('unrelated',95,95,clicks)
 local root=StockFrame({unrelated})
 local status=Host(root)
 local pe=Ebonhold(root,clicks)
 pe.Toggle()
 ProjectEbonhold.HardmodeButton=nil
 check(status.OpenHardcoreMenu()==true and HardmodeFrame.shown==false,'the open panel is closed')
 check(#clicks==0 and #pe.requests==2,'without any handler or request')
 check(status.OpenHardcoreMenu()==false and HardmodeFrame.shown==false,'and is not reopened without the control')
end

-- 5. The stock toggle raises part-way. What counts is the panel: opened is
-- opened, and the error still reaches the client's error handler; a toggle
-- that raises without closing an open panel is backed by a plain Hide; a
-- hostile HardmodeFrame in that path raises nothing out of the call.
do
 local clicks={};printed={}
 local root=StockFrame()
 local status=Host(root)
 local pe,skull=Ebonhold(root,clicks)
 skull.scripts.OnClick=function() pe.Toggle();error('after show') end
 check(status.OpenHardcoreMenu()==true and HardmodeFrame.shown==true,'a toggle that raises after showing still counts as opened')
 check(#reportedErrors==1 and reportedErrors[1]:find('after show',1,true),'and its error is reported: '..#reportedErrors)
 check(#printed==0,'with no misleading notice: '..#printed)
 skull.scripts.OnClick=function() error('before hide') end
 check(status.OpenHardcoreMenu()==true and HardmodeFrame.shown==false,'a toggle that raises while open is backed by Hide')
 check(#reportedErrors==2,'and that error is reported too: '..#reportedErrors)
end
do
 local clicks={};printed={}
 local root=StockFrame()
 local status=Host(root)
 HardmodeFrame=setmetatable({},{__index=function(_,k)
  if k=='IsShown' then return function() return true end end
  error('hostile frame')
 end})
 local ok,res=pcall(status.OpenHardcoreMenu)
 check(ok and res==false,'a hostile HardmodeFrame raises nothing out of the call: '..tostring(res))
 check(#printed==1,'and the player is told once: '..#printed)
end

-- 6. #33: world entries on the SAME stock frame keep exactly one hook.
do
 local root=StockFrame()
 local _,tick,enterWorld=Host(root)
 tick()
 check(root.hookInstalls==1,'fixture: the first scan installs the hook: '..root.hookInstalls)
 for _=1,6 do enterWorld();tick() end
 check(root.hookInstalls==1,'six world entries add no hook to the same frame: '..root.hookInstalls)
 Nexus.ServerStatus.Rescan()
 check(root.hookInstalls==1,'nor does a rescan: '..root.hookInstalls)
 root:Hide();root.hookRuns=0;root:Show()
 check(root.hookRuns==1,'one show runs the hook once: '..root.hookRuns)
 check(root.shown==false,'and the hook still hides the stock HUD while Nexus replaces it')
 -- A NEW frame object (the game rebuilt it) gets its own single hook.
 local rebuilt=StockFrame()
 ProjectEbonholdPlayerRunFrame=rebuilt
 enterWorld();tick();enterWorld();tick()
 check(rebuilt.hookInstalls==1,'a rebuilt frame is hooked once: '..rebuilt.hookInstalls)
 check(root.hookInstalls==1,'and the old frame gains nothing: '..root.hookInstalls)
end

print=realPrint
print('PASS server_status_click_and_hook checks='..checks)
