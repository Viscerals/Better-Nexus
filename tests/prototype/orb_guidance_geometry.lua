-- Modeled fit of the Orb guidance on the HUD and of the Orb window's start
-- refusal. The harness has no font renderer, so this is a MODEL:
--   HUD texts use the addon's owned small font, 10 px x the runtime font
--   scale s (LayoutMetrics clamps s to 0.75-2); s is set here through the
--   owned normal font's size, as the runtime reads it.
--   default      0.55 em per character, 1.2 em lines
--   conservative the larger of a wide face NOT reflected in the scale (the
--                7.0 px / 17 px model of quickstart_layout_fit.lua, wider
--                than the replacement font measured natively for 20dabcd)
--                and a wide face that scales (0.70 em per character, 1.2 em
--                lines)
--   The Orb window uses fixed 7.0 px / 17 px (conservative) and 5.5 / 12.
-- The word wrap and the character count are this file's own; they do not
-- call the product's LayoutMetrics.TextRows.
-- Sizes and positions are the real widgets' after real renders and the real
-- final layout pass; texts are the real texts, including the longest
-- Orb-state reason and the longest overlapping refusal. A UI scale multiplies
-- text and frames alike and does not change a fit. The heading is modeled
-- for width only (one line); its line height is the layout's own row, as for
-- every other heading. Native pixel fit is NOT established here.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local SCALES={0.75,1,1.25,1.5,2}
local HUD={
 {name='default',char=function(s) return 0.55*10*s end,line=function(s) return 1.2*10*s end},
 {name='conservative',char=function(s) return math.max(7.0,0.70*10*s) end,line=function(s) return math.max(17,1.2*10*s) end},
}
local MODELS={{name='default',char=5.5,line=12},{name='conservative',char=7.0,line=17}}
local CAPS=20 -- the button template's two end caps
local function Plain(s) return (tostring(s or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
-- Visible characters: a UTF-8 sequence (for example the dash) counts once.
local function Len(s) local n=0;for _ in Plain(s):gmatch('[^\128-\191]') do n=n+1 end;return n end
local function Lines(text,width,char)
 text=Plain(text);local lines=0
 for para in (text..'\n'):gmatch('(.-)\n') do
  lines=lines+1;local used=0
  for word in para:gmatch('%S+') do
   local w=Len(word)*char;local gap=used>0 and char or 0
   if used>0 and used+gap+w>width then lines=lines+1;used=w else used=used+gap+w end
  end
 end
 return lines
end

local F=dofile('tests/prototype/format5_support.lua')
local function Granted(n)
 local g,id,left={},200001,n
 while left>0 do local s=math.min(5,left);local l={};for i=1,s do l[i]={spellId=id,quality=0} end;g['Echo '..(id-200000)]=l;left=left-s;id=id+1 end
 return g
end
local function Plan()
 local rows={}
 for id=200001,200015 do rows[#rows+1]={spellId=id,quality=id%4,stacks=5,locked=false} end
 rows[#rows+1]={spellId=200016,quality=200016%4,stacks=4,locked=false}
 return rows
end
local H
-- Font objects whose size the runtime reads back (the harness has none).
local function FontDouble()
 CreateFont=function(name)
  local f={name=name,path='Fonts\\FRIZQT__.TTF',size=12,flags=''}
  function f:SetFont(p,sz,fl) self.path,self.size,self.flags=p,sz,fl;return true end
  function f:GetFont() return self.path,self.size,self.flags end
  function f:SetFontObject(o) self.parent=o end
  _G[name]=f;return f
 end
end
local function Boot(orbService,opt)
 opt=opt or {}
 H=F.Boot(F.Database({}),function(h)
  FontDouble()
  h.playerLevel=80;h.granted=Granted(opt.rolled or 75);h.pendingRolls=0
  ProjectEbonhold=ProjectEbonhold or {};ProjectEbonhold.OrbService=orbService
 end)
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic Plan',Plan(),opt.design or {}))
 SlashCmdList.NEXUS('auto')
 for _=1,6 do Nexus.RequestRecompute();H.Advance(.4) end
end
local idle={IsStateKnown=function() return true end,IsOfferPending=function() return false end,
 GetCharges=function() return 3 end,RequestCharges=function() return true end,ConfirmSpend=function() return true end}
-- An Orb service without IsStateKnown: the longest Orb-state reason.
local stateless={IsOfferPending=function() return false end}

local function Scale(s)
 _G.NexusFontNormal:SetFont('Fonts\\FRIZQT__.TTF',12*s,'');_G.NexusFontSmall:SetFont('Fonts\\FRIZQT__.TTF',10*s,'')
 for _=1,3 do Nexus.RequestRecompute();H.Advance(.4) end
 local layout=Nexus.LayoutMetrics.Panel({width=272,fontScale=s,activeRoll=true})
 check(NexusPanel._rollStatus:GetHeight()==layout.small,'scale '..s..': reached: the final layout pass ran at this scale')
 return layout
end
local function Top(region) local _,_,_,_,y=region:GetPoint(1);return -y end
local function Fit(label,expectButton)
 for _,s in ipairs(SCALES) do
  local layout=Scale(s)
  local btn,head,rec,area=NexusPanel._orbsBtn,NexusPanel._rollStatus,NexusPanel._rollRec,NexusPanel._rollStatus:GetParent()
  local g=(Nexus.Panel._lastModel or {}).orbGuidance or {}
  local tag=label..' @'..s
  check(g.text~=nil,tag..': fixture: guidance text is shown: '..tostring(g.state))
  check(rec:GetText()==g.text,tag..': fixture: the body shows the guidance text')
  check(btn:IsShown()==expectButton,tag..': the button is '..(expectButton and 'shown' or 'hidden'))
  local recBottom=Top(rec)+rec:GetHeight()
  check(Top(rec)>=Top(head)+head:GetHeight(),tag..': the body starts below the heading')
  check(recBottom<=area:GetHeight(),tag..': the body ends inside the roll area')
  for _,m in ipairs(HUD) do
   local char,line=m.char(s),m.line(s)
   local body=Lines(rec:GetText(),rec:GetWidth(),char)
   print('ORB_FIT',tag,m.name,'area',area:GetWidth()..'x'..area:GetHeight(),'body',rec:GetWidth()..'x'..rec:GetHeight(),'lines',body,'needs',body*line,
    'heading',head:GetWidth(),Len(head:GetText())*char,'button',btn:GetWidth()..'x'..btn:GetHeight(),Len(btn:GetText())*char+CAPS)
   check(body*line<=rec:GetHeight(),tag..' '..m.name..': every guidance line fits: '..body..' lines')
   check(Len(head:GetText())*char<=head:GetWidth(),tag..' '..m.name..': the heading fits on one line: '..Plain(head:GetText()))
   if expectButton then
    check(Len(btn:GetText())*char+CAPS<=btn:GetWidth(),tag..' '..m.name..': the button label fits')
    check(line<=btn:GetHeight(),tag..' '..m.name..': the button label is not clipped vertically')
   end
  end
  if expectButton then
   -- Distinct hit targets: the button has its own row, below the body and
   -- above the roll area's bottom edge, and does not cover the heading.
   -- Top edge in roll-area coordinates, from whichever anchor is used.
   local point,rel,_,bx,by=btn:GetPoint(1)
   check(rel==area,tag..': the button is anchored in the roll area')
   local btnTop=point:find('^TOP') and -by or point:find('^BOTTOM') and area:GetHeight()-by-btn:GetHeight()
    or (area:GetHeight()-btn:GetHeight())/2-by
   by=area:GetHeight()-btnTop-btn:GetHeight()
   check(btnTop>=recBottom,tag..': the button is below the guidance text')
   check(btnTop>=Top(head)+head:GetHeight(),tag..': the button is below the heading')
   check(by>=0 and btn:GetWidth()<=area:GetWidth()-4,tag..': the button is inside the roll area')
  end
 end
end

do Boot(idle);Fit('finished',true) end
do Boot(nil);Fit('no Orb service',false) end
do
 Boot(idle,{rolled=79,design={[200020]={version=1,copies=1,rows={{spellId=200020,quality=0,stacks=1,locked=true,sourceRole='locked'}}}}})
 Fit('locks only',false)
end
do
 Boot(idle);H.perks.pendingSelectSpellId=200016;H.Notify()
 for _=1,4 do Nexus.RequestRecompute();H.Advance(.4) end
 Fit('waiting',false)
end
do Boot(stateless);Fit('longest Orb-state reason',true) end

-- An earlier Orb action unresolved after a reload: the Orb runtime's own
-- recovery reason (about 200 characters) is the HUD body, with the button.
-- Real OrbRuntime/OrbAdapter with the synthetic Orb service of
-- orbs_support.lua, as in orb_guidance_passive_open.lua.
do
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 FontDouble()
 H=dofile('tests/prototype/orbs_support.lua')
 H.OrbPlan();H.Approve(2);H.Offer()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.O.offer=false
 H.Fire('PLAYER_LOGOUT')
 NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide()
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 H.Notify();H.A.Poll()
 if not (NexusPanel and NexusPanel:IsShown()) then Nexus.Panel.Show() end
 for _=1,4 do Nexus.RequestRecompute();H.Advance(.4) end
 local g=(Nexus.Panel._lastModel or {}).orbGuidance or {}
 check(g.state=='orb-run' and Len(g.text)>=180,'fixture: the HUD shows the long recovery reason: '..tostring(g.state)..' '..tostring(g.text))
 Fit('Orb-run recovery reason',true)
end

-- The Orb window's status box with the longest overlapping refusal.
do
 CreateFont=nil
 local Ho=(function()
  if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
  Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
  return dofile('tests/prototype/orbs_support.lua')
 end)()
 Ho.OrbPlan()
 Ho.orbs.offer=true
 Ho.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 Ho.perks.pendingSelectSpellId=410002;Ho.Notify();Ho.A.Poll()
 Nexus.OrbPanel.Show()
 local status=NexusOrbPanel.status
 local text=status:GetText()
 check(text:find('no confirmed result',1,true) and text:find('An Orb offer is shown',1,true) and text:find('An Echo choice is shown',1,true),
  'fixture: the longest overlapping refusal is shown: '..text)
 for _,m in ipairs(MODELS) do
  local n=Lines(text,status:GetWidth(),m.char)
  print('ORB_FIT','refusal',m.name,'box',status:GetWidth()..'x'..status:GetHeight(),'lines',n,'needs',n*m.line)
  check(n*m.line<=status:GetHeight(),'refusal '..m.name..': every line of the Orb window status fits: '..n..' lines')
 end
 Ho.perks.pendingSelectSpellId=nil;Ho.Board(nil);Ho.orbs.offer=false;Ho.Notify()
 Nexus.OrbRuntime.Status()
 local text2=NexusOrbPanel.status:GetText()
 for _,m in ipairs(MODELS) do
  local n=Lines(text2,NexusOrbPanel.status:GetWidth(),m.char)
  check(n*m.line<=NexusOrbPanel.status:GetHeight(),'status '..m.name..' after the actions settle also fits')
 end
end

print('PASS orb_guidance_geometry checks='..checks)
