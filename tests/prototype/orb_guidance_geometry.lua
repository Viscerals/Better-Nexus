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
--   Its rows take the height the client measures (LayoutMetrics.WrapHeight),
--   so each model is installed as the measurement (layout_geometry_support
--   UseFont) before the real window lays itself out.
-- The word wrap and the character count are this file's own; they do not
-- call the product's LayoutMetrics.TextRows.
-- Sizes and positions are the real widgets' after real renders and the real
-- final layout pass; texts are the real texts, including the longest
-- Orb-state reason and the longest overlapping refusal. A UI scale multiplies
-- text and frames alike and does not change a fit. The heading is modeled
-- for width only (one line); its line height is the layout's own row, as for
-- every other heading. Native pixel fit is NOT established here.
-- The approved compact panel (design draft "Nexus compact panel": 420
-- reference pixels wide, where the reference panel is 284 units, so one
-- reference pixel is 284/420 of the font scale in units). One assertion of
-- the former geometry is replaced where it stood by the draft's own
-- assertion, not relaxed: the offer heading's row is the draft's 18-pixel
-- row at the scale (Scale). One relation of the former geometry is RETIRED
-- by the owner's ruling recorded by Root (v9, ST8-1) and is no longer
-- asserted: that the collapsed level-80 block is shorter than the ordinary
-- block for the same guidance. It is not replaced by an equivalent; the
-- collapsed block is asked instead for what it must itself be (exactly its
-- guidance or its button, the whole guidance fitting, the button apart and
-- inside, the collapsed state), and the retired comparison's figures are
-- printed as a diagnostic at its original inputs (Fit).
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local SCALES={0.75,1,1.25,1.5,2}
local HUD={
 {name='default',char=function(s) return 0.55*10*s end,line=function(s) return 1.2*10*s end},
 {name='conservative',char=function(s) return math.max(7.0,0.70*10*s) end,line=function(s) return math.max(17,1.2*10*s) end},
}
-- size: the font size a text region reports under the model (the Orb
-- window's font does not follow the Nexus font scale).
local MODELS={{name='default',char=5.5,line=12,size=12},{name='conservative',char=7.0,line=17,size=12}}
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
 if opt.auto~=false then SlashCmdList.NEXUS('auto') end
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
 -- Main-panel visual correction ("Measure actual line height for one-line
 -- text too"): the offer heading's row is the design's row of this scale or,
 -- where the client measures the heading's own line taller, that line. The
 -- harness measures every text as one 14-unit line (as stated below for the
 -- Orb window), so here the row is the taller of the two. The collapsed
 -- block lays out no heading row and keeps the small row. The proof that the
 -- final layout pass ran at this scale is read from the applied layout's own
 -- small row, which only this scale gives (9, 11, 14, 17 and 22 units), and
 -- the heading's height is checked against what this scale and the measured
 -- line require.
 -- The approved compact panel: the design's row is the draft's 18 reference
 -- pixels, 18 x 284/420 x the scale (9.1, 12.2, 15.2, 18.3 and 24.3 units),
 -- laid on whole units: the block's top and the row's end are each rounded
 -- to a unit, so the row is that length's whole part or one unit more. With
 -- the 14-unit line that is 14 units at 0.75 and 1.0, then 15 or 16, 18 or
 -- 19, and 24 or 25. EXPECT: the check that stood here took the small row of
 -- the scale for the design's row (14 units at 0.75, 1.0 and 1.25, then 17
 -- and 22).
 local laid=NexusPanel._responsiveLayout or {}
 local head=NexusPanel._rollStatus
 local LINE=14
 local ROW=18*284/420*s
 check(laid.noOffer or math.ceil(head:GetStringHeight() or 0)==LINE,
  'scale '..s..': fixture: the harness measures the shown heading as one '..LINE..'-unit line: '..tostring(head:GetStringHeight()))
 local row=head:GetHeight()
 local drawn=row==math.max(LINE,math.floor(ROW)) or row==math.max(LINE,math.ceil(ROW))
 check(laid.small==layout.small and ((laid.noOffer and row==layout.small) or (not laid.noOffer and drawn)),
  'scale '..s..': reached: the final layout pass ran at this scale (applied small row '..tostring(laid.small)..' of '..layout.small
  ..', heading row '..tostring(row)..' for the draft\'s '..string.format('%.1f',ROW)..' units)')
 return layout
end
local function Top(region) local _,_,_,_,y=region:GetPoint(1);return -y end
local function Fit(label,expectButton,withCards)
 for _,s in ipairs(SCALES) do
  local layout=Scale(s)
  local btn,head,rec,area=NexusPanel._orbsBtn,NexusPanel._rollStatus,NexusPanel._rollRec,NexusPanel._rollStatus:GetParent()
  local g=(Nexus.Panel._lastModel or {}).orbGuidance or {}
  local tag=label..' @'..s
  check(g.text~=nil,tag..': fixture: guidance text is shown: '..tostring(g.state))
  local m0=Nexus.Panel._lastModel or {}
  if withCards then
   check(#(m0.cards or {})>0 and rec:GetText()==m0.recommendation,tag..': fixture: cards, and the body shows the recommendation')
  else
   check(rec:GetText()==g.text,tag..': fixture: the body shows the guidance text')
  end
  check(btn:IsShown()==expectButton,tag..': the button is '..(expectButton and 'shown' or 'hidden'))
  -- design/current "Nexus Main Panel - Compact Redesign" (level 80, normal
  -- rolls finished, no offer): the roll block collapses to the guidance with
  -- Open Orbs... inline at its right; no heading, no 104 px minimum and no
  -- separate button row. Every other guidance keeps the full block below.
  local finished=g.state=='finished' or g.state=='finished-no-orbs' or g.state=='finished-unknown'
  local laid=NexusPanel._responsiveLayout or {}
  check((laid.noOffer==true)==(finished and not withCards),tag..': collapsed exactly for a finished run without an offer: '..tostring(g.state))
  if laid.noOffer then
   check(not head:IsShown(),tag..': the collapsed block has no heading row')
   -- Scale-aware collapse. The requirement is that no unused offer space is
   -- reserved, not a pixel bound: at large text the guidance wrapped beside
   -- the inline button legitimately needs more than 104 px. The block is no
   -- taller than its own content in the conservative model (this file's
   -- word wrap at the body's real width, or the inline button when taller,
   -- plus the layout gap).
   -- RETIRED by the owner's ruling recorded by Root (v9, ST8-1), for the
   -- compact Main collapsed level-80 guidance only: the strict relation that
   -- stood here at eef1608f, "the collapsed block is shorter than the
   -- ordinary block for the same guidance at this scale"
   -- (check(area:GetHeight()<ordinary) against LayoutMetrics.Panel at width
   -- 420 with the guidance wrapped at the 248-unit ordinary body). In the
   -- approved compact presentation readability and the block's natural
   -- measured height come first, and the block is not always shorter than
   -- the different ordinary presentation: beside its inline button the
   -- guidance wraps to more rows than across the block's whole width. The
   -- relation is NOT asserted here any more and is not protected by this
   -- file. The comparison v6 to v8 put in its place (the ordinary block of
   -- this panel's width holding the collapsed body's own row count) could
   -- not fail beside the exact-height check below, protected nothing, and is
   -- removed, not kept.
   -- What is asserted is what the collapsed block itself must be, each from
   -- the real widgets and this file's own word wrap:
   --  - required height: the block is exactly its guidance's rows in the
   --    conservative model, or its inline button when that is taller (no
   --    heading row, no gap and no button row are laid out in it), and so
   --    reserves nothing beyond its content;
   --  - the full guidance fits: every line of it, in both font models, in
   --    the body's real width and height, and the body is inside the block;
   --  - the button: its label fits, it stands inline at the block's top
   --    right, right of the guidance and apart from it, inside the block,
   --    and the body and the button share the block's width with the layout
   --    gap between them;
   --  - state and visibility: collapsed exactly for a finished run without
   --    an offer, no heading row, the button shown or hidden as the state
   --    says, and no mini-panel control.
   -- DIAGNOSTIC ONLY, printed and never asserted, at the same five scales:
   -- 'original' is the ordinary block at the original inputs of the retired
   -- relation, unchanged (width 420, the guidance wrapped at the 248-unit
   -- body), as today's layout engine lays it out; 'own wrap' is the ordinary
   -- block at this panel's width with the guidance wrapped across the
   -- block's own width. Neither is a pass or a fail.
   local cchar,cline=HUD[2].char(s),HUD[2].line(s)
   local rows=Lines(rec:GetText(),rec:GetWidth(),cchar)
   local need=math.max(rows*cline,laid.orbButtonH or 0)+laid.gap
   local original=Nexus.LayoutMetrics.Panel({width=420,fontScale=s,activeRoll=true,orbButton=btn:IsShown(),
    guidanceRows=Lines(rec:GetText(),248,cchar)}).boxes.roll.h
   local own=Nexus.LayoutMetrics.Panel({width=NexusPanel:GetWidth(),fontScale=s,activeRoll=true,orbButton=btn:IsShown(),
    guidanceRows=Lines(rec:GetText(),area:GetWidth(),cchar)}).boxes.roll.h
   print('ORB_FIT',tag,'collapsed','area',area:GetWidth()..'x'..area:GetHeight(),'body',rec:GetWidth()..'x'..rec:GetHeight(),
    'rows',rows,'needs',need)
   print('ORB_FIT_DIAGNOSTIC',tag,'retired relation, not asserted: collapsed',area:GetHeight(),
    'ordinary at the original inputs (width 420, 248-unit body)',original,'ordinary at this width, own wrap',own)
   check(area:GetHeight()<=need,tag..': the collapsed block reserves nothing beyond its content: '..area:GetHeight()..' <= '..need)
   check(math.abs(area:GetHeight()-math.max(rows*cline,laid.orbButtonH or 0))<1e-6,
    tag..': the collapsed block is exactly its guidance or its inline button: '..area:GetHeight()..' = '
    ..math.max(rows*cline,laid.orbButtonH or 0))
   check(Top(rec)>=0 and Top(rec)+rec:GetHeight()<=area:GetHeight(),tag..': the body is inside the collapsed block')
   -- (The body and the inline button share the block's width: the body is
   -- the block less the button and the layout gap, or the whole block
   -- without a button.)
   check(rec:GetWidth()==area:GetWidth()-(expectButton and (btn:GetWidth()+laid.gap) or 0),
    tag..': the guidance body has the block\'s width less the inline button and the layout gap: '..rec:GetWidth()..' of '..area:GetWidth())
   for _,m in ipairs(HUD) do
    local char,line=m.char(s),m.line(s)
    local body=Lines(rec:GetText(),rec:GetWidth(),char)
    check(body*line<=rec:GetHeight(),tag..' '..m.name..': every guidance line fits the collapsed body: '..body..' lines')
    if expectButton then
     check(Len(btn:GetText())*char+CAPS<=btn:GetWidth(),tag..' '..m.name..': the inline button label fits')
     check(line<=btn:GetHeight(),tag..' '..m.name..': the inline button label is not clipped vertically')
    end
   end
   if expectButton then
    local point,rel,_,bx,by=btn:GetPoint(1)
    local _,_,_,rx=rec:GetPoint(1)
    check(rel==area and point=='TOPRIGHT',tag..': the button is anchored inline at the block\'s top right')
    check(area:GetWidth()+bx-btn:GetWidth()>=(rx or 0)+rec:GetWidth(),tag..': the button sits right of the guidance text, apart from it')
    check(-by+btn:GetHeight()<=area:GetHeight() and btn:GetWidth()<=area:GetWidth()-4,tag..': the button is inside the block')
    check(not (NexusPanel._orbMiniBtn and NexusPanel._orbMiniBtn:IsShown()),tag..': the collapsed row keeps one action (the mini panel stays in the Orb window)')
   end
  else
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
-- The Orb-state pause with a board shown: cards, the pause reason as the
-- recommendation body, the button, and the heading (Auto OFF: the
-- preview/active heading; Auto ON: "Auto ON — paused").
for _,auto in ipairs({false,true}) do
 Boot(stateless,{auto=auto,rolled=40})
 H.Board({{spellId=200016,quality=0},{spellId=200015,quality=0},{spellId=200014,quality=0}});H.Notify()
 for _=1,6 do Nexus.RequestRecompute();H.Advance(.4) end
 check(((Nexus.Panel._lastModel or {}).orbGuidance or {}).state=='orb-state','fixture: the Orb-state guidance with a board')
 Fit('Orb-state with cards, Auto '..(auto and 'ON' or 'OFF'),true,true)
end

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

-- The Orb window's status box with the longest overlapping refusal, then the
-- same box after the offer and the choice settle. The harness measures every
-- text as one 14-unit line; for each model its measurement is installed and
-- the real window refreshed before the rows are read.
do
 CreateFont=nil
 local Ho=(function()
  if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
  Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
  return dofile('tests/prototype/orbs_support.lua')
 end)()
 -- After the harness load: the support reaches this harness's region methods.
 local G=dofile('tests/prototype/layout_geometry_support.lua')
 Ho.OrbPlan()
 Ho.orbs.offer=true
 Ho.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 Ho.perks.pendingSelectSpellId=410002;Ho.Notify();Ho.A.Poll()
 local actions,sent=#Ho.actions,#Ho.sent
 Nexus.OrbPanel.Show()
 local f=NexusOrbPanel
 check(f:IsShown() and Nexus.OrbPanel.Page()=='run','fixture: the Orb window shows its run page')
 local function Status(label,fixture)
  for _,m in ipairs(MODELS) do
   G.UseFont(m);Nexus.OrbPanel.Refresh()
   local status=f.status
   local text=status:GetText() or ''
   fixture(text,label..' '..m.name)
   local n=Lines(text,status:GetWidth(),m.char)
   print('ORB_FIT',label,m.name,'box',status:GetWidth()..'x'..status:GetHeight(),'lines',n,'needs',n*m.line)
   check(status:GetWidth()==580,label..' '..m.name..': the status keeps its 580-unit width')
   check(n*m.line<=status:GetHeight(),label..' '..m.name..': every line of the Orb window status fits: '..n..' lines')
   -- Inside the window, below the usage line and above the rows after it.
   local box={0,0,f:GetWidth(),f:GetHeight()}
   local st,usage,close=G.Rect(status,f),G.Rect(f.usage,f),G.Rect(f.closeNotice,f)
   check(G.Inside(st,box) and usage[4]<=st[2] and st[4]<=close[2],
    label..' '..m.name..': the status '..G.Text(st)..' is inside the window, below the usage and above the close notice')
   if (f.notice:GetText() or '')~='' then
    local nt=G.Rect(f.notice,f)
    check(st[4]<=nt[2] and nt[4]<=close[2],label..' '..m.name..': the notice follows the status, apart from it')
   end
  end
 end
 Status('refusal',function(text,tag)
  check(text:find('no confirmed result',1,true) and text:find('An Orb offer is shown',1,true) and text:find('An Echo choice is shown',1,true),
   'fixture: '..tag..': the longest overlapping refusal is shown: '..text)
 end)
 Ho.perks.pendingSelectSpellId=nil;Ho.Board(nil);Ho.orbs.offer=false;Ho.Notify();Ho.A.Poll()
 Status('settled',function(text,tag)
  check(text~='' and not text:find('An Orb offer is shown',1,true) and not text:find('An Echo choice is shown',1,true),
   tag..': after the actions settle the status no longer reports them: '..text)
 end)
 check(#Ho.actions==actions and #Ho.sent==sent and (Ho.orbs.spends or 0)==0,
  'showing and refreshing the Orb window takes no game action, sends nothing and spends no Orb')
end

print('PASS orb_guidance_geometry checks='..checks)
