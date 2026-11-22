-- M7 (work item 5; windowDependencies): contextual Help from each window
-- family. Native QA test.163008 (design/current "Nexus Setup Alternative":
-- Help opens the coach, the manual is Reference on request): each window's
-- Help opens the guided setup coach, and a separately labelled Reference
-- opens that window's own manual page. The Build Library and the
-- Leaderboard offer both on their top row (the Sharing page); like their
-- other nav buttons each replaces the window, whose layer is above both. The
-- Wishlist Editor offers both (the Wishlists page) and stays open below
-- either (HIGH under their DIALOG); its draft is untouched. The Orb window's
-- Help opens the coach in its place and its Reference opens the Orbs page
-- above it. Help's own action row reaches the setup checklist, which Escape
-- closes. The Help text names the new routes and wording. Every route only
-- opens a page: nothing is sent, assigned, saved or spent. fresh31: the
-- Journal's Build Progress page offers passive Help and Reference in its own
-- button row (X6); the setup checklist keeps every reason readable under the
-- conservative font models with a long name, says a refused route's reason
-- in the window and takes no keyboard focus (X7, UX-18); Escape closes each
-- window family opened here (X8).
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
local function CoachShown() return _G.NexusGuidedSetup~=nil and NexusGuidedSetup:IsShown() end
local function HideCoach() if Nexus.GuidedSetupUI then Nexus.GuidedSetupUI.Hide() end end
local function Registered(name) for _,n in ipairs(UISpecialFrames) do if n==name then return true end end;return false end
-- The visible FontString of `root` with this exact text (a window title).
local function Text(root,text)
 for _,r in ipairs(root and root.regions or {}) do
  if r.kind=='FontString' and V.Plain(r:GetText() or '')==text then return r end
 end
end
-- A button's whole label in it, in the conservative 7 px model plus caps.
local function Holds(button) return G.Length(V.Plain(button:GetText() or ''))*7+16<=button:GetWidth() end
-- A centred title's text extent (9 px per character of the large font, a
-- conservative model; the harness gives FontStrings a default box), 16 px tall.
local function TitleRect(root,fs)
 local r=G.Rect(fs,root)
 local w=G.Length(V.Plain(fs:GetText() or ''))*9
 local cx=(r[1]+r[3])/2
 return {cx-w/2,r[2],cx+w/2,r[2]+16}
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
C.setup(not Nexus.OverwriteWarning.IsOpen(),'fixture: no Auto warning waits, so the coach can open')

C.scenario('X1 the Build Library: Help opens the coach, Reference the Sharing page, each in place of the window',function()
 Nexus.CommunityBuilds.Show()
 local f=NexusCommunityBuildsFrame
 C.setup(f~=nil and f:IsShown(),'X1: fixture: the Build Library is open')
 if not f then return end
 local help,reference=f._helpNav,f._referenceNav
 C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown() and help:IsEnabled(),'X1: the nav row offers Help')
 C.expect(reference~=nil and V.Plain(reference:GetText())=='Reference' and reference:IsShown() and reference:IsEnabled(),
  'X1: the nav row offers the manual under its own label, Reference')
 if not (help and reference) then return end
 local wish=f._navBar and V.Button(H,f._navBar,'Wishlists')
 local r,x,root=G.Rect(help,f),G.Rect(reference,f),G.Rect(f,f)
 print('OBSERVED','X1 help',G.Text(r),'reference',G.Text(x))
 C.expect(G.Apart(r,x) and G.Inside(r,root) and G.Inside(x,root) and Holds(reference),
  'X1: Help and Reference sit apart, inside the window, Reference holding its label',G.Text(r)..' / '..G.Text(x))
 if wish then C.expect(G.Apart(G.Rect(wish,f),r) and G.Apart(G.Rect(wish,f),x),'X1: both are clear of the other nav buttons') end
 local title=Text(f,'Explore / Build Library')
 if title then C.expect(G.Apart(TitleRect(f,title),x),'X1: Reference is clear of the title',G.Text(TitleRect(f,title))) end
 C.guard(f:GetFrameLevel()>(NexusHelpWindow and NexusHelpWindow:GetFrameLevel() or 40),
  'X1: the Library\'s layer is above Help\'s (why each route replaces the window)')
 local before=Effects()
 help:Click()
 C.expect(not f:IsShown() and CoachShown() and HelpTitle()=='','X1: Help opens the guided setup coach in place of the Library, not the manual',HelpTitle())
 HideCoach()
 Nexus.CommunityBuilds.Show()
 reference:Click()
 C.expect(not f:IsShown() and not CoachShown() and HelpTitle()=='Nexus Reference - Shared builds and DPS',
  'X1: Reference opens the manual on its Sharing page in place of the Library',HelpTitle())
 C.guard(Same(before,Effects()),'X1: opening Help or Reference sends, acts and changes nothing')
 if NexusHelpWindow then NexusHelpWindow:Hide() end
end)

C.scenario('X2 the Leaderboard (Records): Help opens the coach, Reference the Sharing page',function()
 Nexus.Leaderboard.Show()
 local f=NexusLeaderboardFrame
 C.setup(f~=nil and f:IsShown(),'X2: fixture: the Leaderboard is open')
 if not f then return end
 local help,reference=f._helpNav,f._referenceNav
 C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown(),'X2: the nav row offers Help')
 C.expect(reference~=nil and V.Plain(reference:GetText())=='Reference' and reference:IsShown(),'X2: the top row offers Reference')
 if not (help and reference) then return end
 local r,x,root=G.Rect(help,f),G.Rect(reference,f),G.Rect(f,f)
 print('OBSERVED','X2 help',G.Text(r),'reference',G.Text(x))
 local wish=V.Button(H,f,'Wishlists')
 if wish then
  C.expect(G.Apart(r,G.Rect(wish,f)) and G.Inside(r,root),'X2: Help sits beside the other nav buttons, inside the window',G.Text(r))
 end
 -- The window is titled Records (composition pass; earlier "Explore / Leaderboard").
 local title=Text(f,'Records')
 C.expect(G.Inside(x,root) and Holds(reference) and (not title or G.Apart(TitleRect(f,title),x)),
  'X2: Reference is inside the window, holds its label and is clear of the centred title',G.Text(x))
 for _,label in ipairs({'Sync Now'}) do
  local other=V.Button(H,f,label)
  if other then C.expect(G.Apart(G.Rect(other,f),x),'X2: Reference is clear of '..label) end
 end
 local before=Effects()
 help:Click()
 C.expect(not f:IsShown() and CoachShown() and HelpTitle()=='',
  'X2: the Records Help opens the guided setup coach, not the seven-page manual',HelpTitle())
 HideCoach()
 Nexus.Leaderboard.Show()
 reference:Click()
 C.expect(not f:IsShown() and not CoachShown() and HelpTitle()=='Nexus Reference - Shared builds and DPS',
  'X2: Reference opens the manual on its Sharing page',HelpTitle())
 C.guard(Same(before,Effects()),'X2: opening Help or Reference sends, acts and changes nothing')
 if NexusHelpWindow then NexusHelpWindow:Hide() end
end)

C.scenario('X3 the Wishlist Editor: Help opens the coach above it, Reference the Wishlists page; the draft stays',function()
 Nexus.WishlistEditor.Show()
 local f=NexusEditorFrame
 C.setup(f~=nil and f:IsShown(),'X3: fixture: the Wishlist Editor is open')
 if not f then return end
 C.guard(Registered('NexusEditorFrame') and f:GetFrameStrata()=='HIGH','X3: Escape closes the editor; it is on the HIGH layer')
 local help,reference=f._helpNav,f._referenceNav
 C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown(),'X3: the editor\'s nav row offers Help')
 C.expect(reference~=nil and V.Plain(reference:GetText())=='Reference' and reference:IsShown(),'X3: the editor offers Reference')
 if not (help and reference) then return end
 local x,root=G.Rect(reference,f),G.Rect(f,f)
 local title=Text(f,'Plan / Wishlist Editor')
 C.expect(G.Inside(x,root) and Holds(reference) and (not title or G.Apart(TitleRect(f,title),x))
  and G.Apart(G.Rect(help,f),x),'X3: Reference is inside the editor, clear of the title and Help',G.Text(x))
 local name=_G.NexusWishlistNameInput
 if name then name:SetText('Artificial draft name') end
 local before,draft=Effects(),name and name:GetText()
 help:Click()
 C.expect(f:IsShown() and CoachShown() and HelpTitle()=='','X3: Help opens the coach with the editor still open',HelpTitle())
 C.guard(NexusGuidedSetup:GetFrameStrata()=='DIALOG','X3: the coach is on the DIALOG layer, above the editor')
 HideCoach()
 reference:Click()
 C.expect(f:IsShown() and HelpTitle()=='Nexus Reference - Wishlists and locked targets',
  'X3: Reference opens the manual on its Wishlists page with the editor still open',HelpTitle())
 C.guard(NexusHelpWindow:GetFrameStrata()=='DIALOG','X3: Reference is on the DIALOG layer, above the editor')
 C.guard((not name or name:GetText()==draft) and Same(before,Effects()),'X3: the draft and everything else are unchanged',printable(name and name:GetText()))
 NexusHelpWindow:Hide();f:Hide()
end)

C.scenario('X4 the Orb window: Help opens the coach in its place, Reference the Orbs page above it; Help\'s action row reaches the checklist',function()
 local orb=Nexus.OrbPanel.Show()
 local button=orb and V.Button(H,orb,'Help')
 local reference=orb and V.Button(H,orb,'Reference')
 C.expect(button~=nil and reference~=nil,'X4: the Orb window offers Help and Reference')
 if button and reference then
  local before=Effects()
  button:Click()
  C.expect(CoachShown() and not orb:IsShown() and HelpTitle()=='','X4: Help opens the coach in the Orb window\'s place',HelpTitle())
  HideCoach()
  orb=Nexus.OrbPanel.Show()
  reference:Click()
  C.expect(orb:IsShown() and HelpTitle()=='Nexus Reference - Orbs / Lost Memories','X4: Reference opens the Orbs page above the Orb window',HelpTitle())
  C.guard(Same(before,Effects()),'X4: opening Help or Reference spends, sends and changes nothing')
  for _,label in ipairs({'Help','Advanced','Mini panel','Close'}) do
   local other=V.Button(H,orb,label)
   if other then C.expect(G.Apart(G.Rect(other,orb),G.Rect(reference,orb)),'X4: Reference is clear of '..label) end
  end
  C.expect(G.Inside(G.Rect(reference,orb),G.Rect(orb,orb)) and Holds(reference),'X4: Reference is inside the Orb window and holds its label')
  if NexusHelpWindow then NexusHelpWindow:Hide() end
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
 -- The original-design coach entry comes first; the menu is named by its
 -- visible Options label (issue #165), never a bare ellipsis, and its entry
 -- is a direct Options choice (native QA test.163008: no Manage submenu).
 C.expect((pages.start or ''):find('Start here: Setup / Welcome opens Guided setup at the step you left',1,true)==1
  and Has(pages.start,'(Options > Setup / Welcome)') and not Has(pages.start,'... menu') and not Has(pages.start,'Manage'),
  'X5: Getting started opens with the Guided setup entry and names its Options menu route',pages.start)
 C.expect(Has(pages.start,'Help in each Nexus window') and Has(pages.start,'Reference in a Nexus window opens its own page here'),
  'X5: Getting started says each window\'s Help opens the guide and its Reference opens the manual page',pages.start)
 C.expect(Has(pages.start,'Setup checklist (also in the Options menu)') and Has(pages.start,'closing the Welcome is not a setup step'),
  'X5: Getting started names the checklist and what it is not',pages.start)
 C.expect(Has(pages.start,'A step is done only after Nexus reads the result back; a skipped, pending or unknown step is not done.')
  and Has(pages.start,'Opening, navigating or closing the guide assigns, shares, spends and turns on nothing.'),
  'X5: opening or closing the guide is not a verified step; only a read back result completes one',pages.start)
 -- (2026-11-19, user/coordinator-approved Start/Stop wording: no maximum, Pause/Resume, Review target or Continue.)
 C.expect(Has(pages.orbs,'Continue is no longer offered') and Has(pages.orbs,'kept unchanged as history'),'X5: the Orbs page says Continue is gone and earlier records are history')
 C.expect(Has(pages.orbs,'A maximum saved by an earlier version is kept but not used') and Has(pages.orbs,"is used from the run's next step"),'X5: it names the unused saved maximum and a changed target')
 C.expect(Has(pages.orbs,'Run history clears on reload or logout, and the saved record is kept'),'X5: it names what a reload clears and keeps')
 for _,s in ipairs({'Nexus never retries or refunds it, and never deletes the record',
  'Nexus never continues an earlier run by itself','Closing the window does not stop a run. Use Stop'}) do
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
C.scenario('X6 the Journal Build Progress page offers passive Help (coach) and Reference (Wishlists page) in its button row',function()
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
 local help,reference,details
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:GetParent()==page and f:IsShown() then
   local label=V.Plain(f:GetText() or '')
   if label=='Help' then help=f elseif label=='Reference' then reference=f
   elseif label=='Show details' or label=='Hide details' then details=f end
  end
 end
 C.expect(help~=nil and reference~=nil,'X6: the page offers Help and Reference')
 if not (help and reference) then return end
 local r,x=G.Rect(help,page),G.Rect(reference,page)
 local width=(tonumber(page:GetWidth()) or 0)+0.5
 print('OBSERVED','X6 help',G.Text(r),'reference',G.Text(x),'page width',tostring(page:GetWidth()))
 C.expect(G.Apart(r,x) and r[3]<=width and x[3]<=width and Holds(reference),
  'X6: Help and Reference sit apart, inside the page width',G.Text(r)..' / '..G.Text(x))
 if details then
  local d=G.Rect(details,page)
  C.expect(G.Apart(r,d) and G.Apart(x,d),'X6: both sit beside Show details',G.Text(d))
 end
 for _,button in ipairs({help,reference}) do
  local tip=V.Plain(table.concat(V.TooltipLines(button:GetScript('OnEnter'),button),' ')):lower()
  local jargon
  for _,w in ipairs(JARGON) do if tip:find(w,1,true) then jargon=w end end
  C.expect(tip:find('changes nothing',1,true)~=nil and jargon==nil,'X6: its tooltip says it changes nothing and uses no implementation words',tip)
 end
 local before=Effects()
 help:Click()
 C.expect(CoachShown() and HelpTitle()=='' and NexusJournalPanel:IsShown(),
  'X6: Help opens the guided setup coach and leaves the page open, not the manual',HelpTitle())
 HideCoach()
 reference:Click()
 C.expect(HelpTitle()=='Nexus Reference - Wishlists and locked targets' and NexusJournalPanel:IsShown(),
  'X6: Reference opens the Wishlists page and leaves the page open',HelpTitle())
 C.guard(Same(before,Effects()),'X6: opening Help or Reference assigns, sends, acts and changes nothing')
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
  -- The Reference row above Help and Close (design/current "Nexus Setup
  -- Alternative": Reference on request) holds its whole label, stays inside
  -- the window and clear of the text and the button row.
  local ref=f.reference
  C.expect(ref~=nil,tag..': the checklist offers Reference')
  if ref then
   local rr=G.Rect(ref,f)
   -- Width at this model (24 px end caps, as LayoutMetrics.FitButtonWidth);
   -- its height is the row's own 24 px, as the buttons beside it.
   C.expect(G.Length(V.Plain(ref:GetText() or ''))*model.char+24<=ref:GetWidth() and ref:GetHeight()==f.help:GetHeight(),
    tag..': Reference holds its whole label width in a button as tall as Help',tostring(ref:GetWidth())..'x'..tostring(ref:GetHeight()))
   C.expect(G.Inside(rr,{11,12,f:GetWidth()-12,f:GetHeight()-11}) and G.Apart(rr,G.Rect(f.notice,f))
    and G.Apart(rr,G.Rect(f.status[3],f)) and G.Apart(rr,G.Rect(f.help,f)) and G.Apart(rr,G.Rect(f.close,f))
    and G.Apart(rr,G.Rect(f.editor,f)) and G.Apart(rr,G.Rect(f.assign,f)),
    tag..': Reference lies inside the window, below the text and above the button row',G.Text(rr)..' in '..f:GetWidth()..'x'..f:GetHeight())
  end
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
