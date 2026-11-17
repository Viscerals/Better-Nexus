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
 -- The client CHAINS hooks: installing twice runs both. Modelling that, and
 -- COUNTING both installs and invocations, is what makes "installed once" a
 -- testable claim rather than a hope.
 root.hookInstalls=0
 root.hookRuns=0
 function root:HookScript(event,fn)
  self.hookInstalls=self.hookInstalls+1
  local previous=self.hooks[event]
  self.hooks[event]=function(...)
   self.hookRuns=self.hookRuns+1
   if previous then previous(...) end
   return fn(...)
  end
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
 -- The fourth value is a world entry (the scanner's own event); callers
 -- that do not need it ignore it.
 return root,Nexus.ServerStatus,function() scanner.scripts.OnUpdate(scanner,1.0) end,
  function() scanner.scripts.OnEvent(scanner,'PLAYER_ENTERING_WORLD') end
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

-- 4. Ready, but not on screen right now. A dialog that suppresses the panel
-- is a passing state, NOT a missing replacement, so the stock widget stays
-- replaced. Issue #164 reverses the earlier rule for a panel the PLAYER hid:
-- that is the player turning the Nexus HUD away, so it replaces nothing and
-- the game's own widget keeps its place (this check used to expect hidden).
do
 local root,_,tick=Host(Panel({exists=true,shown=false,wanted=false,
  ready=true,committed=true}),'nexus')
 tick()
 check(root.shown==true and root.hideCalls==0,
  '#164: a panel the player hid is not a replacement; the stock widget keeps its place and is never hidden for it')
end
do
 local root,_,tick=Host(Panel({exists=true,shown=false,wanted=true,
  menuSuppressed=true,ready=true,committed=true}),'nexus')
 tick()
 check(root.shown==false,
  'a panel suppressed by an open dialog is still the replacement; the stock widget does not flicker in behind it')
end

-- 3b. The hook is installed once, however long the scanner runs. Without the
-- guard the client would chain a new hide handler every second, for ever.
do
 local root,_,tick=Host(Panel({exists=true,shown=true,wanted=true,
  ready=true,committed=true}),'nexus')
 for _=1,25 do tick() end
 check(root.hookInstalls==1,
  'one OnShow hook after twenty-five scans, not one per scan: '..root.hookInstalls)
 root.hookRuns=0
 root:Show()
 check(root.hookRuns==1,
  'and showing the widget runs that hook exactly once: '..root.hookRuns)
 check(root.shown==false,'while still keeping it replaced')
end

-- 4b. A replacement that WAS displaying and then fails. We hid the widget for
-- it, so we give it back: leaving it hidden is the no-HUD state this whole
-- correction exists to remove, reached from the other direction.
do
 local ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return ready end}
 local root,status,tick=Host(panel,'nexus')
 -- Many scans, not one: the replacing branch runs every second, and a module
 -- that re-decides ownership on each pass forgets its own hide a second after
 -- making it. Every give-back case below runs long enough to catch that.
 for _=1,12 do tick() end
 check(root.shown==false,'fixture: the Nexus HUD is displaying and the widget stood aside')
 check(root.showCalls==0,
  'and nothing put it back while the replacement was displaying: '..root.showCalls)
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

-- 4d2. A widget we could not hide is not one we later "give back". Claiming a
-- hide that never happened would let this module show a frame it never took.
do
 local ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return ready end}
 local root,_,tick=Host(panel,'nexus')
 root.Hide=function() error('this widget refuses to hide') end
 tick()
 check(root.shown==true,'fixture: the widget could not be hidden')
 ready={exists=true,shown=false,wanted=true,ready=false,committed=false,hadFailure=true}
 tick()
 check(root.showCalls==0,
  'and a hide that never happened is never given back')
end

-- 4d3. Mid-render the panel is briefly not ready while its committed model
-- still stands. That instant must not hand the widget back and take it away
-- again on the next scan.
do
 local facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return facts end}
 local root,_,tick=Host(panel,'nexus')
 for _=1,5 do tick() end
 check(root.shown==false,'fixture: the widget is replaced')
 -- The panel is applying a render: not ready, but its commit still stands.
 facts={exists=true,shown=false,wanted=true,ready=false,committed=true}
 tick()
 check(root.shown==false and root.showCalls==0,
  'a panel part-way through a render does not hand the widget back for one scan')
 facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 tick()
 check(root.shown==false,'and the widget stays replaced when that render commits')
end

-- 4e. After a zone change the client can hand us a DIFFERENT widget object.
-- One we never hid is not one we give back, even though we are still holding
-- the memory of the one we did hide.
do
 local ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return ready end}
 local root,status,tick=Host(panel,'nexus')
 tick()
 check(root.shown==false,'fixture: the first widget was hidden by us')
 -- A new world, a new widget object, and a replacement that cannot display.
 local replacement=StockFrame()
 replacement:Hide()
 local hiddenBefore=replacement.hideCalls
 ProjectEbonholdPlayerRunFrame=replacement
 ready={exists=true,shown=false,wanted=true,ready=false,committed=false,hadFailure=true}
 status.Rescan()
 check(replacement.showCalls==0,
  'a widget this module never hid is not force-shown on the old one s behalf')
 check(replacement.shown==false and replacement.hideCalls==hiddenBefore,
  'and it is not touched at all')
end

-- 4f. An owner whose FACTS TABLE raises on every field read. The owner
-- answered; what it handed back is the hostile part. Reading it outside the
-- protection is how this hazard came back once already, and it strands the
-- player with no HUD and an error every second.
do
 local ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return ready end}
 local root,status,tick=Host(panel,'nexus')
 for _=1,8 do tick() end
 check(root.shown==false,'fixture: the widget was replaced while the facts were readable')
 panel.VisibilityFacts=function()
  return setmetatable({},{__index=function() error('facts table raises') end})
 end
 local ok,err=pcall(tick)
 check(ok,'a scan survives a facts table that raises on every read: '..tostring(err))
 check(root.shown==true and root.showCalls==1,
  'and the widget we hid is given back, because such an owner cannot be a replacement')
 local okFacts,facts=pcall(status.VisibilityFacts)
 check(okFacts and facts.replacementAvailable==false,
  'the facts report it unavailable rather than raising')
end

-- 4g. A widget that was ALREADY hidden is not claimed as ours, so a later
-- give-back cannot put back something the player closed themselves.
do
 local ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local panel={VisibilityFacts=function() return ready end}
 local root,_,tick=Host(panel,'nexus')
 for _=1,6 do tick() end
 check(root.shown==false,'fixture: we hid it while it was on screen')
 ready={exists=true,shown=false,wanted=true,ready=false,committed=false,hadFailure=true}
 tick()
 check(root.shown==true and root.showCalls==1,'it is given back when the replacement fails')
 -- The player closes it. The replacement recovers, hides an already-hidden
 -- widget, and then fails again.
 root:Hide()
 local closedAt=root.showCalls
 ready={exists=true,shown=true,wanted=true,ready=true,committed=true}
 tick()
 ready={exists=true,shown=false,wanted=true,ready=false,committed=false,hadFailure=true}
 tick()
 check(root.shown==false and root.showCalls==closedAt,
  'and a widget the player had already closed is not pushed back on screen')
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

-- 7b. Issue #164: the player hides and shows a ready Nexus panel. A hidden
-- panel replaces nothing, so the widget this module hid comes back at once
-- (PanelVisibilityChanged, no scan needed), exactly once, with only Show:
-- its alpha, mouse and anchors are the game's and are never written. Showing
-- the panel again replaces it again. Repeated toggles never orphan it.
do
 local facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local root,status,tick=Host({VisibilityFacts=function() return facts end},'nexus')
 for _=1,4 do tick() end
 check(root.shown==false and root.hideCalls==1,'fixture: the ready, wanted panel replaces the widget')
 for round=1,5 do
  facts={exists=true,shown=false,wanted=false,ready=true,committed=true}
  check(status.PanelVisibilityChanged()==true,'the owner reports the widget it decided for')
  check(root.shown==true and root.showCalls==round,
   '#164 round '..round..': hiding the panel gives the widget back at once, once: '..root.showCalls)
  tick();tick()
  check(root.shown==true and root.showCalls==round,
   'and later scans neither hide it nor show it again')
  check(status.VisibilityFacts().replacing==false,'the state says nothing replaces it')
  facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
  status.PanelVisibilityChanged()
  check(root.shown==false and root.hideCalls==round+1,
   'showing the panel replaces the widget again at once')
 end
 check(root.alpha==nil and root.mouse==nil,
  'no alpha or mouse state was ever written to the stock widget: '..tostring(root.alpha)..'/'..tostring(root.mouse))
 check(root.hookInstalls==1,'and one OnShow hook stands across every toggle: '..root.hookInstalls)
end

-- 7c. Issue #164: a mid-render instant of a HIDDEN panel is still hidden: the
-- widget comes back and is not taken away when the render commits.
do
 local facts={exists=true,shown=false,wanted=false,ready=true,committed=true}
 local root,_,tick=Host({VisibilityFacts=function() return facts end},'nexus')
 tick()
 check(root.shown==true and root.hideCalls==0,'fixture: a hidden panel leaves the widget alone')
 facts={exists=true,shown=false,wanted=false,ready=false,committed=true}
 tick()
 facts={exists=true,shown=false,wanted=false,ready=true,committed=true}
 tick()
 check(root.shown==true and root.hideCalls==0 and root.showCalls==0,
  'a hidden panel rendering again never hides the widget and never forces it')
end

-- 7d. Issue #164: mode changes in both panel states. Server mode gives back
-- only the widget this module hid, once; a widget the game hid stays hidden
-- and is not re-shown every second.
do
 local facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local root,status,tick=Host({VisibilityFacts=function() return facts end},'server')
 root:Hide()
 for _=1,5 do tick() end
 check(root.shown==false and root.showCalls==0,
  'in server mode a widget the game hid is left hidden: no recurring Show')
 root:Show()
 -- Visible panel: nexus then server.
 status.SetMode('nexus')
 check(root.shown==false,'visible panel: the Nexus HUD replaces the widget')
 status.SetMode('server')
 check(root.shown==true and root.showCalls==2,'visible panel: the server HUD gives it back once')
 tick();tick()
 check(root.showCalls==2,'and does not force it again')
 -- Hidden panel: nexus then server.
 facts={exists=true,shown=false,wanted=false,ready=true,committed=true}
 status.SetMode('nexus')
 check(root.shown==true,'hidden panel: choosing the Nexus HUD does not take the widget away')
 tick()
 check(root.shown==true and root.hideCalls==2,'and no scan does either: '..root.hideCalls)
 status.SetMode('server')
 check(root.shown==true and root.showCalls==2,'hidden panel: the server HUD leaves a shown widget alone')
 -- Shown again in Nexus mode: replaced again.
 facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 status.SetMode('nexus')
 check(root.shown==false,'showing the panel in Nexus mode replaces the widget again')
end

-- 7e. Issue #164: a game-recreated stock widget while the panel is hidden is
-- left alone; once shown, the panel replaces the new one and gives back the
-- new one, never the old.
do
 local facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 local root,status,tick=Host({VisibilityFacts=function() return facts end},'nexus')
 tick()
 check(root.shown==false,'fixture: the first widget is replaced')
 facts={exists=true,shown=false,wanted=false,ready=true,committed=true}
 status.PanelVisibilityChanged()
 check(root.shown==true,'fixture: hiding the panel gives the first widget back')
 local rebuilt=StockFrame()
 ProjectEbonholdPlayerRunFrame=rebuilt
 status.Rescan();tick()
 check(rebuilt.shown==true and rebuilt.hideCalls==0 and rebuilt.showCalls==0,
  'a rebuilt widget is left exactly as the game made it while the panel is hidden')
 facts={exists=true,shown=true,wanted=true,ready=true,committed=true}
 status.PanelVisibilityChanged()
 check(rebuilt.shown==false,'showing the panel replaces the rebuilt widget')
 local oldShows=root.showCalls
 facts={exists=true,shown=false,wanted=false,ready=true,committed=true}
 status.PanelVisibilityChanged()
 check(rebuilt.shown==true and rebuilt.showCalls==1,'and hiding it gives the rebuilt widget back')
 check(root.showCalls==oldShows,'the old widget object is not touched on its behalf')
end

-- 7f-7k. Issue #164 give-back readback. A Show that returns is not proof the
-- game's widget is on screen: only IsShown reading true ends this module's
-- claim. A no-op, raising or unreadable Show leaves a truthful pending or
-- unknown state, retried only at a lifecycle point (mode change, panel
-- hide/show, rescan, first scan after a world entry), never every second,
-- and the widget is never hidden, moved or written to satisfy the check.
local READY={exists=true,shown=true,wanted=true,ready=true,committed=true}
local HIDDEN={exists=true,shown=false,wanted=false,ready=true,committed=true}
-- A Show that returns normally and changes nothing (another addon's wrapper).
local function NoOpShow(root)
 root.noOps=0
 root.Show=function(self) self.noOps=self.noOps+1 end
end
-- 7f. Attached (Nexus HUD): a no-op Show while the player hides the panel.
do
 local facts=READY
 local root,status,tick,world=Host({VisibilityFacts=function() return facts end},'nexus')
 for _=1,3 do tick() end
 check(root.shown==false and root.hideCalls==1,'fixture: the ready panel replaces the widget')
 local realShow=root.Show
 NoOpShow(root)
 facts=HIDDEN
 status.PanelVisibilityChanged()
 local f=status.VisibilityFacts()
 check(root.noOps==1 and root.shown==false,'7f: hiding the panel asks for the widget once; the no-op Show changed nothing')
 check(f.restore=='pending' and f.hiddenByNexus==true and f.stockShown==false and f.replacing==false,
  '7f: the state is truthful: still hidden by Nexus, give-back pending, not replacing ('..tostring(f.restore)..')')
 for _=1,6 do tick() end
 check(root.noOps==1 and root.hideCalls==1,'7f: scans only read it back; no Show every second and no hide')
 check(status.VisibilityFacts().restore=='pending','7f: still pending after the scans')
 status.Rescan()
 check(root.noOps==2,'7f: a rescan is a lifecycle point and retries the Show once')
 world();tick();tick()
 check(root.noOps==3,'7f: the first scan after a world entry retries once; the next scan does not')
 -- The game shows its own widget later: on screen again, and no longer ours.
 realShow(root)
 local after=status.VisibilityFacts()
 check(root.shown==true and after.restore==nil and after.hiddenByNexus==false,
  '7f: once the widget reads back shown the claim ends')
 local shows=root.showCalls
 tick();tick()
 check(root.showCalls==shows and root.noOps==3 and root.hideCalls==1,'7f: and nothing is forced afterwards')
 root.Show=realShow
 root:Hide()
 tick();tick()
 check(root.shown==false and root.showCalls==shows,'7f: a player hide after that is theirs')
 check(root.noOps==3 and status.VisibilityFacts().hiddenByNexus==false,'7f: and is never claimed or undone')
 check(root.alpha==nil and root.mouse==nil,'7f: no alpha or mouse was written to the widget')
end
-- 7g. A pending give-back is dropped when the panel replaces the widget again.
do
 local facts=READY
 local root,status,tick=Host({VisibilityFacts=function() return facts end},'nexus')
 tick()
 NoOpShow(root)
 facts=HIDDEN;status.PanelVisibilityChanged()
 check(status.VisibilityFacts().restore=='pending','fixture: 7g give-back pending')
 facts=READY;status.PanelVisibilityChanged()
 local f=status.VisibilityFacts()
 check(root.shown==false and root.hideCalls==1 and f.restore==nil and f.hiddenByNexus==true and f.replacing==true,
  '7g: showing the panel again keeps the still-hidden widget replaced, with no extra hide and no pending give-back')
 facts=HIDDEN;status.PanelVisibilityChanged()
 check(root.noOps==2 and status.VisibilityFacts().restore=='pending','7g: the next hide asks again, once')
end
-- 7h. A Show that runs on a widget that cannot report IsShown: unknown, never
-- "restored", and not retried blindly.
do
 local facts=READY
 local root,status,tick=Host({VisibilityFacts=function() return facts end},'nexus')
 tick()
 check(root.shown==false,'fixture: 7h replaced')
 root.IsShown=nil
 facts=HIDDEN;status.PanelVisibilityChanged()
 local f=status.VisibilityFacts()
 check(root.showCalls==1 and f.restore=='unknown' and f.stockShown==nil and f.hiddenByNexus==false,
  '7h: Show ran once; with no readback the give-back is reported unknown and the claim ends ('..tostring(f.restore)..')')
 for _=1,4 do tick() end
 status.Rescan()
 check(root.showCalls==1,'7h: an unknown give-back is not repeated by scans or lifecycle points')
end
-- 7i. A raising Show: pending until a lifecycle retry succeeds.
do
 local facts=READY
 local root,status,tick=Host({VisibilityFacts=function() return facts end},'nexus')
 tick()
 local realShow,raised=root.Show,0
 root.Show=function() raised=raised+1;error('this widget refuses to show') end
 facts=HIDDEN;status.PanelVisibilityChanged()
 check(raised==1 and root.shown==false and status.VisibilityFacts().restore=='pending',
  '7i: a raising Show leaves the widget ours and the give-back pending')
 tick();tick()
 check(raised==1,'7i: and scans do not retry it')
 root.Show=realShow
 status.Rescan()
 local f=status.VisibilityFacts()
 check(root.shown==true and root.showCalls==1 and f.restore==nil and f.hiddenByNexus==false,
  '7i: the lifecycle retry gives it back and the readback confirms it')
end
-- 7j. Detached (server HUD) mode changes with a no-op Show.
do
 local root,status,tick=Host({VisibilityFacts=function() return READY end},'nexus')
 tick()
 NoOpShow(root)
 status.SetMode('server')
 check(root.noOps==1 and root.shown==false and status.VisibilityFacts().restore=='pending'
  and NexusDB.soulAshHudMode=='server','7j: choosing the server HUD asks once; the no-op leaves it pending')
 tick();tick();tick()
 check(root.noOps==1,'7j: no Show every second in server mode')
 status.SetMode('server')
 check(root.noOps==2,'7j: the mode setter is a lifecycle point and retries once')
 status.SetMode('nexus')
 local f=status.VisibilityFacts()
 check(root.hideCalls==1 and f.restore==nil and f.replacing==true and f.hiddenByNexus==true,
  '7j: back to the Nexus HUD the still-hidden widget is replaced without another hide')
end
-- 7k. A prehidden widget, and a reload (a fresh module) over one: never
-- claimed, never shown by Nexus.
for _,start in ipairs({'nexus','server'}) do
 local facts=READY
 local root,status,tick=Host({VisibilityFacts=function() return facts end},start)
 root:Hide()
 local hides=root.hideCalls
 tick();tick()
 facts=HIDDEN;status.PanelVisibilityChanged()
 status.SetMode(start=='nexus' and 'server' or 'nexus');status.SetMode(start)
 tick()
 local f=status.VisibilityFacts()
 check(root.shown==false and root.showCalls==0 and root.hideCalls==hides and f.hiddenByNexus==false and f.restore==nil,
  '7k '..start..': a widget hidden before Nexus (or before a reload) is never claimed, hidden again or shown')
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

-- 9. Explicit user hide/show of the replacement. Issue #164 reverses the
-- earlier rule here: a player who hid the Nexus HUD has turned it away, so the
-- game's own Difficulty/Soul Ash widget comes back with that hide (this check
-- used to expect the widget to stay hidden).
Nexus.Panel.Hide()
check(stock:IsShown()==true,'#164: hiding the Nexus panel gives the stock widget back at once')
H.Advance(1.2)
check(Nexus.Panel.VisibilityFacts().ready==true,'hiding the panel does not unmake its render')
check(stock:IsShown()==true,
 '#164: and a hidden Nexus panel is not a replacement, so the stock widget stays on screen')
Nexus.Panel.Show();H.Advance(.4)
check(stock:IsShown()==false,'showing the Nexus panel again replaces the stock widget again')

-- 10. Dialogs: one, then two, then none.
-- A first-run session really does open the quick-start window. It is not an
-- attached menu: it never hides the panel. The player closes it, as they would.
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

-- 12b. Mid-render, the panel is NOT a replacement: a HUD that is halfway
-- through being built cannot be offered to anyone. Observed from inside the
-- real transaction, through the real panel, rather than asserted about it
-- from outside.
do
 -- A shown panel is no longer hidden while it applies (native test.163012,
 -- native_panel_input_continuity), so the observation point is a step the
 -- transaction itself runs: the context header update inside ApplyCandidate.
 local panelFrame=_G.NexusPanel
 check(panelFrame~=nil,'fixture: the real panel frame exists')
 Nexus.Panel.Show();H.Advance(.4)
 check(panelFrame:IsShown()==true,'fixture: it is on screen before the render')
 local seen={}
 local header=Nexus.Panel.UpdateContextHeader
 Nexus.Panel.UpdateContextHeader=function(...)
  seen[#seen+1]=Nexus.Panel.VisibilityFacts()
  return header(...)
 end
 Nexus.Panel.Refresh();H.Advance(.4)
 Nexus.Panel.UpdateContextHeader=header
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

-- No widget found at all, and no Nexus HUD: that is a no-HUD state too, and
-- the section said nothing about it until it was asked to.
do
 local realPanel,realStatus=Nexus.Panel,Nexus.ServerStatus
 Nexus.Panel={VisibilityFacts=function()
  return {exists=false,shown=false,wanted=true,ready=false,committed=false,
   hiddenUncommitted=0,commits=0,failures=0}
 end}
 Nexus.ServerStatus={VisibilityFacts=function()
  return {mode='nexus',detected=false,stockShown=nil,replacing=false}
 end}
 local ok,text=pcall(ReportText)
 Nexus.Panel,Nexus.ServerStatus=realPanel,realStatus
 check(ok,'the report is prepared with no widget at all: '..tostring(text))
 check(text:find('no server widget was found',1,true)~=nil,
  'and it states that neither HUD is on screen because there is nothing to show')
end

-- The same state with the SERVER HUD preferred. Nothing was found to show and
-- nothing can display instead, which is true whichever HUD the player wants.
do
 local realPanel,realStatus=Nexus.Panel,Nexus.ServerStatus
 Nexus.Panel={VisibilityFacts=function()
  return {exists=false,shown=false,wanted=true,ready=false,committed=false,
   hiddenUncommitted=0,commits=0,failures=0}
 end}
 Nexus.ServerStatus={VisibilityFacts=function()
  return {mode='server',detected=false,stockShown=nil,replacing=false}
 end}
 local ok,text=pcall(ReportText)
 Nexus.Panel,Nexus.ServerStatus=realPanel,realStatus
 check(ok,'the report is prepared in server mode with no widget: '..tostring(text))
 check(text:find('preference=server',1,true)~=nil,'it names the server preference')
 check(text:find('no server widget was found',1,true)~=nil,
  'and says neither HUD is on screen in that mode too')
end

-- A fact table that raises on every read must not take this section away: it
-- is the one section a player with a missing HUD is here to send.
do
 local realPanel=Nexus.Panel
 Nexus.Panel={VisibilityFacts=function()
  return setmetatable({},{__index=function() error('facts table raises') end})
 end}
 local ok,text=pcall(ReportText)
 Nexus.Panel=realPanel
 check(ok,'the report survives a raising facts table: '..tostring(text))
 check(text:find('-- HUD',1,true)~=nil,'the HUD section is still present')
 check(text:find('section hud was unavailable',1,true)==nil,
  'and it was not dropped as unavailable')
 check(text:find('preference=',1,true)~=nil,
  'the owner that did answer is still reported')
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

----------------------------------------------------------------------------
-- Part C: Callboard stock ownership. Each case loads a fresh copy of the
-- real ui/CallboardStatus.lua and drives it only through Init, GetSummary,
-- PublishCoverage and its own scanner event and update, against synthetic
-- stock frames and a synthetic covered Nexus row. Each expectation is a
-- literal alpha, mouse or write count of a stock object. The cases run
-- independently and are reported together. Offline characterization only:
-- none of this is native client evidence.
----------------------------------------------------------------------------
do
 local function StockObject(alpha,mouse,parent)
  local f={alpha=alpha,mouse=mouse,parent=parent,alphaSets=0,mouseSets=0,showHides=0}
  function f:GetAlpha() return self.alpha end
  function f:SetAlpha(v) self.alphaSets=self.alphaSets+1;self.alpha=v end
  function f:IsMouseEnabled() return self.mouse end
  function f:EnableMouse(v) self.mouseSets=self.mouseSets+1;self.mouse=v and true or false end
  function f:GetParent() return self.parent end
  function f:IsShown() return true end
  function f:Show() self.showHides=self.showHides+1 end
  function f:Hide() self.showHides=self.showHides+1 end
  return f
 end
 -- A stock object whose alpha and mouse originals cannot be read. A nil
 -- mouse is the client's "off" answer (1/nil convention): known, and
 -- already the suppressed value, so it is not written either. A wrong type
 -- is a string or a number that is no client boolean; a numeric 1 is the
 -- client's "on" and is a usable original (the 'client 1/nil' case below).
 local function Unreadable(kind,parent)
  local f=StockObject(nil,nil,parent)
  if kind=='nil' then
   f.GetAlpha=function() return nil end
   f.IsMouseEnabled=function() return nil end
  elseif kind=='throws' then
   f.GetAlpha=function() error('alpha getter raises') end
   f.IsMouseEnabled=function() error('mouse getter raises') end
  elseif kind=='missing' then
   f.GetAlpha=nil;f.IsMouseEnabled=nil
  elseif kind=='other number' then
   f.GetAlpha=function() return {} end
   f.IsMouseEnabled=function() return 2 end
  else
   f.GetAlpha=function() return '1' end
   f.IsMouseEnabled=function() return '1' end
  end
  return f
 end
 -- The client widget convention for the mouse: IsMouseEnabled answers 1 or
 -- nil; EnableMouse takes a Lua boolean. Exact build-12340 returns NOT_RUN.
 local function ClientMouse(f)
  f.mouse=f.mouse and 1 or nil
  function f:IsMouseEnabled() return self.mouse end
  function f:EnableMouse(v) self.mouseSets=self.mouseSets+1;if v then self.mouse=1 else self.mouse=nil end end
  return f
 end
 local function Objective(rewards)
  local o={title='Callboard Quest',questId=77,objectiveText='Bring the tome'}
  if rewards then o.normalSoulAshes=1200;o.normalMoney=45000 end
  return o
 end
 -- Synthetic globals in the shape the module reads. The Nexus row is covered
 -- (shown, committed, healthy, same title, 17px rows) until a case changes it.
 local function CallboardHost(o)
  local host={facts={shown=true,committed=true,hadFailure=false},
   objective=o.objective,log={{title='Callboard Quest',id=77}}}
  Nexus={};UIParent={}
  GameTooltip=o.tooltip;hooksecurefunc=nil;EbonAPI=nil
  ObjectiveTrackerFrame=o.root;EbonholdQuestTracker=o.tracker
  ProjectEbonholdQuestTracker=nil;WatchFrame=o.watch
  ProjectEbonholdDB={questTracker={watchedQuests={}}}
  GetTrackedAchievements=nil;GetAchievementInfo=nil;GetNumTrackedAchievements=nil
  GetNumQuestWatches=nil;GetQuestIndexForWatch=nil
  GetNumQuestLeaderBoards=nil;GetQuestLogLeaderBoard=nil
  GetNumQuestLogEntries=function() return #host.log end
  GetQuestLogTitle=function(i)
   local q=host.log[i]
   if q then return q.title,80,nil,nil,nil,nil,q.complete,nil,q.id end
  end
  UnitLevel=function() return 80 end
  ProjectEbonhold={ObjectivesService={GetActiveObjective=function() return host.objective end}}
  local function Row(text)
   local row={text=text}
   function row:IsShown() return host.facts.shown==true end
   function row:GetHeight() return 17 end
   function row:GetText() return self.text end
   return row
  end
  NexusPanel={_callboardTitle=Row('Callboard Quest'),_callboardLine=Row('Bring the tome')}
  Nexus.Panel={VisibilityFacts=function() return host.facts end}
  local scanner
  function CreateFrame(_,name)
   local f={scripts={}}
   function f:RegisterEvent() end
   function f:SetScript(event,fn) self.scripts[event]=fn end
   if name=='NexusCallboardStatusScanner' then scanner=f end
   return f
  end
  dofile('ui/CallboardStatus.lua')
  host.status=Nexus.CallboardStatus
  host.status.Init()
  assert(scanner and scanner.scripts.OnEvent and scanner.scripts.OnUpdate,
   'fixture: the Callboard scanner is created')
  -- The module's own scanner: a quest event, then one update.
  function host.Scan()
   scanner.scripts.OnEvent(scanner,'QUEST_LOG_UPDATE')
   scanner.scripts.OnUpdate(scanner,0.25)
  end
  -- What the Nexus panel does on its own show and hide.
  function host.Cover(shown)
   host.facts.shown=shown
   host.status.PublishCoverage()
  end
  return host
 end
 local failures={}
 local function Case(name,fn)
  local ok,err=pcall(fn)
  if not ok then failures[#failures+1]=name..': '..tostring(err) end
 end

 for _,kind in ipairs({'nil','throws','missing','wrong type','other number'}) do
  Case('unreadable originals ('..kind..')',function()
   local root=Unreadable(kind)
   local bag=Unreadable(kind,root)
   root.rewardBagFrame=bag
   local watch=Unreadable(kind)
   local tracker=StockObject(0.8,true)
   local collapse=StockObject(1,true,tracker)
   tracker.collapse=collapse
   local host=CallboardHost({objective=Objective(true),root=root,tracker=tracker,watch=watch})
   host.Scan()
   check(#host.status.GetSummary().rewards==1,'fixture: the covered objective has a usable reward row')
   check(tracker.alpha==0 and collapse.mouse==false,
    'positive control: the tracker alpha and collapse mouse with known originals are taken over')
   check(root.alphaSets==0 and root.mouseSets==0 and bag.alphaSets==0 and bag.mouseSets==0
    and watch.alphaSets==0,
    'an alpha or mouse whose original cannot be read is never written: '..kind)
   host.Cover(false)
   check(tracker.alpha==0.8 and collapse.mouse==true and tracker.mouseSets==0,
    'the positive control gets its exact alpha and mouse back')
   check(root.alphaSets==0 and root.mouseSets==0 and bag.alphaSets==0 and bag.mouseSets==0
    and watch.alphaSets==0 and root.alpha==nil and root.mouse==nil,
    'and no guessed default is written in their place on restore: '..kind)
  end)
 end

 Case('client 1/nil mouse originals',function()
  -- Review C-01: a mouse that answers 1 is on. The objective root, its
  -- reward bag and the tracker collapse control lose the mouse while the
  -- covered row shows and are given exactly 1 back; a stock mouse that
  -- already answers nil stays the game's and is never written.
  local root=ClientMouse(StockObject(0.35,true))
  local bag=ClientMouse(StockObject(1,true,root))
  root.rewardBagFrame=bag
  local tracker=ClientMouse(StockObject(0.8,false))
  local collapse=ClientMouse(StockObject(1,true,tracker))
  tracker.collapse=collapse
  local host=CallboardHost({objective=Objective(true),root=root,tracker=tracker})
  host.Scan()
  check(root.alpha==0 and bag.alpha==0 and tracker.alpha==0,'fixture: the covered row replaces the stock alpha')
  check(root.mouse==nil and bag.mouse==nil and collapse.mouse==nil
   and root.mouseSets==1 and bag.mouseSets==1 and collapse.mouseSets==1,
   'a numeric 1 mouse original is taken over once on each mouse role')
  check(tracker.mouse==nil and tracker.mouseSets==0,'a mouse already off (nil) is not written')
  host.Scan()
  check(root.mouseSets==1 and bag.mouseSets==1 and collapse.mouseSets==1,'an unchanged pass writes no mouse again')
  host.Cover(false)
  check(root.mouse==1 and bag.mouse==1 and collapse.mouse==1
   and root.mouseSets==2 and bag.mouseSets==2 and collapse.mouseSets==2,
   'hiding the row gives each its exact mouse back, once')
  check(tracker.mouse==nil and tracker.mouseSets==0 and root.alpha==0.35 and tracker.alpha==0.8,
   'the game-owned off mouse and every alpha are as they were')
  host.Scan()
  check(root.mouseSets==2 and bag.mouseSets==2 and collapse.mouseSets==2,'a restored mouse is not written again')
  -- Shown again: the same roles are held again, once each.
  host.Cover(true)
  check(root.mouse==nil and bag.mouse==nil and collapse.mouse==nil
   and root.mouseSets==3 and bag.mouseSets==3 and collapse.mouseSets==3,
   'a reshown row takes each mouse over again, once')
  -- Another addon turns the bag mouse back on while Nexus holds it.
  bag.mouse=1
  host.Scan()
  check(bag.mouse==1 and bag.mouseSets==3,'a held mouse another addon turned on is not taken again by a later pass')
  host.Cover(false)
  check(bag.mouse==1 and bag.mouseSets==3,'nor written on restore: it already reads as its original')
  check(root.mouse==1 and collapse.mouse==1 and root.mouseSets==4 and collapse.mouseSets==4,
   'the other roles are given exactly 1 back')
  check(tracker.mouse==nil and tracker.mouseSets==0,'the game-owned off mouse is still never written')
 end)

 Case('client 0 mouse original is off',function()
  -- IsMouseEnabled answering 0 is read as off, like nil: not written.
  local root=StockObject(0.35,true)
  root.IsMouseEnabled=function() return 0 end
  local host=CallboardHost({objective=Objective(true),root=root})
  host.Scan()
  check(root.alpha==0 and root.mouseSets==0,'an off (0) mouse is not taken over; the alpha still is')
  host.Cover(false)
  check(root.alpha==0.35 and root.mouseSets==0,'and nothing is written for it on restore')
 end)

 -- Another owner changes a held property: its value is kept. Only what still
 -- reads as Nexus's own write (alpha 0, mouse off) is given back. Run with
 -- Lua-boolean and client 1/nil mouse answers.
 for _,convention in ipairs({'lua','native'}) do
  Case('foreign change while held ('..convention..')',function()
   local function Stock(alpha,mouse,parent)
    local f=StockObject(alpha,mouse,parent)
    if convention=='native' then ClientMouse(f) end
    return f
   end
   local ON=convention=='native' and 1 or true
   local OFF=nil
   if convention=='lua' then OFF=false end
   local root=Stock(0.35,true)
   local bag=Stock(1,true,root)
   root.rewardBagFrame=bag
   local tracker=Stock(0.8,true)
   local collapse=Stock(1,true,tracker)
   tracker.collapse=collapse
   local host=CallboardHost({objective=Objective(true),root=root,tracker=tracker})
   host.Scan()
   check(root.alpha==0 and bag.alpha==0 and tracker.alpha==0 and root.mouse==OFF and bag.mouse==OFF
    and collapse.mouse==OFF,'fixture: every role is held')
   -- Another addon sets the root and bag alpha and turns the bag mouse back on.
   root.alpha=0.6;bag.alpha=0.7;bag.mouse=ON
   local sets={root.alphaSets,bag.alphaSets,bag.mouseSets,collapse.mouseSets,tracker.alphaSets,root.mouseSets}
   host.Scan()
   check(root.alpha==0.6 and bag.alpha==0.7 and bag.mouse==ON and root.alphaSets==sets[1]
    and bag.alphaSets==sets[2] and bag.mouseSets==sets[3],
    'a later pass keeps the foreign values and writes nothing over them')
   host.Cover(false)
   check(root.alpha==0.6 and bag.alpha==0.7 and bag.mouse==ON and root.alphaSets==sets[1]
    and bag.alphaSets==sets[2] and bag.mouseSets==sets[3],
    'the restore keeps the foreign values: 0.35 and 1 are not written over them')
   check(tracker.alpha==0.8 and collapse.mouse==ON and root.mouse==ON
    and tracker.alphaSets==sets[5]+1 and collapse.mouseSets==sets[4]+1 and root.mouseSets==sets[6]+1,
    'what still read as Nexus\'s write is given its exact original back, once each')
   -- A later handoff takes the values as they now are and gives those back.
   host.Cover(true)
   check(root.alpha==0 and bag.alpha==0 and bag.mouse==OFF and collapse.mouse==OFF,
    'covered again, every role is held again')
   host.Cover(false)
   check(root.alpha==0.6 and bag.alpha==0.7 and bag.mouse==ON and collapse.mouse==ON and tracker.alpha==0.8,
    'and released, each gets the value it had at that later hold')
   local writes=root.alphaSets+bag.alphaSets+bag.mouseSets+collapse.mouseSets+tracker.alphaSets
   host.Scan()
   check(root.alphaSets+bag.alphaSets+bag.mouseSets+collapse.mouseSets+tracker.alphaSets==writes,
    'nothing given back is written again')
  end)
 end

 Case('unreadable while held, then readable again',function()
  -- A getter that fails at release time is no sign of another owner: the
  -- original is written as before, and the record stays until a getter
  -- confirms it; that later pass writes nothing more.
  local root=StockObject(0.35,true)
  local host=CallboardHost({objective=Objective(true),root=root})
  host.Scan()
  check(root.alpha==0,'fixture: the root alpha is held')
  local getAlpha=root.GetAlpha
  root.GetAlpha=function() error('alpha getter raises') end
  local writes=root.alphaSets
  host.Cover(false)
  check(root.mouse==true,'fixture: the readable mouse is given back')
  check(root.alpha==0.35 and root.alphaSets==writes+1,'an unreadable held alpha still gets its original written')
  root.GetAlpha=getAlpha
  host.status.PublishCoverage()
  check(root.alpha==0.35 and root.alphaSets==writes+1,'a later pass confirms it and writes nothing more')
 end)

 Case('one-shot throwing setters',function()
  local root=StockObject(0.35,true)
  local tracker=StockObject(0.8,true)
  local collapse=StockObject(1,true,tracker)
  tracker.collapse=collapse
  -- The tracker alpha setter refuses its first restore and changes nothing.
  local setAlpha=tracker.SetAlpha
  tracker.SetAlpha=function(self,v)
   if v~=0 and not self.refused then self.refused=true;error('alpha setter raises once') end
   return setAlpha(self,v)
  end
  -- The collapse mouse setter changes the value and then raises, once.
  local enableMouse=collapse.EnableMouse
  collapse.EnableMouse=function(self,v)
   enableMouse(self,v)
   if not self.raised then self.raised=true;error('mouse setter raises after changing') end
  end
  local host=CallboardHost({objective=Objective(true),root=root,tracker=tracker})
  host.Scan()
  check(root.alpha==0 and tracker.alpha==0 and collapse.mouse==false,
   'fixture: the stock trackers are replaced, including the mouse a raising setter changed')
  host.Cover(false)
  check(root.alpha==0.35 and root.mouse==true,'hiding the row restores the objective root at once')
  check(collapse.mouse==true,
   'a mouse changed by a setter that then raised was owned, and is given back')
  check(tracker.alpha==0,'fixture: the tracker restore raised and changed nothing')
  host.status.PublishCoverage()
  check(tracker.alpha==0.8,
   'the failed restore is retried by the next publish, with no replacement on screen, to the exact alpha')
  local writes=tracker.alphaSets
  host.Scan()
  check(tracker.alpha==0.8 and tracker.alphaSets==writes,
   'and once a getter confirms it, a later scan does not write it again')
 end)

 Case('silent setter success with a failed readback',function()
  local root=StockObject(0.35,true)
  local host=CallboardHost({objective=Objective(true),root=root})
  host.Scan()
  check(root.alpha==0 and root.mouse==false,'fixture: the objective root is replaced')
  -- The alpha setter returns normally once and changes nothing.
  local setAlpha=root.SetAlpha
  root.SetAlpha=function(self,v)
   if not self.ignored then self.ignored=true;self.alphaSets=self.alphaSets+1;return end
   return setAlpha(self,v)
  end
  host.Cover(false)
  check(root.mouse==true,'the mouse is restored and confirmed')
  check(root.alpha==0,'fixture: the alpha setter reported success and changed nothing')
  host.Scan()
  check(root.alpha==0.35,
   'a readback that did not confirm the original keeps the record, and a later scan restores the exact alpha')
  local writes=root.alphaSets
  host.Cover(false)
  check(root.alpha==0.35 and root.alphaSets==writes,'and a confirmed alpha is not written again')
 end)

 Case('partial restore',function()
  local root=StockObject(0.35,true)
  local host=CallboardHost({objective=Objective(true),root=root})
  host.Scan()
  check(root.alpha==0 and root.mouse==false,'fixture: alpha and mouse are both held')
  local enableMouse=root.EnableMouse
  root.EnableMouse=function(self,v)
   if v==true and not self.refused then self.refused=true;error('mouse setter raises once') end
   return enableMouse(self,v)
  end
  host.Cover(false)
  check(root.alpha==0.35,'the alpha is restored although the mouse restore raised')
  check(root.mouse==false,'fixture: the mouse restore failed')
  -- The game changes the alpha after Nexus gave it back.
  root.alpha=0.6
  local alphaWrites=root.alphaSets
  host.status.PublishCoverage()
  check(root.mouse==true,'the mouse alone is retried and restored')
  check(root.alpha==0.6 and root.alphaSets==alphaWrites,
   'the alpha restored earlier is not written again by the mouse retry')
 end)

 Case('another watched quest',function()
  local watch=StockObject(0.9,true)
  local root=StockObject(0.35,true,watch)
  local bag=StockObject(1,true,root)
  root.rewardBagFrame=bag
  local tracker=StockObject(0.8,true)
  local collapse=StockObject(1,true,tracker)
  tracker.collapse=collapse
  local host=CallboardHost({objective=Objective(true),root=root,tracker=tracker,watch=watch})
  host.Scan()
  check(root.alpha==0 and bag.alpha==0 and tracker.alpha==0 and collapse.mouse==false
   and watch.alpha==0,'fixture: only the callboard objective is tracked and every stock role is replaced')
  host.log[2]={title='One More Door',id=901}
  ProjectEbonholdDB.questTracker.watchedQuests[901]=true
  host.Scan()
  check(tracker.alpha==0.8 and collapse.mouse==true and watch.alpha==0.9,
   'another watched quest gives the quest tracker, its collapse control and WatchFrame back on that pass')
  check(root.alpha==0 and root.mouse==false and bag.alpha==0 and bag.mouse==false,
   'while the covered objective root and its reward bag stay replaced')
  ProjectEbonholdDB.questTracker.watchedQuests[901]=nil
  host.Scan()
  check(tracker.alpha==0 and collapse.mouse==false and watch.alpha==0,
   'when it is no longer watched the tracker roles are replaced again')
  host.Cover(false)
  check(tracker.alpha==0.8 and collapse.mouse==true and watch.alpha==0.9 and root.alpha==0.35
   and root.mouse==true and bag.alpha==1 and bag.mouse==true,
   'and hiding the row gives every exact original back')
 end)

 Case('shared stock object',function()
  -- The quest tracker and WatchFrame are the objective root itself here.
  local root=StockObject(0.35,true)
  local collapse=StockObject(1,true,root)
  root.collapse=collapse
  local host=CallboardHost({objective=Objective(true),root=root,tracker=root,watch=root})
  host.Scan()
  check(root.alpha==0 and root.mouse==false and collapse.mouse==false,
   'the shared frame and the collapse control of its tracker role are both replaced')
  local alphaWrites,mouseWrites=root.alphaSets,root.mouseSets
  host.log[2]={title='One More Door',id=901}
  ProjectEbonholdDB.questTracker.watchedQuests[901]=true
  host.Scan()
  check(collapse.mouse==true,'another watched quest releases the tracker-only collapse role')
  check(root.alpha==0 and root.mouse==false and root.alphaSets==alphaWrites
   and root.mouseSets==mouseWrites,
   'the objective root role still covers the shared frame: it is neither given back nor taken again')
  host.Cover(false)
  check(root.alpha==0.35 and root.mouse==true,'hiding the row gives its exact original back')
 end)

 Case('replaced stock objects',function()
  local rootA=StockObject(0.35,true)
  local trackerA=StockObject(0.8,true)
  local collapseA=StockObject(1,true,trackerA)
  trackerA.collapse=collapseA
  local host=CallboardHost({objective=Objective(true),root=rootA,tracker=trackerA})
  host.Scan()
  check(rootA.alpha==0 and trackerA.alpha==0 and collapseA.mouse==false,
   'fixture: the first stock objects are replaced')
  -- The game rebuilds the collapse control of the same tracker.
  local collapseB=StockObject(1,true,trackerA)
  trackerA.collapse=collapseB
  host.Scan()
  check(collapseA.mouse==true,'the replaced collapse control gets its own exact mouse back')
  check(collapseB.mouse==false and trackerA.alpha==0,
   'its successor is taken over independently and the tracker stays replaced')
  -- Then the objective root and the tracker themselves are replaced.
  local rootB=StockObject(0.5,true)
  local trackerB=StockObject(0.6,true)
  local collapseC=StockObject(1,true,trackerB)
  trackerB.collapse=collapseC
  ObjectiveTrackerFrame=rootB;EbonholdQuestTracker=trackerB
  host.Scan()
  check(rootA.alpha==0.35 and rootA.mouse==true and trackerA.alpha==0.8 and collapseB.mouse==true,
   'every replaced object gets its exact original back')
  check(rootB.alpha==0 and rootB.mouse==false and trackerB.alpha==0 and collapseC.mouse==false,
   'and every successor is held on its own')
  local writes=rootA.alphaSets+rootA.mouseSets+trackerA.alphaSets+collapseA.mouseSets+collapseB.mouseSets
  host.Cover(false)
  check(rootB.alpha==0.5 and rootB.mouse==true and trackerB.alpha==0.6 and collapseC.mouse==true,
   'hiding the row gives each successor its own original, not its predecessor value')
  check(rootA.alphaSets+rootA.mouseSets+trackerA.alphaSets+collapseA.mouseSets+collapseB.mouseSets==writes,
   'and the predecessors already given back are not written again')
 end)

 Case('reward access without usable reward rows',function()
  local watch=StockObject(1,true)
  local tracker=StockObject(0.8,true,watch)
  local collapse=StockObject(1,true,tracker)
  tracker.collapse=collapse
  local root=StockObject(0.35,true,tracker)
  local bag=StockObject(1,true,root)
  root.rewardBagFrame=bag
  local host=CallboardHost({objective=Objective(false),root=root,tracker=tracker,watch=watch})
  host.Scan()
  local summary=host.status.GetSummary()
  check(summary.observed==true and type(summary.rewards)=='table' and #summary.rewards==0,
   'fixture: the covered objective has no reward rows')
  check(bag.alpha==1 and bag.mouse==true and bag.alphaSets==0 and bag.mouseSets==0,
   'without usable reward rows the stock reward bag keeps its alpha and mouse')
  check(root.alpha==0.35 and root.mouse==true and root.alphaSets==0 and root.mouseSets==0,
   'and so does the objective root that holds it')
  check(tracker.alpha==0.8 and collapse.mouse==true and watch.alpha==1 and tracker.alphaSets==0
   and collapse.mouseSets==0 and watch.alphaSets==0,
   'and so do the tracker and WatchFrame above it: a bag at alpha 1 is not usable inside a parent at alpha 0')
  host.objective=Objective(true)
  host.Scan()
  check(#host.status.GetSummary().rewards==1,'fixture: usable reward rows arrive')
  check(bag.alpha==0 and bag.mouse==false and root.alpha==0 and root.mouse==false
   and tracker.alpha==0 and collapse.mouse==false and watch.alpha==0,
   'with usable reward rows the covered row replaces the bag and every stock role above it')
  host.objective=Objective(false)
  host.Scan()
  check(#host.status.GetSummary().rewards==0,'fixture: the reward rows are gone again')
  check(bag.alpha==1 and bag.mouse==true and root.alpha==0.35 and root.mouse==true
   and tracker.alpha==0.8 and collapse.mouse==true and watch.alpha==1,
   'without them the exact originals come back while the row itself stays covered')
  check(bag.showHides+root.showHides+tracker.showHides+collapse.showHides+watch.showHides==0,
   'no stock frame is shown or hidden: only alpha and mouse are used')
 end)

 Case('progress-only tracker without reward rows',function()
  local watch=StockObject(1,true)
  local root=StockObject(0.35,true,watch)
  local bag=StockObject(1,true,root)
  root.rewardBagFrame=bag
  local tracker=StockObject(0.8,true)
  local collapse=StockObject(1,true,tracker)
  tracker.collapse=collapse
  local host=CallboardHost({objective=Objective(false),root=root,tracker=tracker,watch=watch})
  host.Scan()
  check(bag.alpha==1 and bag.mouse==true and root.alpha==0.35 and root.mouse==true
   and watch.alpha==1 and bag.alphaSets+bag.mouseSets+root.alphaSets+root.mouseSets+watch.alphaSets==0,
   'the reward bag, its objective root and the WatchFrame above them keep their state')
  check(tracker.alpha==0 and collapse.mouse==false,
   'a progress-only tracker outside the parents of the reward bag stays replaced')
  host.Cover(false)
  check(tracker.alpha==0.8 and collapse.mouse==true,'and gets its exact original back')
 end)

 Case('initially hidden or disabled stock state',function()
  local root=StockObject(0,false)
  local bag=StockObject(1,false,root)
  root.rewardBagFrame=bag
  local tracker=StockObject(0,true)
  local collapse=StockObject(1,false,tracker)
  tracker.collapse=collapse
  local host=CallboardHost({objective=Objective(true),root=root,tracker=tracker})
  host.Scan()
  check(bag.alpha==0,'fixture: the visible reward bag alpha is replaced')
  check(root.alphaSets==0 and root.mouseSets==0 and bag.mouseSets==0 and tracker.alphaSets==0
   and collapse.mouseSets==0,
   'alpha already 0 and mouse already off are the game state, not changed by Nexus and never written')
  -- While the row stays covered the game fades its root in and enables it.
  root.alpha=0.5;root.mouse=true
  host.status.PublishCoverage()
  check(root.alpha==0 and root.mouse==false,'the next pass takes over the values the game raised')
  host.Cover(false)
  check(root.alpha==0.5 and root.mouse==true,
   'hiding the row gives back the game values, not the initial alpha 0 and mouse off')
  check(bag.alpha==1 and bag.mouse==false and tracker.alpha==0 and tracker.mouse==true
   and collapse.mouse==false,'every initially hidden or disabled property is exactly as the game left it')
  check(bag.mouseSets==0 and tracker.alphaSets==0 and collapse.mouseSets==0,
   'and none of those was ever written')
 end)

 Case('coverage ends',function()
  local root=StockObject(0.35,true)
  local host=CallboardHost({objective=Objective(true),root=root})
  host.Scan()
  check(root.alpha==0 and root.mouse==false,'fixture: the objective root is replaced')
  host.facts.committed=false;host.status.PublishCoverage()
  check(root.alpha==0.35 and root.mouse==true,'an uncommitted Nexus panel gives the root back')
  host.facts.committed=true;host.status.PublishCoverage()
  check(root.alpha==0 and root.mouse==false,'a committed one replaces it again')
  host.facts.hadFailure=true;host.status.PublishCoverage()
  check(root.alpha==0.35 and root.mouse==true,'a failed render gives it back')
  host.facts.hadFailure=false;host.status.PublishCoverage()
  check(root.alpha==0,'fixture: covered again')
  host.objective=nil;host.log={}
  host.Scan()
  check(host.status.GetSummary().observed==false and root.alpha==0.35 and root.mouse==true,
   'an objective that disappears gives it back')
 end)

 -- Part C2: objective identity and reward attribution, through the same host,
 -- its scanner, GetSummary and ShowRewardsTooltip. The synthetic GameTooltip
 -- is drawn by the game for its own owner and only read by Nexus, through the
 -- OnShow hook Init installs. Two known positive quest IDs that differ are two
 -- objectives even under one title. Synthetic source behaviour only.
 local function RewardTooltip()
  local tip={left={},right={},hooks={},writes=0}
  for i=1,8 do
   _G['GameTooltipTextLeft'..i]={GetText=function() return tip.left[i] end}
   _G['GameTooltipTextRight'..i]={GetText=function() return tip.right[i] end}
  end
  function tip:HookScript(event,fn) self.hooks[event]=fn end
  function tip:NumLines() return #self.left end
  function tip:GetOwner() return self.owner end
  function tip:SetOwner(owner) self.writes=self.writes+1;self.owner=owner end
  function tip:ClearAllPoints() end
  function tip:SetPoint() end
  function tip:ClearLines() self.writes=self.writes+1;self.left,self.right={},{} end
  function tip:AddLine(text)
   self.writes=self.writes+1;self.left[#self.left+1]=tostring(text);self.right[#self.left]=''
  end
  function tip:AddDoubleLine(l,r)
   self.writes=self.writes+1;self.left[#self.left+1]=tostring(l);self.right[#self.left]=tostring(r)
  end
  function tip:Hide() self.writes=self.writes+1 end
  function tip:Show() if self.hooks.OnShow then self.hooks.OnShow(self) end end
  -- The game shows its own reward tooltip for owner.
  function tip:Observe(owner,ash)
   self.owner=owner
   self.left,self.right={'Rewards by Difficulty','Normal'},{'',tostring(ash)}
   self:Show()
  end
  function tip:Drawn() return table.concat(self.left,'|')..'|'..table.concat(self.right,'|') end
  return tip
 end
 -- Ordinary quest tracker text: a header, an ordinary quest and its progress.
 local function TrackerTexts(tracker,texts)
  function tracker:GetChildren()
   local out={}
   for i=1,#texts do out[i]={text=texts[i]} end
   return unpack(out)
  end
 end

 Case('same-title quest log row under another quest ID',function()
  local host=CallboardHost({objective=Objective(true),root=StockObject(0.35,true)})
  -- The log holds this title under quest 900 and in a row without an ID;
  -- neither is quest 77.
  host.log={{title='Callboard Quest',id=900,complete=1},{title='Callboard Quest',complete=-1}}
  host.Scan()
  local summary=host.status.GetSummary()
  local text=table.concat(summary.lines or {},'|')
  check(summary.observed==true and summary.questId==77,
   'the active objective keeps its own quest ID, not that of a same-title log row: '..tostring(summary.questId))
  check(text=='Bring the tome' and summary.progressSource=='objective',
   'no progress of the other quest, and no same-title row without an ID in its place: '..text)
  check(summary.rewards[1] and summary.rewards[1].ash==1200 and summary.rewardSource=='api'
   and summary.rewards[1].source=='api','its own API reward rows stay attributed to it')
  -- Control: the row with the matching ID is this objective, after the other one.
  host.log={{title='Callboard Quest',id=900,complete=-1},{title='Callboard Quest',id=77,complete=1}}
  host.Scan()
  summary=host.status.GetSummary()
  text=table.concat(summary.lines or {},'|')
  check(summary.questId==77 and text:find('Ready for turn-in',1,true)~=nil
   and text:find('Failed',1,true)==nil and summary.progressSource=='questlog',
   'the log row with the matching ID gives its progress: '..text)
  -- Control: with no ID on the log side the title still matches.
  host.log={{title='Callboard Quest',complete=1}}
  host.Scan()
  summary=host.status.GetSummary()
  check(summary.questId==77
   and table.concat(summary.lines or {},'|'):find('Ready for turn-in',1,true)~=nil,
   'a same-title row without an ID is a title fallback when no ID conflicts')
 end)

 Case('tooltip owner identity',function()
  local tip=RewardTooltip()
  local host=CallboardHost({objective=Objective(false),root=StockObject(0.35,true),tooltip=tip})
  host.Scan()
  check(#(host.status.GetSummary().rewards or {})==0,'fixture: the objective has no API reward rows')
  tip:Observe({objectiveData={title='Callboard Quest',questId=900}},3000)
  host.Scan()
  check(#(host.status.GetSummary().rewards or {})==0,
   'rows under a same-title tooltip owner with another quest ID are not attributed to this objective')
  local other={objectiveData={title='Callboard Quest',questId=900}}
  tip:Observe({objectiveData={title='Callboard Quest'},GetParent=function() return other end},3500)
  host.Scan()
  check(#(host.status.GetSummary().rewards or {})==0,
   'an owner without an ID does not override the conflicting ID its parent objective holds')
  local own={objectiveData={title='Callboard Quest',questId=77}}
  local owner={GetParent=function() return own end}
  tip:Observe(owner,4000)
  host.Scan()
  local summary=host.status.GetSummary()
  check(summary.rewards[1] and summary.rewards[1].ash==4000 and summary.rewards[1].source=='tooltip'
   and summary.rewardSource=='tooltip',
   'the parent objective with the matching ID attributes the observed rows to this objective')
  check(tip.writes==0 and tip.owner==owner and tip.left[2]=='Normal',
   'reading the game tooltip changed neither its owner nor its lines')
  local row={}
  host.status.ShowRewardsTooltip(row)
  check(tip.owner==row and tip:Drawn():find('4K Ash',1,true)~=nil,
   'the Nexus rewards tooltip shows the attributed rows')
 end)

 Case('same-title objective change and removal',function()
  local tip=RewardTooltip()
  local host=CallboardHost({objective=Objective(false),root=StockObject(0.35,true),tooltip=tip})
  host.Scan()
  tip:Observe({objectiveData={title='Callboard Quest'}},3000)
  host.Scan()
  local summary=host.status.GetSummary()
  check(summary.questId==77 and summary.rewards[1] and summary.rewards[1].ash==3000,
   'fixture: a capture whose owner has no ID is attributed to the observed objective by its title')
  local row={}
  host.status.ShowRewardsTooltip(row)
  check(tip:Drawn():find('3K Ash',1,true)~=nil,'fixture: the Nexus rewards tooltip shows those rows')
  -- The board moves on to another objective under the same title.
  host.objective={title='Callboard Quest',questId=900,objectiveText='Bring the other tome'}
  host.log={{title='Callboard Quest',id=900}}
  host.Scan()
  summary=host.status.GetSummary()
  check(summary.observed==true and summary.questId==900
   and (summary.lines or {})[1]=='Bring the other tome','fixture: the new objective is observed')
  check(#(summary.rewards or {})==0,
   'it does not inherit the reward rows cached for the old objective of the same title')
  host.status.ShowRewardsTooltip(row)
  check(tip:Drawn():find('not available',1,true)~=nil and tip:Drawn():find('3K Ash',1,true)==nil,
   'and the Nexus rewards tooltip says its rewards are not available')
  tip:Observe({objectiveData={title='Callboard Quest',questId=900}},5000)
  host.Scan()
  summary=host.status.GetSummary()
  check(summary.rewards[1] and summary.rewards[1].ash==5000,'its own observed rows are attributed')
  -- The objective is removed, and then the same one is observed again.
  host.objective=nil;host.log={}
  host.Scan()
  check(host.status.GetSummary().observed==false,'fixture: the objective is gone')
  host.objective={title='Callboard Quest',questId=900,objectiveText='Bring the other tome'}
  host.log={{title='Callboard Quest',id=900}}
  host.Scan()
  summary=host.status.GetSummary()
  check(summary.observed==true and #(summary.rewards or {})==0,
   'rows read before a removal are not inherited afterwards')
 end)

 Case('ordinary tracker without a Callboard source',function()
  local root=StockObject(0.35,true)
  local tracker=StockObject(0.8,true)
  TrackerTexts(tracker,{'Quests','One More Door','0/1 Doors'})
  local host=CallboardHost({objective=nil,root=root,tracker=tracker})
  host.log={{title='One More Door',id=901}}
  host.Scan()
  local summary=host.status.GetSummary()
  check(summary.observed==false,
   'a shown objective tracker does not make its first ordinary quest a Callboard objective: '
   ..tostring(summary.title))
  check(root.alphaSets+root.mouseSets+tracker.alphaSets+tracker.mouseSets==0,
   'and no stock state is changed for it')
  -- Control: the objectiveData of the reward bag is an authoritative source.
  local bag=StockObject(1,true,root)
  bag.objectiveData={title='Callboard Quest',questId=77,objectiveText='Bring the tome'}
  root.rewardBagFrame=bag
  host.Scan()
  summary=host.status.GetSummary()
  check(summary.observed==true and summary.title=='Callboard Quest' and summary.questId==77
   and (summary.lines or {})[1]=='Bring the tome' and summary.source=='bag',
   'the reward bag objective is observed, without the progress of the ordinary tracked quest')
 end)

 Case('current objective list matched by quest ID',function()
  local host=CallboardHost({objective=nil,root=StockObject(0.35,true)})
  local other={title='Callboard Quest',questId=900,objectiveText='Another board',normalSoulAshes=9000}
  local own={title='Callboard Quest',questId=77,objectiveText='Bring the tome',normalSoulAshes=1200}
  ProjectEbonhold.ObjectivesService.GetCurrentObjectives=function() return {other,own} end
  host.Scan()
  local summary=host.status.GetSummary()
  check(summary.observed==true and (summary.lines or {})[1]=='Bring the tome'
   and summary.rewards[1] and summary.rewards[1].ash==1200,
   'the current objective whose quest ID the log holds is observed with its own progress and rewards')
  check(summary.questId==77 and summary.source=='list' and summary.rewardSource=='api',
   'and attributed to the matched current-objective list and its API fields')
 end)

 -- Part C3: reward fidelity and the tracker identity rule, through the same
 -- host, its scanner, GetSummary and ShowRewardsTooltip. API XP stays XP: no
 -- money is derived from it, and money is what the source states. A passive
 -- single-line tooltip row keeps its own difficulty label. A watched quest of
 -- the same title under another known positive quest ID is another quest.
 Case('literal XP and explicit money',function()
  local tip=RewardTooltip()
  local o=Objective(false);o.normalXp=5000
  local host=CallboardHost({objective=o,root=StockObject(0.35,true),tooltip=tip})
  host.Scan()
  local summary=host.status.GetSummary()
  local first=(summary.rewards or {})[1]
  check(first and first.label=='Normal' and first.xp==5000 and first.copper==0
   and summary.rewardSource=='api',
   'API XP at level 80 stays XP and no money is derived from it: '..tostring(first and first.copper))
  local row={}
  host.status.ShowRewardsTooltip(row)
  local drawn=tip:Drawn()
  check(drawn:find('5000 XP',1,true)~=nil and drawn:find('MoneyFrame',1,true)==nil,
   'the Nexus rewards tooltip states the literal XP and no coin: '..drawn)
  o=Objective(false);o.normalXp=5000;o.normalMoney=45000;o.hc1Xp=7000;o.hc1Gold=3
  host.objective=o
  host.Scan()
  summary=host.status.GetSummary()
  local normal,hc1=(summary.rewards or {})[1],(summary.rewards or {})[2]
  check(normal and normal.copper==45000 and normal.xp==5000 and hc1 and hc1.label=='Hardcore I'
   and hc1.copper==30000 and hc1.xp==7000,
   'explicitly supplied money and gold stay the observed amounts beside their XP')
  host.status.ShowRewardsTooltip(row)
  drawn=tip:Drawn()
  check(drawn:find('|cffffffff4|r',1,true)~=nil and drawn:find('|cffffffff50|r',1,true)~=nil
   and drawn:find('|cffffffff3|r',1,true)~=nil and drawn:find('UI-GoldIcon',1,true)~=nil,
   'and the Nexus rewards tooltip shows that observed money: '..drawn)
 end)

 Case('single-line passive Hardcore II and III rows',function()
  local tip=RewardTooltip()
  local host=CallboardHost({objective=Objective(false),root=StockObject(0.35,true),tooltip=tip})
  host.Scan()
  check(#(host.status.GetSummary().rewards or {})==0,'fixture: the objective has no API reward rows')
  -- The game draws each difficulty and its amount on one line for its own owner.
  tip.owner={objectiveData={title='Callboard Quest',questId=77}}
  tip.left={'Rewards by Difficulty','Hardcore II 2000','Hardcore III 3000','Hardcore IV 4000'}
  tip.right={'','','',''}
  tip:Show()
  host.Scan()
  local summary=host.status.GetSummary()
  local labels={}
  for i,r in ipairs(summary.rewards or {}) do
   labels[i]=tostring(r.label)..'='..tostring(r.ash)..'/'..tostring(r.source)
  end
  local seen=table.concat(labels,',')
  check(seen=='Hardcore II=2000/tooltip,Hardcore III=3000/tooltip,Hardcore IV=4000/tooltip'
   and summary.rewardSource=='tooltip',
   'each observed row keeps its own longest difficulty label, never a shorter prefix: '..seen)
  local row={}
  host.status.ShowRewardsTooltip(row)
  local drawn=tip:Drawn()
  check(drawn:find('Hardcore II|Hardcore III|Hardcore IV|',1,true)~=nil
   and drawn:find('2K Ash',1,true)~=nil and drawn:find('3K Ash',1,true)~=nil,
   'and the Nexus rewards tooltip shows Hardcore II and III with their own amounts: '..drawn)
 end)

 Case('same-title watched quest under another quest ID',function()
  local watch=StockObject(0.9,true)
  local root=StockObject(0.35,true,watch)
  local bag=StockObject(1,true,root)
  root.rewardBagFrame=bag
  local tracker=StockObject(0.8,true)
  local collapse=StockObject(1,true,tracker)
  tracker.collapse=collapse
  local own={title='Callboard Quest',questId=991901,objectiveText='Bring the tome',
   normalSoulAshes=1200,normalMoney=45000}
  local host=CallboardHost({objective=own,root=root,tracker=tracker,watch=watch})
  host.log={{title='Callboard Quest',id=991901},{title='Callboard Quest',id=991999}}
  host.Scan()
  check(host.status.GetSummary().questId==991901 and tracker.alpha==0 and collapse.mouse==false
   and watch.alpha==0 and root.alpha==0,
   'fixture: nothing else is watched and every stock role is replaced')
  ProjectEbonholdDB.questTracker.watchedQuests[991999]=true
  host.Scan()
  check(tracker.alpha==0.8 and collapse.mouse==true and watch.alpha==0.9,
   'a watched same-title quest under another known quest ID gives the tracker, its collapse control and WatchFrame back')
  check(root.alpha==0 and root.mouse==false and bag.alpha==0 and bag.mouse==false,
   'while the covered objective root and its reward bag stay replaced')
  ProjectEbonholdDB.questTracker.watchedQuests[991999]=nil
  ProjectEbonholdDB.questTracker.watchedQuests[991901]=true
  host.Scan()
  check(tracker.alpha==0 and collapse.mouse==false and watch.alpha==0,
   'watching the objective under its own quest ID keeps the tracker roles replaced')
  host.Cover(false)
  check(tracker.alpha==0.8 and collapse.mouse==true and watch.alpha==0.9 and root.alpha==0.35
   and root.mouse==true and bag.alpha==1 and bag.mouse==true,
   'and hiding the row gives every exact original back')
 end)

 check(#failures==0,'Callboard stock ownership: '..table.concat(failures,' | '))
end

print('PASS server_hud_handoff: the stock HUD is replaced only by a replacement that exists checks='..checks)
