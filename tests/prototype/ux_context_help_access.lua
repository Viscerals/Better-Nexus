-- M7 (work item 5; windowDependencies): contextual Help from each window
-- family. The Build Library and the Leaderboard offer Help on their nav row
-- (the Sharing page); like their other nav buttons it replaces the window,
-- whose layer is above Help's. The Wishlist Editor offers Help on its nav row
-- (the Wishlists page) and stays open below it (HIGH under Help's DIALOG); its
-- draft is untouched. The Orb window keeps its Help button. Help's own action
-- row reaches the setup checklist, which Escape closes. The Help text names
-- the new routes and wording. Every route only opens a page: nothing is sent,
-- assigned, saved or spent. fresh31: the Journal's Build Progress page offers
-- passive Help in its own button row (X6); the setup checklist keeps every
-- reason readable under the conservative font models with a long name, says
-- a refused route's reason in the window and takes no keyboard focus (X7,
-- UX-18); Escape closes each window family opened here (X8).
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a, where these buttons do not
-- exist; a missing button is a failed EXPECT, not a raised scenario; not
-- executed by the author). GUARD already holds there and must keep holding.
-- SETUP is the fixture. Geometry is the conservative harness model
-- (layout_geometry_support), not native glyphs, scale or hit testing.
-- Real TOC boot, format-5 saved data (Manual), real windows. No native claim.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local printable=V.printable
local C=V.Checker('ux_context_help_access')

local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end
local H=F.Boot(F.Database(),function(h)
 h.perks.serverBuildSlots={[1]={name='Artificial Help One',verified=true,echoes={E(200001,2),E(200002,1)}}}
 h.perks.serverActiveSlot=1
end)
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end
local function Until(limit,fn) for _=1,limit do if fn() then return true end;H.Advance(.05,.05) end;return fn() end
local function Effects() return {sent=#H.sent,actions=#H.actions,mode=Nexus.SyncModePolicy.Mode(),auto=Nexus.RecomputeStats().autoEnabled==true} end
local function Same(a,b) return a.sent==b.sent and a.actions==b.actions and a.mode==b.mode and a.auto==b.auto end
local function HelpTitle() return _G.NexusHelpWindow and NexusHelpWindow:IsShown() and V.Plain(NexusHelpWindow.title:GetText() or '') or '' end
local function Registered(name) for _,n in ipairs(UISpecialFrames) do if n==name then return true end end;return false end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')

C.scenario('X1 the Build Library: Help on its nav row opens Sharing in place of the window',function()
 Nexus.CommunityBuilds.Show()
 local f=NexusCommunityBuildsFrame
 C.setup(f~=nil and f:IsShown(),'X1: fixture: the Build Library is open')
 if not f then return end
 local help=f._helpNav
 C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown() and help:IsEnabled(),'X1: the nav row offers Help')
 if not help then return end
 local wish=f._navBar and V.Button(H,f._navBar,'Wishlists')
 if wish then
  local r,w,root=G.Rect(help,f),G.Rect(wish,f),G.Rect(f,f)
  print('OBSERVED','X1 help',G.Text(r),'wishlists',G.Text(w))
  C.expect(G.Apart(r,w) and G.Inside(r,root),'X1: it sits beside the other nav buttons, inside the window',G.Text(r)..' / '..G.Text(w))
 end
 C.guard(f:GetFrameLevel()>(NexusHelpWindow and NexusHelpWindow:GetFrameLevel() or 40),
  'X1: the Library\'s layer is above Help\'s (why the route replaces the window)')
 local before=Effects()
 help:Click()
 C.expect(not f:IsShown() and HelpTitle()=='Nexus Help - Shared builds and DPS','X1: Help opens on its Sharing page in place of the Library',HelpTitle())
 C.guard(Same(before,Effects()),'X1: opening Help sends, acts and changes nothing')
 if NexusHelpWindow then NexusHelpWindow:Hide() end
end)

C.scenario('X2 the Leaderboard: Help on its nav row opens Sharing in place of the window',function()
 Nexus.Leaderboard.Show()
 local f=NexusLeaderboardFrame
 C.setup(f~=nil and f:IsShown(),'X2: fixture: the Leaderboard is open')
 if not f then return end
 local help=f._helpNav
 C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown(),'X2: the nav row offers Help')
 if not help then return end
 local wish=V.Button(H,f,'Wishlists')
 if wish then
  local r,w=G.Rect(help,f),G.Rect(wish,f)
  C.expect(G.Apart(r,w) and G.Inside(r,G.Rect(f,f)),'X2: it sits beside the other nav buttons, inside the window',G.Text(r)..' / '..G.Text(w))
 end
 local before=Effects()
 help:Click()
 C.expect(not f:IsShown() and HelpTitle()=='Nexus Help - Shared builds and DPS','X2: Help opens on its Sharing page',HelpTitle())
 C.guard(Same(before,Effects()),'X2: opening Help sends, acts and changes nothing')
 if NexusHelpWindow then NexusHelpWindow:Hide() end
end)

C.scenario('X3 the Wishlist Editor: Help opens Wishlists above it; the draft stays',function()
 Nexus.WishlistEditor.Show()
 local f=NexusEditorFrame
 C.setup(f~=nil and f:IsShown(),'X3: fixture: the Wishlist Editor is open')
 if not f then return end
 C.guard(Registered('NexusEditorFrame') and f:GetFrameStrata()=='HIGH','X3: Escape closes the editor; it is on the HIGH layer')
 local help=f._helpNav
 C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown(),'X3: the editor\'s nav row offers Help')
 if not help then return end
 local name=_G.NexusWishlistNameInput
 if name then name:SetText('Artificial draft name') end
 local before,draft=Effects(),name and name:GetText()
 help:Click()
 C.expect(f:IsShown() and HelpTitle()=='Nexus Help - Wishlists and locked targets','X3: Help opens on its Wishlists page with the editor still open',HelpTitle())
 C.guard(NexusHelpWindow:GetFrameStrata()=='DIALOG','X3: Help is on the DIALOG layer, above the editor')
 C.guard((not name or name:GetText()==draft) and Same(before,Effects()),'X3: the draft and everything else are unchanged',printable(name and name:GetText()))
 NexusHelpWindow:Hide();f:Hide()
end)

C.scenario('X4 the Orb window keeps its Help; Help\'s action row reaches the checklist, which Escape closes',function()
 local orb=Nexus.OrbPanel.Show()
 local button=orb and V.Button(H,orb,'Help')
 C.guard(button~=nil,'X4: the Orb window offers Help')
 if button then
  button:Click()
  C.guard(HelpTitle()=='Nexus Help - Orbs / Lost Memories','X4: it opens the Orbs page',HelpTitle())
 end
 Nexus.OrbPanel.Hide()
 Nexus.Help.Show('start')
 local row=V.Button(H,NexusHelpWindow,'Setup checklist')
 C.expect(row~=nil,'X4: Help\'s action row offers Setup checklist')
 if row then
  local before=Effects()
  row:Click()
  C.expect(_G.NexusSetupChecklist~=nil and NexusSetupChecklist:IsShown() and not NexusHelpWindow:IsShown(),'X4: it opens the checklist in place of Help')
  C.expect(Registered('NexusSetupChecklist'),'X4: Escape closes the checklist')
  C.guard(Same(before,Effects()),'X4: opening it changes nothing')
  if NexusSetupChecklist then NexusSetupChecklist:Hide() end
 end
 C.guard(Registered('NexusHelpWindow'),'X4: Escape closes Help')
end)

C.scenario('X5 the Help text names the new routes and wording, and keeps its earlier statements',function()
 local pages={}
 for _,p in ipairs(Nexus.Help.Pages) do pages[p.id]=p.text end
 C.expect(Has(pages.start,'Setup checklist (also in the ... menu)') and Has(pages.start,'closing the Welcome is not a setup step'),
  'X5: Getting started names the checklist and what it is not',pages.start)
 C.expect(Has(pages.orbs,'labelled Paused') and Has(pages.orbs,'until it settles or you continue past it'),'X5: the Orbs page names restored PAUSED and the Continue exit')
 C.expect(Has(pages.orbs,'the window says the target is back') and Has(pages.orbs,'the maximum was not recorded'),'X5: it names a returned target and an unrecorded maximum')
 C.expect(Has(pages.orbs,'the header says the current state and the last recorded one'),'X5: it names live and recorded history state')
 for _,s in ipairs({'what is blocked, then what you can do now, then the details','Review target spends nothing',
  'Nexus never continues by itself','Closing the window does not stop an approved run. Use Pause or Stop.'}) do
  C.guard(Has(pages.orbs,s),'X5: the Orbs page keeps: '..s)
 end
 for id,text in pairs(pages) do
  for token in text:gmatch('%S+') do
   if #token*7>585 then C.guard(false,'X5: page '..id..': a token wider than the body: '..token) end
  end
 end
end)

-- fresh31: the Journal family. The journal frames are SYNTHETIC stand-ins
-- with the client's names (as advisor_build_progress builds them); the page,
-- its buttons and Help are the real JournalTab and Help code.
local JARGON={'provider','catalog','malformed','recogni','grammar','advisor'}
C.scenario('X6 the Journal Build Progress page offers passive Help in its button row',function()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 if not _G.ProjectEbonholdEchoJournalScroll then CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal) end
 if not _G.ProjectEbonholdEchoJournalTab1 then CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal) end
 local installed=Nexus.JournalTab.TryInstall(function() return {sections={}} end)
 C.setup(installed and _G.NexusJournalTab~=nil and _G.NexusJournalPanel~=nil,'X6: fixture: the Journal page installs')
 if not (_G.NexusJournalTab and _G.NexusJournalPanel) then return end
 NexusJournalTab:Click()
 local page=_G.NexusJournalScroll and NexusJournalScroll.scrollChild
 C.setup(NexusJournalPanel:IsShown() and page~=nil,'X6: fixture: the Build Progress page is shown')
 if not page then return end
 local help,details
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:GetParent()==page and f:IsShown() then
   local label=V.Plain(f:GetText() or '')
   if label=='Help' then help=f elseif label=='Show details' or label=='Hide details' then details=f end
  end
 end
 C.expect(help~=nil,'X6: the page offers Help')
 if not help then return end
 if details then
  local r,d=G.Rect(help,page),G.Rect(details,page)
  print('OBSERVED','X6 help',G.Text(r),'details',G.Text(d),'page width',tostring(page:GetWidth()))
  C.expect(G.Apart(r,d) and r[3]<=(tonumber(page:GetWidth()) or 0)+0.5,'X6: it sits beside Show details, inside the page width',G.Text(r))
 end
 local tip=V.Plain(table.concat(V.TooltipLines(help:GetScript('OnEnter'),help),' ')):lower()
 local jargon
 for _,w in ipairs(JARGON) do if tip:find(w,1,true) then jargon=w end end
 C.expect(tip:find('changes nothing',1,true)~=nil and jargon==nil,'X6: its tooltip says it changes nothing and uses no implementation words',tip)
 local before=Effects()
 help:Click()
 C.expect(HelpTitle()=='Nexus Help - Wishlists and locked targets' and NexusJournalPanel:IsShown(),
  'X6: it opens the Wishlists page and leaves the page open',HelpTitle())
 C.guard(Same(before,Effects()),'X6: opening Help assigns, sends, acts and changes nothing')
 if NexusHelpWindow then NexusHelpWindow:Hide() end
end)

-- fresh31 UX-18: the setup checklist under the conservative font models,
-- with a long Saved Build name. Every text block is either tall enough for
-- its wrapped text or kept at its maximum with the complete text on hover;
-- blocks and buttons do not overlap; a refused route says why in the window.
-- Modeled only: native glyphs, UI scale and occlusion remain M8.
local LONG='Artificial Help One with a deliberately long Saved Build name that will not fit on one line'
C.scenario('X7 the checklist keeps every reason readable under each font model and a long name',function()
 local slots=H.perks.serverBuildSlots
 slots[1].name=LONG;H.Notify();if Nexus.GameAdapter.Poll then Nexus.GameAdapter.Poll() end
 Nexus.Panel.Show();if Nexus.RequestRecompute then Nexus.RequestRecompute() end
 H.Advance(1)
 local quick=Nexus.QuickStart
 C.expect(type(quick.ShowChecklist)=='function' and type(quick.RefreshChecklist)=='function','X7: the checklist exists')
 if type(quick.ShowChecklist)~='function' then return end
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
  G.UseFont(model)
  local f=quick.ShowChecklist();quick.RefreshChecklist()
  local blocks={f.subtitle,f.rows[1],f.rows[2],f.rows[3],f.summary,f.statusTitle,f.status[1],f.status[2],f.status[3],f.notice}
  local tag='X7 '..model.name
  local named=false
  for _,fs in ipairs(blocks) do if (fs:GetText() or ''):find(LONG,1,true) then named=true end end
  C.setup(named,tag..': fixture: a checklist row names the long Saved Build')
  for i,fs in ipairs(blocks) do
   local text=fs:GetText() or ''
   local need=G.Rows(text,tonumber(fs:GetWidth()) or 0,model.char)*model.line
   local fits=(tonumber(fs:GetHeight()) or 0)+0.5>=need
   local full=fits
   if not fits and f.textHits then
    for _,hit in ipairs(f.textHits) do
     if hit._nexusText==fs then
      full=V.Plain(table.concat(V.TooltipLines(hit:GetScript('OnEnter'),hit),' '))==V.Plain(text)
     end
    end
   end
   C.expect(full,tag..': block '..i..' is readable in full (height or hover)',tostring(fs:GetHeight())..' < '..need)
   if i>1 then
    C.expect(G.Apart(G.Rect(blocks[i-1],f),G.Rect(fs,f)),tag..': blocks '..(i-1)..' and '..i..' do not overlap')
   end
  end
  C.expect(G.Apart(G.Rect(f.notice,f),G.Rect(f.close,f)) and G.Apart(G.Rect(f.status[3],f),G.Rect(f.assign,f)),
   tag..': the text ends above the buttons',tostring(f:GetHeight()))
 end
 G.UseFont(G.MODELS.default)
 -- A refused route says why in the checklist itself.
 local f=quick.ShowChecklist()
 local realStatus=Nexus.StartupStatus
 Nexus.StartupStatus=function() return {coreReady=false,state='pending'} end
 local ok=pcall(function() f.editor:Click() end)
 Nexus.StartupStatus=realStatus
 local notice=V.Plain(f.notice:GetText() or '')
 C.expect(ok and f:IsShown() and notice:find('opens after start-up finishes',1,true)~=nil,'X7: a refused route shows its reason in the window',notice)
 local editBoxes=0
 for _,x in ipairs(H.frames) do if x.kind=='EditBox' and x:GetParent()==f then editBoxes=editBoxes+1 end end
 C.expect(editBoxes==0 and Registered('NexusSetupChecklist'),'X7: the checklist takes no keyboard focus and Escape closes it')
 f:Hide()
end)

C.scenario('X8 Escape closes every Nexus window family opened above',function()
 for _,name in ipairs({'NexusCommunityBuildsFrame','NexusLeaderboardFrame','NexusEditorFrame','NexusOrbPanel','NexusHelpWindow'}) do
  C.guard(Registered(name),'X8: Escape closes '..name)
 end
 C.expect(Registered('NexusSetupChecklist'),'X8: Escape closes the setup checklist')
end)

C.guard(#H.actions==0,'no game action anywhere in this test',#H.actions)
C.finish('(contextual Help routes open pages only; modeled geometry, no native claim)')
