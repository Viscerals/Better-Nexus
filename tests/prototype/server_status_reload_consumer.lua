-- Consumer contract only: synthetic HUD text through the real TOC boot,
-- ServerStatus scanner, Main display input, MainViewModel and Panel renderer.
-- This does not implement the foreign Ebonhold producer or prove realm tier.
-- F.Reload round-trips synthetic saved data and reloads modules offline; it
-- does not model the producer's native ReloadUI/default/request behavior.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function InstallHud(H,text)
 HardmodeFrame=nil;EbonholdIntensityData=nil
 local root=CreateFrame('Frame','ProjectEbonholdPlayerRunFrame',UIParent)
 local header=CreateFrame('Frame',nil,root)
 local button=CreateFrame('Button',nil,header)
 local tier=button:CreateFontString(nil)
 tier:SetText(text)
 local ash=header:CreateFontString(nil);ash:SetText('76,054')
 local gain=header:CreateFontString(nil);gain:SetText('+188%')
 root.hardmodeTierText=tier;root.soulPointsText=ash;root.multiplierText=gain
 H.difficultyHud={root=root,tier=tier}
 -- Only the existing named balance contract is supplied. No tier getter or
 -- foreign update callback is invented, and Hide never changes the text.
 ProjectEbonhold.PlayerRunUI={GetUIElements=function()
  return {soulPointsText=ash}
 end}
end
local function Settle(H) H.Advance(2.5,.05) end
local function ExpectCaption(H,mode,tier,label)
 local summary=Nexus.ServerStatus.GetSummary()
 check(summary.mode==mode and summary.tier==tier,label..': scanner summary')
 check(summary.ash=='76,054' and summary.gain=='+188%',label..': balance and gain')
 local model=assert(Nexus.Panel._lastModel,label..': actual panel model')
 check(model.serverStatus and model.serverStatus.mode==mode
  and model.serverStatus.tier==tier,label..': Main and view model preserve summary')
 check(model.serverStatus~=summary,label..': display model does not alias the scanner cache')
 local box
 for _,frame in ipairs(H.frames) do
  if rawget(frame,'_summary') and frame:GetParent()==NexusPanel then
   check(box==nil,label..': unique rendered difficulty card')
   box=frame
  end
 end
 check(box~=nil and box:IsShown(),label..': actual difficulty card is shown')
 local expected='|cffff6b5f'..(tier or mode or 'Difficulty')..'|r'
 check(box.regions[1]:GetText()==expected,label..': actual rendered caption')
 check(Nexus.Panel.VisibilityFacts().committed==true,label..': panel committed')
 check(HardmodeFrame==nil,label..': no selected-menu override')
 check(#H.actions==0,label..': no game action')
 print('CONSUMER '..label..' mode='..tostring(mode)..' tier='..tostring(tier)
  ..' caption='..box.regions[1]:GetText())
end
local function Before(text) return function(H) InstallHud(H,text) end end

local db=F.Database({});db.soulAshHudMode='nexus'
local H=F.Boot(db,Before('Hardcore 1'));Settle(H)
ExpectCaption(H,'HC1','HC1','fresh boot HC1')
check(not H.difficultyHud.root:IsShown(),'committed Nexus panel suppresses synthetic HUD')
check(H.difficultyHud.tier:GetText()=='Hardcore 1','suppression does not edit HUD tier text')

H.Fire('PLAYER_ENTERING_WORLD');Settle(H)
ExpectCaption(H,'HC1','HC1','world entry unchanged HC1')

-- The scanner must rediscover the replacement frame object after world entry.
InstallHud(H,'Hardcore 1');H.Fire('PLAYER_ENTERING_WORLD');Settle(H)
ExpectCaption(H,'HC1','HC1','world entry replacement HC1')
check(not H.difficultyHud.root:IsShown(),'world entry replacement HC1: new root is discovered and suppressed')

H=F.Reload(Before('Hardcore 1'));Settle(H)
ExpectCaption(H,'HC1','HC1','offline module reload unchanged HC1')

-- A consumer that remembers HC1 as authority would reject these legitimate
-- new input states. Only the supplied text is asserted, never server state.
H.difficultyHud.tier:SetText('Normal');Settle(H)
ExpectCaption(H,'Normal',nil,'explicit Normal after HC1')
H=F.Reload(Before('Normal'));Settle(H)
ExpectCaption(H,'Normal',nil,'offline module reload explicit Normal')

H.difficultyHud.tier:SetText('');Settle(H)
ExpectCaption(H,nil,nil,'absent difficulty text')
H=F.Reload(Before(''));Settle(H)
ExpectCaption(H,nil,nil,'offline module reload absent difficulty')

-- Issue #164: Hide Nexus Panel is the player's saved display choice. While
-- the panel is hidden the game's own Difficulty/Soul Ash widget is on screen,
-- as and where the game left it; the choice survives an offline module
-- reload and a login with the saved data, is undone only by /nexus panel or
-- the minimap button, and never changes Auto or a setting. Offline consumer
-- characterization only: this is not native client evidence.
local function AutoFacts()
 local stats=Nexus.RecomputeStats()
 return tostring(stats.autoEnabled)..'|'..F.Serialize(Nexus.Store.Settings())
end
-- Counts every placement, alpha or mouse write to a stock widget. Nexus only
-- ever hides and shows it.
local function WatchStock(stock)
 local writes={n=0}
 for _,name in ipairs({'SetPoint','ClearAllPoints','SetAllPoints','SetParent',
  'SetAlpha','EnableMouse','SetScale','SetFrameStrata','SetFrameLevel','SetSize'}) do
  local original=stock[name]
  stock[name]=function(self,...)
   writes.n=writes.n+1;writes[#writes+1]=name
   if original then return original(self,...) end
  end
 end
 return writes
end
local function ExpectHidden(H,label)
 local stock=H.difficultyHud.root
 check(Nexus.Panel.IsShown()==false,label..': the Nexus panel is hidden')
 check(Nexus.Panel.VisibilityFacts().wanted==false,label..': as the player chose')
 check(NexusDB.panelHidden==true,label..': and the choice is saved')
 check(stock:IsShown()==true,label..': the stock Difficulty/Soul Ash widget is on screen')
 check(stock:GetParent()==UIParent,label..': in its own place')
 check(Nexus.ServerStatus.VisibilityFacts().replacing==false,label..': nothing stands in for it')
 check(H.difficultyHud.tier:GetText()=='Hardcore 1',label..': its difficulty text is untouched')
 check(#H.actions==0,label..': no game action')
end
local function ExpectShown(H,label)
 local stock=H.difficultyHud.root
 check(Nexus.Panel.IsShown()==true,label..': the Nexus panel is on screen')
 check(Nexus.Panel.VisibilityFacts().wanted==true,label..': as the player chose')
 check(NexusDB.panelHidden==nil,label..': and no hide is saved')
 check(stock:IsShown()==false,label..': the stock widget stands aside for it')
 check(Nexus.ServerStatus.VisibilityFacts().replacing==true,label..': the panel replaces it')
 check(#H.actions==0,label..': no game action')
end
do
 local db=F.Database({});db.soulAshHudMode='nexus'
 H=F.Boot(db,Before('Hardcore 1'));Settle(H)
 check(Nexus.MainInternals.SavedRootReadOnlyV1()==nil,
  'fixture: the saved root is writable, so a saved choice is expected to persist')
 ExpectShown(H,'#164 fresh boot')
 local writes=WatchStock(H.difficultyHud.root)
 local auto=AutoFacts()
 -- The header X and Hide Nexus Panel both call this.
 Nexus.Panel.Hide()
 check(H.difficultyHud.root:IsShown()==true,'#164 hide: the stock widget comes back at once')
 Settle(H)
 ExpectHidden(H,'#164 hide')
 -- Mode changes while hidden: neither takes the stock widget away.
 Nexus.ServerStatus.SetMode('server');Settle(H)
 ExpectHidden(H,'#164 hidden, server HUD')
 Nexus.ServerStatus.SetMode('nexus');Settle(H)
 ExpectHidden(H,'#164 hidden, Nexus HUD')
 check(NexusDB.soulAshHudMode=='nexus','#164: the HUD preference is what was chosen')
 check(AutoFacts()==auto,'#164 hide: Auto and settings are unchanged')
 check(writes.n==0,'#164 hide: no placement, alpha or mouse write: '..table.concat(writes,','))
end
do
 -- Offline module reload with the saved data round-tripped.
 H=F.Reload(Before('Hardcore 1'));Settle(H)
 ExpectHidden(H,'#164 after reload')
 Settle(H)
 ExpectHidden(H,'#164 after reload, later scans')
end
do
 -- Login with the saved choice: a fresh boot of a profile holding it.
 local db=F.Database({});db.soulAshHudMode='nexus';db.panelHidden=true
 H=F.Boot(db,Before('Hardcore 1'));Settle(H)
 ExpectHidden(H,'#164 login')
 local writes=WatchStock(H.difficultyHud.root)
 local auto=AutoFacts()
 -- /nexus panel restores it.
 SlashCmdList.NEXUS('panel')
 ExpectShown(H,'#164 /nexus panel')
 Settle(H)
 ExpectShown(H,'#164 /nexus panel, later scans')
 -- The minimap button: repeated toggles never orphan either HUD.
 local mini=_G.NexusMinimapButton
 check(mini~=nil and mini:GetScript('OnClick')~=nil,'#164: the minimap button exists')
 for round=1,4 do
  mini:GetScript('OnClick')(mini,'LeftButton')
  if round%2==1 then ExpectHidden(H,'#164 minimap toggle '..round)
  else ExpectShown(H,'#164 minimap toggle '..round) end
  Settle(H)
  if round%2==1 then ExpectHidden(H,'#164 minimap toggle '..round..' settled')
  else ExpectShown(H,'#164 minimap toggle '..round..' settled') end
 end
 -- Mode changes while visible.
 Nexus.ServerStatus.SetMode('server')
 check(H.difficultyHud.root:IsShown()==true and Nexus.Panel.IsShown()==true
  and NexusDB.panelHidden==nil,'#164 visible, server HUD: the stock widget comes back, the panel stays')
 Nexus.ServerStatus.SetMode('nexus');Settle(H)
 ExpectShown(H,'#164 visible, Nexus HUD again')
 -- Menu suppression. A dialog over a shown panel keeps the stock widget
 -- replaced (no flicker); a hide while it is open gives the widget back, and
 -- closing the dialog does not undo the hide.
 local dialog=CreateFrame('Frame','NexusIssue164Dialog',UIParent)
 dialog:Hide()
 Nexus.Panel.AttachMenuFrame(dialog)
 dialog:Show();Settle(H)
 check(Nexus.Panel.VisibilityFacts().menuSuppressed==true and Nexus.Panel.IsShown()==false,
  '#164 dialog: the panel is suppressed')
 check(H.difficultyHud.root:IsShown()==false,'#164 dialog: the stock widget stays replaced')
 Nexus.Panel.Hide()
 check(H.difficultyHud.root:IsShown()==true,'#164 dialog: hiding the panel gives the widget back')
 dialog:Hide();Settle(H)
 ExpectHidden(H,'#164 dialog closed after a hide')
 -- A show asked for while a dialog is open waits for the dialog to close.
 dialog:Show()
 SlashCmdList.NEXUS('panel')
 check(Nexus.Panel.IsShown()==false and Nexus.Panel.VisibilityFacts().wanted==true,
  '#164 dialog: a show waits for the dialog')
 dialog:Hide();Settle(H)
 ExpectShown(H,'#164 dialog closed after a show')
 -- The game recreates its widget while the panel is hidden.
 Nexus.Panel.Hide();Settle(H)
 ExpectHidden(H,'#164 before recreation')
 local old=H.difficultyHud.root
 InstallHud(H,'Hardcore 1');H.Fire('PLAYER_ENTERING_WORLD');Settle(H)
 check(H.difficultyHud.root~=old,'fixture: a new stock widget object')
 ExpectHidden(H,'#164 recreated while hidden')
 SlashCmdList.NEXUS('panel');Settle(H)
 ExpectShown(H,'#164 recreated, shown')
 check(old:IsShown()==true,'#164: the old widget object was given back and is not touched again')
 check(AutoFacts()==auto,'#164 toggles: Auto and settings are unchanged')
 check(writes.n==0,'#164 toggles: no placement, alpha or mouse write: '..table.concat(writes,','))
end
do
 -- Issue #164 readback through the real boot: a Show that returns without
 -- putting the widget on screen (another addon's no-op wrapper) is not a
 -- give-back. The state stays truthful (pending, still hidden by Nexus), the
 -- scans do not call Show every second, and nothing is moved or written to
 -- the widget. The game showing it later ends the claim.
 local db=F.Database({});db.soulAshHudMode='nexus'
 H=F.Boot(db,Before('Hardcore 1'));Settle(H)
 ExpectShown(H,'#164 no-op Show fixture')
 local stock=H.difficultyHud.root
 local writes=WatchStock(stock)
 local auto=AutoFacts()
 local realShow,noOps=stock.Show,0
 stock.Show=function() noOps=noOps+1 end
 Nexus.Panel.Hide()
 local facts=Nexus.ServerStatus.VisibilityFacts()
 check(noOps==1 and stock:IsShown()==false,'#164 no-op Show: the hide asks for the widget once; nothing came back')
 check(facts.restore=='pending' and facts.hiddenByNexus==true and facts.replacing==false and facts.stockShown==false,
  '#164 no-op Show: the state says the give-back is pending, not done ('..tostring(facts.restore)..')')
 Settle(H)
 check(noOps==1 and Nexus.ServerStatus.VisibilityFacts().restore=='pending',
  '#164 no-op Show: later scans read it back without calling Show every second')
 stock.Show=realShow
 SlashCmdList.NEXUS('panel');Settle(H)
 ExpectShown(H,'#164 no-op Show, panel shown again')
 check(Nexus.ServerStatus.VisibilityFacts().restore==nil,'#164 no-op Show: replacing again drops the pending give-back')
 Nexus.Panel.Hide()
 check(stock:IsShown()==true and Nexus.ServerStatus.VisibilityFacts().restore==nil
  and Nexus.ServerStatus.VisibilityFacts().hiddenByNexus==false,'#164: a working Show reads back shown and the claim ends')
 Settle(H)
 ExpectHidden(H,'#164 no-op Show, then a real give-back')
 check(AutoFacts()==auto and writes.n==0,'#164 no-op Show: Auto, settings and the widget\'s placement, alpha and mouse are unchanged')
end

print('PASS server_status_reload_consumer checks='..checks..'; synthetic producer; native cause UNKNOWN')
