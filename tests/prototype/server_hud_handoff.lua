-- The stock Difficulty/Soul Ash widget is only replaced by a replacement.
--
-- Reported symptom: "my panel disappears", on test.9043, with a ready
-- start-up, no incidents and no Lua errors. The saved display preference is
-- the Nexus HUD.
--
-- ui/ServerStatus.lua hides the Project Ebonhold widget when that preference
-- is set. ui/Panel.lua refuses to show NexusPanel until a render has
-- committed. Neither owner asked the other anything, so a replacement that
-- has not committed, has failed, or was never loaded left the player with no
-- HUD at all. Every assertion below names which frame must be on screen and
-- why.
--
-- Part A drives the real modules in the real host. Part B drives the real
-- ServerStatus against a synthetic panel, which is the only way to state what
-- this owner does when the panel reports a FAILED render rather than one that
-- has simply not happened yet.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

----------------------------------------------------------------------------
-- Part B: what ServerStatus does with each answer the panel can give.
----------------------------------------------------------------------------
local function StockFrame()
 local root={shown=true,hideCalls=0,showCalls=0,hooks={}}
 function root:Hide() self.shown=false;self.hideCalls=self.hideCalls+1 end
 function root:Show()
  self.shown=true;self.showCalls=self.showCalls+1
  if self.hooks.OnShow then self.hooks.OnShow(self) end
 end
 function root:IsShown() return self.shown end
 function root:SetAlpha(v) self.alpha=v end
 function root:EnableMouse(v) self.mouse=v end
 -- The client CHAINS hooks: installing twice runs both. Modelling that is
 -- what makes "installed once" a testable claim rather than a hope.
 function root:HookScript(event,fn)
  local previous=self.hooks[event]
  self.hooks[event]=function(...) if previous then previous(...) end return fn(...) end
 end
 function root:GetRegions() return end
 function root:GetChildren() return end
 return root
end

-- A fresh copy of the real module with synthetic globals, in the shape the
-- reporter's own probe used.
local function Host(panel,mode)
 NexusDB={};if mode then NexusDB.soulAshHudMode=mode end
 Nexus={};if panel~=nil then Nexus.Panel=panel end
 UIParent={};EbonholdIntensityData=nil;HardmodeFrame=nil
 local root=StockFrame()
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
 return root,Nexus.ServerStatus,function() scanner.scripts.OnUpdate(scanner,1.0) end
end

local function Panel(facts) return {VisibilityFacts=function() return facts end} end

-- 1. No replacement at all. This is the reporter-supplied probe's exact
-- scenario, and the one that leaves a player with nothing.
do
 local root,status,tick=Host(nil,'nexus')
 tick()
 check(root.shown==true,
  'with no Nexus panel loaded, the stock widget must stay on screen: nothing else can show the difficulty or Soul Ash')
 check(root.hideCalls==0,'and it is not hidden even once')
 check(root.showCalls==0,
  'and it is not forced to show either: the game and the player own it while Nexus cannot replace it')
 root:Show()
 check(root.shown==true,'showing it again is not undone by the mode hook')
 local facts=status.VisibilityFacts()
 check(facts.mode=='nexus','the preference is unchanged: '..tostring(facts.mode))
 check(facts.replacementAvailable==false,'and the absent panel is reported as unavailable')
 check(facts.replacing==false,'so nothing is standing aside for it')
end

-- 2. A replacement that exists but has FAILED to render. The panel keeps
-- itself hidden in that state, so the stock widget must keep its place.
do
 local root,status,tick=Host(Panel({exists=true,shown=false,wanted=true,
  ready=false,committed=false,hadFailure=true,failures=1}),'nexus')
 tick()
 check(root.shown==true,
  'a failed render is not a replacement: the stock widget stays on screen')
 check(root.hideCalls==0,'and is never hidden for it')
 -- The game hides its own widget for its own reasons; Nexus does not undo it.
 root:Hide()
 tick()
 check(root.shown==false and root.showCalls==0,
  'and a widget the game hid is left hidden, not forced back every second')
 check(status.VisibilityFacts().replacing==false,'the state says it is not replacing')
end

-- 3. A replacement that is ready. This is the intended behaviour and must be
-- preserved exactly.
do
 local root,status,tick=Host(Panel({exists=true,shown=true,wanted=true,
  ready=true,committed=true}),'nexus')
 tick()
 check(root.shown==false and root.hideCalls==1,
  'a committed Nexus HUD replaces the stock widget, which is the point of the preference')
 root:Show()
 check(root.shown==false and root.hideCalls==2,
  'and the hook keeps it replaced when something shows it again')
 check(status.VisibilityFacts().replacing==true,'the state says it is replacing')
end

-- 4. Ready, but not on screen right now. A player who hid the Nexus panel,
-- and a dialog that suppresses it, are deliberate states -- NOT a missing
-- replacement -- so the stock widget stays replaced.
do
 local root,_,tick=Host(Panel({exists=true,shown=false,wanted=false,
  ready=true,committed=true}),'nexus')
 tick()
 check(root.shown==false,
  'a panel the player hid themselves is still the replacement; the stock widget does not come back behind their back')
end
do
 local root,_,tick=Host(Panel({exists=true,shown=false,wanted=true,
  menuSuppressed=true,ready=true,committed=true}),'nexus')
 tick()
 check(root.shown==false,
  'a panel suppressed by an open dialog is still the replacement; the stock widget does not flicker in behind it')
end

-- 4b. A replacement that WAS displaying and then fails. We hid the widget for
-- it, so we give it back: leaving it hidden is the no-HUD state this whole
-- correction exists to remove, reached from the other direction.
do
 local ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return ready end}
 local root,status,tick=Host(panel,'nexus')
 tick()
 check(root.shown==false,'fixture: the Nexus HUD is displaying and the widget stood aside')
 -- A committed render fails: the panel owner reports it can no longer display.
 ready={exists=true,shown=false,wanted=true,ready=false,committed=false,
  hadFailure=true,failures=1}
 tick()
 check(root.shown==true,
  'the widget we took away comes back when the replacement stops being able to display')
 check(root.showCalls==1,'and it is given back once, not forced every second')
 tick();tick()
 check(root.showCalls==1,'still once after further scans')
 -- The player closes it themselves: that is theirs to decide, not ours to undo.
 root:Hide()
 tick()
 check(root.shown==false and root.showCalls==1,
  'and once given back it is the player s again: we do not keep re-showing it')
 -- When the replacement recovers, the widget stands aside again.
 ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 tick()
 check(root.shown==false,'a recovered replacement replaces it again')
 check(status.VisibilityFacts().replacing==true,'and the state says so')
end

-- 4c. A widget this module never hid is not "given back" to a state the game
-- did not ask for: only our own hide is undone.
do
 local root,_,tick=Host(Panel({exists=true,shown=false,wanted=true,
  ready=false,committed=false}),'nexus')
 root:Hide()
 local hidden=root.hideCalls
 tick();tick()
 check(root.shown==false and root.showCalls==0 and root.hideCalls==hidden,
  'a widget hidden by the game, while we were never replacing it, is left alone')
end

-- 4d. An owner whose table raises on ANY field read. This runs on a one-second
-- timer, so a read outside the protection would raise once a second forever.
do
 local hostile=setmetatable({},{__index=function() error('hostile panel owner') end})
 local root,status=Host(hostile,'nexus')
 -- The visibility decision and the facts are what this correction owns, and
 -- both must survive a table that raises on every field read.
 local ok,err=pcall(status.Rescan)
 check(ok,'deciding visibility does not raise on a hostile panel owner: '..tostring(err))
 check(root.shown==true,'and the stock widget keeps its place')
 local okFacts,facts=pcall(status.VisibilityFacts)
 check(okFacts and facts.replacementAvailable==false,
  'the facts report it unavailable rather than raising')
 -- Disclosed, and deliberately NOT hardened here: the scanner's summary pass
 -- and SetMode both reach Nexus.Panel.Refresh through a plain field lookup,
 -- which such a table raises on. Those lines predate this correction and
 -- hardening them is outside what this task authorises.
end

-- 5. A panel that cannot answer. An owner that raises is unavailable, not
-- assumed ready: the stock widget keeps its place.
do
 local root,_,tick=Host({VisibilityFacts=function() error('panel owner is broken') end},'nexus')
 tick()
 check(root.shown==true,
  'a panel owner that raises leaves the stock widget on screen rather than hiding it on an assumption')
end

-- 6. A panel from an older build that only reports its own visibility.
do
 local root,_,tick=Host({IsShown=function() return true end},'nexus')
 tick()
 check(root.shown==false,'a panel that is demonstrably on screen is a replacement')
end
do
 local root,_,tick=Host({IsShown=function() return false end},'nexus')
 tick()
 check(root.shown==true,'a panel that is not on screen and cannot say why is not one')
end

-- 7. The explicit preference still wins, whatever the panel says.
do
 local root,status,tick=Host(Panel({exists=true,shown=true,ready=true,committed=true}),'server')
 tick()
 check(root.shown==true and root.hideCalls==0,
  'in server mode the stock widget is the HUD and is shown')
 status.SetMode('nexus')
 check(root.shown==false,'switching to the Nexus HUD replaces it immediately')
 status.SetMode('server')
 check(root.shown==true,'and switching back restores it immediately')
 check(NexusDB.soulAshHudMode=='server','the preference is what was stored')
end

ProjectEbonholdPlayerRunFrame=nil

----------------------------------------------------------------------------
-- Part A: the real modules, the real host, the real lifecycle.
----------------------------------------------------------------------------
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database({}))
check(Nexus.StartupStatus().coreReady==true,'fixture: start-up completed')
check(Nexus.ServerStatus~=nil and Nexus.Panel~=nil,'both owners are loaded')

-- The player's saved preference, as the reporter's profile has it.
check(Nexus.ServerStatus.IsUsingNexusHud()==true,'fixture: the Nexus HUD is the preference')

-- 8. The stock widget appears before the Nexus panel has rendered anything.
-- This is the window the report describes, and the one that used to leave a
-- player with nothing on screen.
local stock=CreateFrame('Frame','ProjectEbonholdPlayerRunFrame',UIParent)
stock:Show()
check(Nexus.Panel.VisibilityFacts().exists==false,
 'fixture: the Nexus panel has not been built yet')
check(Nexus.ServerStatus.Rescan()==true,'the stock widget is detected')
check(stock:IsShown()==true,
 'and it stays on screen, because no Nexus HUD exists yet to replace it')
H.Advance(1.2)
check(Nexus.Panel.VisibilityFacts().ready==true,
 'the Nexus HUD commits a render during ordinary work')
check(stock:IsShown()==false,
 'and only then does the stock widget stand aside for it')
check(#H.actions==0,'no gameplay or server action was taken by any of this')

-- 9. Explicit user hide/show of the replacement.
Nexus.Panel.Hide()
H.Advance(1.2)
check(Nexus.Panel.VisibilityFacts().ready==true,'hiding the panel does not unmake its render')
check(stock:IsShown()==false,
 'so a player who hid the Nexus HUD does not get the stock widget back without asking for it')
Nexus.Panel.Show();H.Advance(.4)
check(stock:IsShown()==false,'and showing it again changes nothing for the stock widget')

-- 10. Dialogs: one, then two, then none.
-- A first-run session really does open the quick-start window, and Panel
-- correctly treats it as an open menu. The player closes it, as they would.
if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then
 _G.NexusQuickStart:Hide();H.Advance(.4)
end
check(Nexus.Panel.VisibilityFacts().menuSuppressed==false,
 'fixture: no Nexus menu is open before the dialog sequence')
check(stock:IsShown()==false,
 'and the stock widget was replaced throughout the quick-start window, because the panel could always display')
-- A client frame is created shown, and a dialog hides itself until it is
-- opened; the hooks only fire on a real transition, so the fixture makes one.
local dialogA=CreateFrame('Frame','NexusHandoffTestDialogA',UIParent)
local dialogB=CreateFrame('Frame','NexusHandoffTestDialogB',UIParent)
dialogA:Hide();dialogB:Hide()
Nexus.Panel.AttachMenuFrame(dialogA)
Nexus.Panel.AttachMenuFrame(dialogB)
dialogA:Show()
check(Nexus.Panel.VisibilityFacts().menuSuppressed==true,'an open dialog suppresses the panel')
H.Advance(1.2)
check(stock:IsShown()==false,
 'while a dialog is open the stock widget stays replaced rather than flickering back in')
-- Dialog churn: a second one opens and the first closes. These fixture
-- frames are not in Panel's own menu list, so this exercises the hooks and
-- the stock widget's stability across them, not that list's membership.
dialogB:Show();dialogA:Hide()
H.Advance(1.2)
check(stock:IsShown()==false,'and it stays replaced across dialogs opening and closing')
dialogB:Hide();H.Advance(.4)
check(Nexus.Panel.VisibilityFacts().menuSuppressed==false,'closing the last dialog releases the panel')
check(stock:IsShown()==false,'the stock widget is still replaced afterwards')

-- 11. The supported preference, through the same setter the More menu uses.
Nexus.ServerStatus.SetMode('server')
check(stock:IsShown()==true,
 'choosing the server HUD brings the original Difficulty/Soul Ash widget straight back')
H.Advance(1.2)
check(stock:IsShown()==true,'and it stays back')
stock:Hide();stock:Show()
check(stock:IsShown()==true,'with no hook hiding it again')
Nexus.ServerStatus.SetMode('nexus')
check(stock:IsShown()==false,'switching back to the Nexus HUD replaces it again')

-- 12. Zone change: the module drops its frame reference and rebinds. A new
-- stock widget appears late and is replaced once the panel is ready, and the
-- OnShow hook is installed once rather than stacked.
for _,frame in ipairs(H.frames or {}) do
 if frame.name=='NexusServerStatusScanner' and frame.scripts.OnEvent then
  frame.scripts.OnEvent(frame,'PLAYER_ENTERING_WORLD')
 end
end
local replacementStock=CreateFrame('Frame','ProjectEbonholdPlayerRunFrame',UIParent)
replacementStock:Show()
H.Advance(1.2)
check(replacementStock:IsShown()==false,
 'a stock widget created after a zone change is replaced too, once the Nexus HUD is ready')
replacementStock:Show()
check(replacementStock:IsShown()==false,'and showing it is undone by the hook')
H.Advance(1.2);replacementStock:Show()
check(replacementStock:IsShown()==false,
 'the hook is installed once, not stacked on every scan')

-- 12b. Mid-render, the panel is NOT a replacement: Render hides its own frame
-- while applying, and a HUD that is halfway through being built cannot be
-- shown to anyone. Observed from inside the real transaction, through the
-- real panel, rather than asserted about it from outside.
do
 -- The transaction hides the panel's own frame while it applies, so that
 -- frame's OnHide runs INSIDE the window. Observed there, through the real
 -- frame, rather than asserted about it from outside.
 local panelFrame=_G.NexusPanel
 check(panelFrame~=nil,'fixture: the real panel frame exists')
 Nexus.Panel.Show();H.Advance(.4)
 check(panelFrame:IsShown()==true,'fixture: it is on screen before the render')
 local seen={}
 panelFrame:HookScript('OnHide',function()
  seen[#seen+1]=Nexus.Panel.VisibilityFacts()
 end)
 Nexus.Panel.Refresh();H.Advance(.4)
 check(#seen>0,'the observation point ran inside a real render transaction')
 local applying=0
 for _,facts in ipairs(seen) do
  if facts.ready==false then applying=applying+1 end
 end
 check(applying>0,
  'a panel part-way through applying a render is not offered as a replacement')
 check(Nexus.Panel.VisibilityFacts().ready==true,
  'and it is one again as soon as that render commits')
 check(stock:IsShown()==false,
  'the stock widget is not given back for that momentary state')
end

-- 13. Passive inspection writes nothing to the profile. The snapshot is
-- taken here, after the deliberate preference changes above: those are
-- writes the player asked for, and this section is about the ones nobody did.
local before=F.Serialize(NexusDB)
local facts=Nexus.ServerStatus.VisibilityFacts()
check(facts.detected==true and facts.replacing==true,'the state is readable')
check(type(Nexus.Panel.VisibilityFacts().hiddenUncommitted)=='number',
 'and so are the panel counters')
H.Advance(1.2)
check(F.Serialize(NexusDB)==before,
 'reading HUD state and running the scanner stores nothing new in the profile')
check(#H.actions==0,'and submits nothing to the server')

-- 14. The report can now say which HUD was on screen. This is the fact the
-- supplied support file did not carry, and without it a report of "my panel
-- disappeared" cannot tell an intended replacement from a missing one.
local function ReportText()
 local builder=Nexus.SupportReport
 local report=assert(builder.Prepare({extended=true},600),'the report is prepared')
 return table.concat(report.chunks or {},'')
end
do
 local text=ReportText()
 check(text:find('-- HUD',1,true)~=nil,'the prepared report has a HUD section')
 check(text:find('preference=nexus',1,true)~=nil,'it names the display preference')
 check(text:find('server widget=present',1,true)~=nil,'and whether the stock widget exists')
 check(text:find('replaced by Nexus=true',1,true)~=nil,
  'and states that it is standing aside for a Nexus HUD that can display')
 check(text:find('Nexus panel=built',1,true)~=nil,'and that the panel is built')
 check(text:find('render committed=true',1,true)~=nil,'and that its render committed')
 check(text:find(F.NAME,1,true)==nil,'without naming the character')
 check(text:find('Ebonhold',1,true)==nil,'or the realm')
end

-- The same report when the replacement cannot display. The panel owner is
-- swapped for one that answers honestly and restored immediately after; this
-- states what the section says in the case that matters, which the real host
-- cannot reach once its panel has committed.
do
 local realPanel=Nexus.Panel
 Nexus.Panel={VisibilityFacts=function()
  return {exists=true,shown=false,wanted=true,menuSuppressed=false,
   ready=false,committed=false,hadFailure=true,hiddenUncommitted=3,
   commits=0,failures=1}
 end}
 local ok,text=pcall(ReportText)
 Nexus.Panel=realPanel
 check(ok,'the report is still prepared when the panel cannot display: '..tostring(text))
 check(text:find('render committed=false',1,true)~=nil,
  'it states that no render has committed')
 check(text:find('failures=1',1,true)~=nil,'with the failure the owner counted')
 check(text:find('NEITHER HUD is on screen',1,true)~=nil,
  'and says plainly that nothing is on screen, because this section reports the widget hidden too')
end

-- The sentence must follow the two facts above it, in each of its three
-- cases. Both owners are swapped for ones that answer exactly, and restored
-- immediately: this states what the report SAYS, which is the thing a
-- supporter acts on.
do
 local realPanel,realStatus=Nexus.Panel,Nexus.ServerStatus
 local stock
 Nexus.Panel={VisibilityFacts=function()
  return {exists=true,shown=false,wanted=true,ready=false,committed=false,
   hiddenUncommitted=1,commits=0,failures=0}
 end}
 Nexus.ServerStatus={VisibilityFacts=function()
  return {mode='nexus',detected=true,stockShown=stock,replacing=false}
 end}
 stock=true
 local kept=ReportText()
 stock=false
 local neither=ReportText()
 stock=nil
 local unknown=ReportText()
 Nexus.Panel,Nexus.ServerStatus=realPanel,realStatus
 check(kept:find('the server widget keeps its place',1,true)~=nil
  and kept:find('NEITHER HUD',1,true)==nil,
  'a visible server widget is reported as keeping its place')
 check(neither:find('NEITHER HUD is on screen',1,true)~=nil,
  'a hidden one is reported as leaving the player with nothing')
 check(unknown:find('not knowable here',1,true)~=nil,
  'and an unknowable one is not guessed at either way')
end

-- An owner that is absent or raises must not take the report away.
do
 local realPanel,realStatus=Nexus.Panel,Nexus.ServerStatus
 Nexus.Panel={VisibilityFacts=function() error('panel owner is broken') end}
 Nexus.ServerStatus=nil
 local ok,text=pcall(ReportText)
 Nexus.Panel,Nexus.ServerStatus=realPanel,realStatus
 check(ok,'a broken HUD owner does not break the report: '..tostring(text))
 check(text:find('-- HUD',1,true)~=nil,'the section is still present')
 check(text:find('not available',1,true)~=nil,'and says plainly that it has nothing')
end

check(F.Serialize(NexusDB)==before,'preparing a report stores nothing in the profile')

-- And not even when the preference has never been stored. Describing a
-- setting must not create it: the first version of this diagnostic asked the
-- owner a question that normalizes and SAVES the default, which turned
-- copying a support report into a profile write.
do
 local savedMode=NexusDB.soulAshHudMode
 NexusDB.soulAshHudMode=nil
 local snapshot=F.Serialize(NexusDB)
 local facts=Nexus.ServerStatus.VisibilityFacts()
 check(facts.mode=='nexus',
  'with no stored preference the Nexus HUD is still reported as the effective one')
 check(NexusDB.soulAshHudMode==nil,'and reading it did not store it')
 ReportText()
 check(F.Serialize(NexusDB)==snapshot,
  'preparing a report with no stored preference writes nothing either')
 NexusDB.soulAshHudMode=savedMode
end

print('PASS server_hud_handoff: the stock HUD is replaced only by a replacement that exists checks='..checks)
