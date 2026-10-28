-- Help entry points of the setup surfaces (design/current "Nexus Setup
-- Alternative": Help and Setup open the coach; the long manual moves to a
-- separately named, optional Reference). Codex review4: the setup window (the
-- Welcome and its informational replay) and the setup checklist still offered
-- Help that opened the dense manual directly (Help.Show("start")). Each now
-- offers Help as the guided setup coach through Help's guarded route
-- (Help.OpenGuide, as the Options menu and /nexus help take it) and the
-- manual under its own name, Reference. While an Auto warning waits for its
-- answer the coach does not open and says why; Help then answers with the
-- read-only Reference. The coach's own manual links and chat say Reference
-- or /nexus help, not Help.
-- Categories (view_regression_support): EXPECT is behaviour added by this
-- change (predicted from source to fail on the review3 cut, where these Help
-- buttons call Help.Show("start"); not executed by the author). GUARD is
-- navigation-only, no-write behaviour that already held. SETUP is the fixture.
-- Real TOC boot (format-5 saved data, first use already seen, the first-launch
-- warning answered), real windows and real buttons. Spies only count calls at
-- the GuidedSetupUI.Show and Help.Show boundaries and are restored at once.
-- Geometry is the harness text model (layout_geometry_support, plus the 125%
-- model of guided_setup_flow F5), not native glyphs, scale or hit testing:
-- native NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('setup_help_entry_points')

local H=F.Boot(F.Database({mutate=function(db) db.hasSeenQuickStart=true end}))
C.setup(Nexus.StartupStatus().coreReady==true and Nexus.OverwriteWarning.EnsureOnboarding()=='accepted'
 and not Nexus.OverwriteWarning.IsOpen(),'fixture: start-up is ready and the first-launch warning is answered')

local MODEL125={name='125%',char=8.75,line=15,size=15}
local MODELS={G.MODELS.default,G.MODELS.px16,G.MODELS.small,MODEL125,G.MODELS.double}
local KEYS,methods,saved0={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'},G.RegionMethods(),{}
for _,k in ipairs(KEYS) do saved0[k]=rawget(methods,k) end
local function RestoreFont() for _,k in ipairs(KEYS) do methods[k]=saved0[k] end;G.model=nil end

local function Saved() return F.Serialize(NexusDB) end
local function Effects()
 return 'actions='..#H.actions..' sent='..#H.sent..' auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)
end
-- Counts calls of owner[key] while body runs; the stand-in returns true and
-- opens nothing. Restored at once, also when body raises.
local function Spy(owner,key,body)
 local real=owner[key]
 local spy={n=0}
 owner[key]=function(...) spy.n=spy.n+1;spy.args={n=select('#',...),...};return true end
 local ok,err=pcall(body)
 owner[key]=real
 assert(ok,err)
 return spy
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
-- GuidedSetupUI.Show refusing as while an Auto warning waits for its answer.
local function Refusing(body)
 local ui=Nexus.GuidedSetupUI
 local real=ui.Show
 ui.Show=function() return false,'warning-open' end
 local ok,err=pcall(body)
 ui.Show=real
 assert(ok,err)
end
local function Welcome() return _G.NexusQuickStart end
local function WelcomeShown() local w=Welcome();return w~=nil and w:IsShown() end
local function CoachShown() return _G.NexusGuidedSetup~=nil and NexusGuidedSetup:IsShown() end
local function ManualShown() return _G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown() end
local function Caption(w,text)
 for _,c in ipairs(w and w.children or {}) do
  if c.kind=='Button' and V.Plain(c:GetText() or '')==text then return c end
 end
end
local function Captions(w)
 local out={}
 for _,c in ipairs(w and w.children or {}) do if c.kind=='Button' then out[#out+1]=V.Plain(c:GetText() or '') end end
 return table.concat(out,' | ')
end
-- Plain hides only: a hidden Welcome is not visible, so its Escape child
-- finishes nothing and nothing is recorded.
local function Reset()
 if Nexus.GuidedSetupUI then Nexus.GuidedSetupUI.Hide() end
 if _G.NexusHelpWindow then NexusHelpWindow:Hide() end
 if _G.NexusQuickStart then NexusQuickStart:Hide() end
 Nexus.QuickStart.HideChecklist()
end

local PRESENTATIONS={
 {name='the informational replay (Setup information)',open=function() return Nexus.QuickStart.ShowSetup()==true and WelcomeShown() end},
 {name='the deliberate Welcome (QuickStart.Show)',open=function() Nexus.QuickStart.Show();return WelcomeShown() end},
}

for index,p in ipairs(PRESENTATIONS) do
 C.scenario('W'..index..' '..p.name..': Help opens the coach, Reference the manual',function()
  local tag='W'..index
  Reset()
  if not C.setup(p.open(),tag..': fixture: the setup window is shown') then return end
  local w=Welcome()
  local help,reference=Caption(w,'Help: Guided setup'),Caption(w,'Reference')
  C.expect(help~=nil and reference~=nil,tag..': it offers Help: Guided setup and Reference',Captions(w))
  C.expect(Caption(w,'Help / Getting Started')==nil and Caption(w,'Guided setup (step by step)')==nil,
   tag..': no button opens the manual under the generic Help label, and the coach has one entry',Captions(w))
  if not (help and reference) then return end
  -- The coach entry stays the prominent full row; Reference is a half-row entry.
  C.expect(help:GetWidth()>=w:GetWidth()-48 and help:GetWidth()>2*reference:GetWidth(),
   tag..': Help is the full-width row, more prominent than Reference',help:GetWidth()..' / '..reference:GetWidth()..' in '..w:GetWidth())
  local before,saved=Effects(),Saved()

  local manual
  local coach=Spy(Nexus.GuidedSetupUI,'Show',function()
   manual=Spy(Nexus.Help,'Show',function() help:Click() end)
  end)
  C.expect(coach.n==1 and manual.n==0,tag..': Help opens the guided setup coach (GuidedSetupUI.Show), not the manual (Help.Show)',
   'coach='..coach.n..' manual='..manual.n)
  C.expect(not WelcomeShown(),tag..': Help takes the setup window\'s place')

  Reset();p.open()
  help:Click()
  C.expect(CoachShown() and not ManualShown() and not WelcomeShown(),tag..': the real coach is shown at its current step, the manual is not')
  Reset()

  p.open()
  coach=Spy(Nexus.GuidedSetupUI,'Show',function()
   manual=Spy(Nexus.Help,'Show',function() reference:Click() end)
  end)
  C.expect(manual.n==1 and manual.args[1]=='start' and coach.n==0,
   tag..': Reference opens the manual at its first page (Help.Show("start")) and not the coach',
   'manual='..manual.n..' page='..tostring(manual.args and manual.args[1])..' coach='..coach.n)
  Reset()

  -- The warning-open refusal and fallback contract of the Options menu and
  -- /nexus help: the coach says why and the read-only Reference answers.
  p.open()
  local fallback,said
  Refusing(function()
   said=Heard(function() fallback=Spy(Nexus.Help,'Show',function() help:Click() end) end)
  end)
  C.expect(fallback.n==1 and fallback.args[1]=='start' and said:find('Answer the open warning',1,true)~=nil and not CoachShown(),
   tag..': while an Auto warning waits, Help says why and opens the Reference instead of the coach',
   'reference='..fallback.n..' said='..said)
  Reset()
  C.guard(Effects()==before and Saved()==saved,tag..': every route only navigates: no action, send, saved change or Auto change',
   before..' -> '..Effects())
 end)
end

C.scenario('K1 the setup checklist: Help opens the coach in its place, Reference the manual above it',function()
 Reset()
 local f=Nexus.QuickStart.ShowChecklist()
 C.setup(f~=nil and f:IsShown(),'K1: fixture: the checklist is shown')
 C.expect(f.help~=nil and V.Plain(f.help:GetText() or '')=='Help' and f.reference~=nil and V.Plain(f.reference:GetText() or '')=='Reference',
  'K1: the checklist offers Help and Reference')
 if not (f.help and f.reference) then return end
 local before,saved=Effects(),Saved()

 local manual
 local coach=Spy(Nexus.GuidedSetupUI,'Show',function()
  manual=Spy(Nexus.Help,'Show',function() f.help:Click() end)
 end)
 C.expect(coach.n==1 and manual.n==0 and not f:IsShown(),
  'K1: Help opens the guided setup coach in place of the checklist, not the manual','coach='..coach.n..' manual='..manual.n)

 f=Nexus.QuickStart.ShowChecklist()
 coach=Spy(Nexus.GuidedSetupUI,'Show',function()
  manual=Spy(Nexus.Help,'Show',function() f.reference:Click() end)
 end)
 C.expect(manual.n==1 and manual.args[1]=='start' and coach.n==0 and f:IsShown(),
  'K1: Reference opens the manual at its first page above the checklist, which stays',
  'manual='..manual.n..' coach='..coach.n)

 local fallback
 Refusing(function() fallback=Spy(Nexus.Help,'Show',function() f.help:Click() end) end)
 local notice=V.Plain(f.notice:GetText() or '')
 C.expect(f:IsShown() and notice:find('Answer the open warning',1,true)~=nil and fallback.n==1 and fallback.args[1]=='start',
  'K1: while an Auto warning waits, the checklist shows why and Help opens the Reference instead',notice)

 -- Without Help's route the reason is shown in the window and nothing raises.
 local help=Nexus.Help
 Nexus.Help=nil
 local ok=pcall(function() f.help:Click() end)
 Nexus.Help=help
 notice=V.Plain(f.notice:GetText() or '')
 C.guard(ok and f:IsShown() and notice=='Guided setup is not available. Nothing was opened.',
  'K1: without Help\'s route, Help says so in the checklist and opens nothing',notice)
 Reset()
 C.guard(Effects()==before and Saved()==saved,'K1: every route only navigates: no action, send, saved change or Auto change',
  before..' -> '..Effects())
end)

C.scenario('T1 the coach and the setup window point at Reference for the manual and at /nexus help for the coach',function()
 local guide=Nexus.UserText and Nexus.UserText.Guide or {}
 local sharing
 for _,l in ipairs(guide.finish and guide.finish.lessons or {}) do if l.id=='sharing' then sharing=l end end
 local lines=sharing and table.concat(sharing.lines or {},' ') or ''
 C.expect(sharing~=nil and sharing.open=='Open Reference: Sharing' and lines:find('Reference',1,true)~=nil
  and not lines:find('Help',1,true),'T1: the sharing lesson calls the manual page Reference, not Help',
  tostring(sharing and sharing.open)..' | '..lines)
 local chat=guide.chat or {}
 for _,key in ipairs({'reopen','reopenSession'}) do
  local text=tostring(chat[key] or '')
  C.expect(text:find('/nexus help',1,true)~=nil and not text:find('Help:',1,true),
   'T1: the coach\'s '..key..' chat line names /nexus help, not the manual\'s Help window',text)
 end
 Reset()
 Nexus.QuickStart.ShowSetup()
 local sync=V.Plain(Welcome() and Welcome().sync and Welcome().sync:GetText() or '')
 C.expect(sync:find('Reference: Sharing lists what is sent.',1,true)~=nil and not sync:find('Help:',1,true),
  'T1: the setup window\'s Sync line points at the Reference Sharing page',sync)
 Reset()
end)

-- Geometry under each declared text model, the 125% model and a 420 px
-- window: the two entries hold their whole labels, lie inside the window
-- border and overlap no other control or text block.
local function Labelled(button,m)
 return G.Length(V.Plain(button:GetText() or ''))*m.char+24<=button:GetWidth()
end
C.scenario('G1 the setup window keeps both Help entries readable and clear at 420 px under every text model',function()
 local ok,err=pcall(function()
  for _,m in ipairs(MODELS) do
   G.UseFont(m)
   Reset()
   local shown=Nexus.QuickStart.ShowSetup()
   local w=Welcome()
   local tag='G1 '..m.name
   if C.setup(shown==true and w~=nil and w:IsShown(),tag..': fixture: the setup window is shown') then
    local W,Ht=w:GetWidth(),w:GetHeight()
    local border={11,12,W-12,Ht-11}
    for _,caption in ipairs({'Help: Guided setup','Reference'}) do
     local b=Caption(w,caption)
     C.expect(b~=nil,tag..': '..caption..' is offered')
     if b then
      local r=G.Rect(b,w)
      C.expect(Labelled(b,m),tag..': the whole "'..caption..'" fits its button width',tostring(b:GetWidth()))
      C.expect(G.Inside(r,border),tag..': '..caption..' lies inside the window border',G.Text(r)..' in '..W..'x'..Ht)
      local clear=true
      for _,o in ipairs(w.children or {}) do
       local region=o~=b and o:IsShown() and (o.kind=='Button' or o==w.body or o==w.hint or o==w.sync)
       if region and not G.Apart(r,G.Rect(o,w)) then clear=false end
      end
      C.expect(clear,tag..': '..caption..' overlaps no other control or text block',G.Text(r))
     end
    end
    C.guard(W<=1024 and Ht/2+55<=384,tag..': the window still fits the smallest UI at its offset',W..'x'..Ht)
   end
  end
 end)
 RestoreFont();Reset()
 assert(ok,err)
end)

C.scenario('G2 the setup checklist keeps Reference readable and clear under every text model',function()
 local ok,err=pcall(function()
  for _,m in ipairs(MODELS) do
   G.UseFont(m)
   Reset()
   local f=Nexus.QuickStart.ShowChecklist()
   Nexus.QuickStart.RefreshChecklist()
   local tag='G2 '..m.name
   local ref=f and f.reference
   C.expect(ref~=nil,tag..': the checklist offers Reference')
   if ref then
    local W,Ht=f:GetWidth(),f:GetHeight()
    local r=G.Rect(ref,f)
    C.expect(Labelled(ref,m) and ref:GetHeight()==f.help:GetHeight(),
     tag..': Reference holds its whole label width in a button as tall as Help',ref:GetWidth()..'x'..ref:GetHeight())
    C.expect(G.Inside(r,{11,12,W-12,Ht-11}),tag..': Reference lies inside the window border',G.Text(r)..' in '..W..'x'..Ht)
    local blocks={f.subtitle,f.summary,f.statusTitle,f.notice,f.help,f.close,f.assign,f.editor}
    for _,x in ipairs(f.rows or {}) do blocks[#blocks+1]=x end
    for _,x in ipairs(f.status or {}) do blocks[#blocks+1]=x end
    local clear=true
    for _,x in ipairs(blocks) do if x and not G.Apart(r,G.Rect(x,f)) then clear=false end end
    C.expect(clear,tag..': Reference overlaps no text block or button',G.Text(r))
   end
  end
 end)
 RestoreFont();Reset()
 assert(ok,err)
end)

C.guard(Nexus.RecomputeStats().autoEnabled~=true and not Nexus.OverwriteWarning.IsOpen(),'Auto stays OFF and no warning is left open')
C.finish('(setup Help entries open the guarded coach; Reference is the separately named manual; offline model only, native NOT_RUN)')
