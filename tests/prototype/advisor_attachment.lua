-- The Nexus Advisor tab stays attached to the Echo Journal's host.
-- test.9027 anchored it once, to the last numbered journal tab, and set its
-- frame levels once. Client evidence (echo_journal.lua) says the journal is
-- reparented into CollectionsJournal on first embed, that this resets its
-- children's frame levels, and that the hub hides the journal's numbered tabs.
-- The frames below are SYNTHETIC models of those stated facts. They verify the
-- addon's anchoring logic only; they are not native verification, and the hub's
-- own replacement navigation is not modelled because it is not in the evidence.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(5,0)
-- Lazy creation, as in the client: the journal frames exist only after the first open.
local EJ=ProjectEbonhold.EchoJournal
local journal,tabs
local function CreateJournal()
 if journal then return end
 journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:SetSize(480,500);journal:SetPoint('TOPLEFT',UIParent,'TOPLEFT',16,-140);journal:SetFrameLevel(3);journal:Hide()
 CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
 tabs={}
 for i,label in ipairs({'Echoes','Loadouts','Tomes'})do
  local tab=CreateFrame('Button','ProjectEbonholdEchoJournalTab'..i,journal);tab:SetSize(90,32);tab:SetText(label);tab:SetFrameLevel(4)
  if i==1 then tab:SetPoint('CENTER',journal,'BOTTOMLEFT',70,-12) else tab:SetPoint('LEFT',tabs[i-1],'RIGHT',-16,0)end
  tab:SetScript('OnClick',function()end);tabs[i]=tab
 end
 journal.ownTabButtons=tabs
end
EJ.Show=function()CreateJournal();journal:Show()end
EJ.Toggle=function()CreateJournal();if journal:IsShown()then journal:Hide()else journal:Show()end end
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local J=Nexus.JournalTab

-- Test-side geometry: resolve a frame's first anchor to absolute coordinates.
local FX={LEFT=0,CENTER=.5,RIGHT=1};local FY={TOP=0,CENTER=.5,BOTTOM=1}
local function Frac(point)
 local x=point:find('LEFT')and 0 or point:find('RIGHT')and 1 or .5
 local y=point:find('TOP')and 0 or point:find('BOTTOM')and 1 or .5
 return x,y
end
local function Origin(f,depth)               -- top-left corner, y grows downward
 depth=depth or 0;assert(depth<12,'anchor chain must end')
 if f==UIParent then return 0,0 end
 assert(f:GetNumPoints()>=1,'frame has an anchor: '..tostring(f:GetName()))
 local point,rel,relPoint,x,y=f:GetPoint(1)
 assert(type(rel)=='table','anchor is relative to a frame, never bare screen coordinates: '..tostring(f:GetName()))
 local rx,ry=Origin(rel,depth+1);local px,py=Frac(relPoint);local sx,sy=Frac(point)
 return rx+px*rel:GetWidth()+(x or 0)-sx*f:GetWidth(), ry+py*rel:GetHeight()-(y or 0)-sy*f:GetHeight()
end
local function ChainReaches(f,host)
 for _=1,12 do if f==host then return true end;if f==UIParent or f==nil then return false end;f=select(2,f:GetPoint(1))end
 return false
end
local function Count(name)local n=0;for _,f in ipairs(H.frames)do if f.name==name then n=n+1 end end;return n end
local function Usable(tab)
 assert(tab:IsVisible() and tab:IsEnabled() and tab:GetScript('OnClick'),'Advisor tab is visible, enabled and clickable')
 assert(tab:GetParent()==journal and tab:GetNumPoints()==1,'one relative anchor, parented to the journal')
 assert(select(2,tab:GetPoint(1))~=UIParent and ChainReaches(tab,journal),'anchor chain reaches the journal, not the screen')
end

-- 1. Lazy creation: nothing to attach to yet, and no frame is invented.
assert(journal==nil and NexusJournalTab==nil and J.TryInstall()==false,'no journal yet: not installed, no frame created')
assert(J.AttachmentStatus().mode=='none')
-- Review F11: the first Install stops partway (synthetic failure after the tab and the panel exist).
-- The next lifecycle call runs the Install body again; it must reuse every frame and hook.
local realCreate,failedOnce=CreateFrame,false
CreateFrame=function(kind,name,...)if name=='NexusJournalScroll' and not failedOnce then failedOnce=true;error('synthetic partial install failure')end;return realCreate(kind,name,...)end
EJ.Show()
assert(failedOnce and J.AttachmentStatus().installed==false and NexusJournalTab,'fixture: the Install body stopped after it created the tab')
CreateFrame=realCreate
EJ.Show()
assert(J.AttachmentStatus().installed==true,'the second Install body completes')
local tab=assert(NexusJournalTab,'first open installs the Advisor tab')
Usable(tab)
local status=J.AttachmentStatus()
assert(status.mode=='journal-tabs' and status.anchor=='ProjectEbonholdEchoJournalTab3' and status.journalParent=='UIParent','standalone: after the last shown numbered tab: '..status.anchor)
assert(select(1,tab:GetPoint(1))=='TOPLEFT' and select(3,tab:GetPoint(1))=='TOPRIGHT' and tab:GetFrameLevel()==tabs[3]:GetFrameLevel())
print('PASS lazy creation: installed on first open, anchored after the last shown journal tab')

-- 2. Idempotent installation and hooks: repeated lifecycle calls add nothing.
local points=H.Clone({tab:GetPoint(1)})
for i=1,5 do J.TryInstall();EJ.Show();EJ.Toggle();EJ.Toggle()end
assert(Count('NexusJournalTab')==1 and Count('NexusJournalPanel')==1 and Count('NexusJournalScroll')==1,'one tab, one panel, one scroll frame')
assert(tab:GetNumPoints()==1,'anchors do not accumulate')
local clicks=0;local deselect=PanelTemplates_DeselectTab
PanelTemplates_DeselectTab=function(t)if t==tab then clicks=clicks+1 end end
tabs[2]:Click()
assert(clicks==1,'one stock-tab hook, not one per install attempt: '..clicks)
PanelTemplates_DeselectTab=deselect
print('PASS idempotent install and hooks')

-- 3. Drag, close and reopen in the standalone shape: the tab keeps its offset from the journal.
local function Offset()local tx,ty=Origin(tab);local jx,jy=Origin(journal);return tx-jx,ty-jy end
local ox,oy=Offset()
journal:ClearAllPoints();journal:SetPoint('TOPLEFT',UIParent,'TOPLEFT',400,-300)      -- the window was dragged
local nx,ny=Offset();assert(nx==ox and ny==oy,'the tab moved with the journal')
EJ.Toggle();assert(not tab:IsVisible(),'closed with the journal');EJ.Toggle();Usable(tab)
nx,ny=Offset();assert(nx==ox and ny==oy,'same place after close and reopen')
print('PASS drag and close/reopen (standalone)')

-- 4. Supported reparenting, from the client evidence: embedded into CollectionsJournal,
-- children's frame levels reset, numbered tabs hidden by the hub.
local hub=CreateFrame('Frame','CollectionsJournal',UIParent);hub:SetSize(1000,620);hub:SetPoint('TOPLEFT',UIParent,'TOPLEFT',50,-80);hub:SetFrameLevel(10)
journal:Hide();journal:SetParent(hub);journal:ClearAllPoints();journal:SetPoint('TOPLEFT',hub,'TOPLEFT',20,-60);journal:SetFrameLevel(12)
for _,child in ipairs({tab,NexusJournalPanel,tabs[1],tabs[2],tabs[3]})do child:SetFrameLevel(1)end   -- the reset
for _,t in ipairs(tabs)do t:Hide()end
journal:Show()
status=J.AttachmentStatus()
assert(status.mode=='journal-frame' and status.anchor=='ProjectEbonholdEchoJournal' and status.journalParent=='CollectionsJournal','embedded: a hidden numbered tab is not the anchor: '..status.mode..' '..status.anchor)
assert(status.hubNavigation:find('not in client evidence',1,true),'the missing hub evidence is stated, no hub control is named')
Usable(tab)
assert(tab:GetFrameLevel()>journal:GetFrameLevel() and NexusJournalPanel:GetFrameLevel()==journal:GetFrameLevel()+10,'frame levels are reasserted after the reparent reset')
local tx,ty=Origin(tab);local jx,jy=Origin(journal)
assert(tx>=jx and tx+tab:GetWidth()<=jx+journal:GetWidth(),'inside the journal width')
assert(tx>jx+70+3*90,'not on the left tab-row origin, where the hidden tabs were')
print('PASS supported reparenting: visible host anchor, levels reasserted')

-- 5. Drag of the hub, close/reopen, UI scale: still attached, anchors unchanged.
ox,oy=Offset()
hub:ClearAllPoints();hub:SetPoint('TOPLEFT',UIParent,'TOPLEFT',333,-222)
nx,ny=Offset();assert(nx==ox and ny==oy and ChainReaches(tab,hub),'the tab moved with the dragged hub window')
hub:Hide();assert(not tab:IsVisible());hub:Show();Usable(tab)
hub:SetScale(1.3);journal:Hide();journal:Show()
nx,ny=Offset();assert(nx==ox and ny==oy and tab:GetScale()==1 and tab:GetNumPoints()==1,'UI scale is inherited through the parent; no own scale, no new anchor')
print('PASS hub drag, close/reopen and UI scale')

-- 6. Progression-tab switching: the hub hides the journal on another tab and shows it again.
journal:Hide();assert(not tab:IsVisible() and not NexusJournalPanel:IsVisible(),'hidden with the journal on another progression tab')
NexusJournalPanel:SetFrameLevel(1);journal:Show();Usable(tab)
assert(NexusJournalPanel:GetFrameLevel()==journal:GetFrameLevel()+10 and not NexusJournalPanel:IsShown(),'back on Echoes: levels right, Advisor content closed until clicked')
tab:Click();assert(NexusJournalPanel:IsVisible(),'Advisor content opens from the tab')
-- Review F13: with the numbered tabs hidden no stock click closes the Advisor; a second click on its own tab does.
tab:Click();assert(not NexusJournalPanel:IsShown() and tab:IsVisible(),'a second click closes the Advisor content')
tab:Click();assert(NexusJournalPanel:IsVisible());journal:Hide();journal:Show()
assert(not NexusJournalPanel:IsShown(),'reopening the journal starts with the Advisor content closed')
-- The host restores the numbered tabs (standalone again): event-driven, without a reopen.
for _,t in ipairs(tabs)do t:Show()end
status=J.AttachmentStatus();assert(status.mode=='journal-tabs' and status.anchor=='ProjectEbonholdEchoJournalTab3','re-anchored when the numbered tabs returned')
tabs[3]:Hide();status=J.AttachmentStatus();assert(status.anchor=='ProjectEbonholdEchoJournalTab2','only a shown tab is used')
Usable(tab);assert(Count('NexusJournalTab')==1)
local snapshot=table.concat(J.DebugSnapshot(),'\n')
assert(snapshot:find('advisorTab mode=journal-tabs anchor=ProjectEbonholdEchoJournalTab2',1,true),'the attachment is in the diagnostic snapshot')
assert(#H.actions==0,'no gameplay action')
print('PASS progression-tab switching and event-driven re-anchor')
