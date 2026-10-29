-- M4 (UX-13 / LP-13): one count vocabulary. Planned copies, rolled copies
-- this run, the Wishlist's copies found in a Saved Build, locked targets and
-- Echo families represented are different units and are said as such. A run
-- whose rolled copies are met while a locked target is still to lock is not
-- called complete; an unknown count is unavailable, never 0; the counting
-- itself (owned/total/toLock, EchoProgress) is unchanged.
-- Categories (view_regression_support): EXPECT is behaviour added in M4 (it
-- fails on the accepted M3 cut ab3cb307); GUARD already holds there and must
-- keep holding; SETUP is the fixture. Oracles: the text the real panel and
-- Build Library render (their own fontstrings), the panel's completed state,
-- the Help body, game-action/send/request counters. The panel is rendered by
-- its real Render from the model the runtime published, with only the count
-- fields of that model varied (the same synthetic-model render path the
-- terminology consumers use). Real TOC boot; synthetic host services only.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('ux_qualified_counts')
local H,A
local E2={{spellId=201175,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}

local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;NexusEditorFrame=nil;NexusPanel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=60
 wipe(H.db)
 H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots={[2]={name='Fire PvE',verified=true,echoes=H.Clone(E2)},
  [107]={name='W-Free',verified=false,echoes=H.Clone(EF)}}
 H.perks.serverActiveSlot=2
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() error('reading counts must not spend') end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
local function Effects()
 return {actions=#H.actions,sent=#H.sent,granted=tonumber(H.grantedRequests) or 0,
  facts=V.Count(type(Nexus.Store.State().loadoutWishlists)=='table' and Nexus.Store.State().loadoutWishlists or {})}
end
local function Same(a,b) return a.actions==b.actions and a.sent==b.sent and a.granted==b.granted and a.facts==b.facts end
-- Every visible text of the panel's own fontstrings.
local function PanelTexts()
 local out={}
 local frame=NexusPanel
 for _,r in ipairs(frame and frame.regions or {}) do
  if r.GetText and r:IsShown() then local t=r:GetText();if type(t)=='string' and t~='' then out[#out+1]=V.Plain(t) end end
 end
 return out
end
-- The panel's progress value: its own line that starts with the counts.
local function ProgressLine()
 for _,t in ipairs(PanelTexts()) do
  if t:find('^%d+ / %d+') or t:find('^Rolled') then return t end
 end
 return nil
end
local function Shows(needle)
 for _,t in ipairs(PanelTexts()) do if t:find(needle,1,true) then return t end end
 return nil
end
-- The model the runtime published, with only its count fields varied.
local function RenderCounts(owned,total,toLock)
 local model=H.Clone(Nexus.Panel._lastModel)
 model.progress=model.progress or {}
 model.progress.owned,model.progress.total,model.progress.toLock=owned,total,toLock
 model.progress.missing={};model.progress.unknownTomes={}
 model.progress.wishlistName=model.progress.wishlistName or 'W-Free'
 model.cards={};model.recommendation=nil;model.orbGuidance=nil;model.autoNote=nil
 return Nexus.Panel.Render(model)==true
end

C.scenario('Q1 rolled copies met while a locked target is still to lock: not complete, and said so',function()
 Boot()
 C.setup(A.SetLoadoutWishlist(2,107)==true,'Q1: fixture: Saved Build 2 is assigned W-Free')
 Nexus.Panel.Show();if Nexus.RequestRecompute then Nexus.RequestRecompute() end;H.Notify();H.Advance(1)
 C.setup(type(Nexus.Panel._lastModel)=='table','Q1: fixture: the runtime published a panel model')
 local before=Effects()
 C.setup(RenderCounts(79,79,{'Locked Echo (Rare)'}),'Q1: fixture: the panel renders 79/79 rolled with one locked target to lock')
 local line=ProgressLine() or ''
 print('OBSERVED','Q1 progress='..line)
 C.expect(line:find('79 / 79 rolled',1,true)~=nil and line:find('to lock',1,true)~=nil,
  'Q1: the progress says the rolled copies and that a locked target is still to lock',line)
 C.expect(not line:lower():find('complete',1,true),'Q1: it does not say complete',line)
 C.guard(Shows('Wishlist complete')==nil,'Q1: the panel does not show the Wishlist as complete')
 C.guard(Same(Effects(),before),'Q1: rendering changes no assignment and sends or requests nothing')
end)

C.scenario('Q2 a partial run names its unit',function()
 C.setup(RenderCounts(12,79,{}),'Q2: fixture: the panel renders 12/79 rolled')
 local line=ProgressLine() or ''
 print('OBSERVED','Q2 progress='..line)
 C.expect(line=='12 / 79 rolled copies this run','Q2: the progress names rolled copies this run',line)
 C.expect(not line:lower():find('complete',1,true),'Q2: a partial run is not called complete',line)
end)

C.scenario('Q3 met rolled copies with no locked target outstanding stay complete (unchanged)',function()
 C.setup(RenderCounts(79,79,{}),'Q3: fixture: the panel renders 79/79 with nothing to lock')
 C.guard(ProgressLine()==nil,'Q3: the in-progress count is not shown for a completed build',ProgressLine())
end)

C.scenario('Q4 the plan count says copies, not Echoes',function()
 -- The real ... menu item turns the DPS records view on (its own handler).
 local captured
 EasyMenu=function(items) captured=items end
 CloseDropDownMenus=CloseDropDownMenus or function() end
 local button=NexusPanel and NexusPanel._menuBtn
 if button then button:GetScript('OnClick')(button) end
 local show
 -- A direct Options choice (native QA test.163008).
 for _,item in ipairs(captured or {}) do if item.text=='Show DPS records' then show=item end end
 C.setup(show~=nil and type(show.func)=='function','Q4: fixture: the menu offers Show DPS records')
 if show then show.func() end
 C.setup(RenderCounts(12,79,{}),'Q4: fixture: the panel renders the plan with DPS records shown')
 local label=Shows('Target build') or ''
 print('OBSERVED','Q4 label='..label)
 C.expect(label:find('79 rolled copies',1,true)~=nil and not label:find('Echoes',1,true),
  'Q4: the plan count is rolled copies, not Echoes',label)
end)

-- The Build Library card of a server Saved Build mirror (format-5 saved
-- fixture: Saved Build 1 is assigned "Gen plan").
local function Until(limit,fn)
 for i=1,limit do if fn() then return i end;H.Advance(.05,.05) end
 return nil
end
local function Mirror(slot)
 local found
 for _,b in pairs(Nexus.CommunityBuilds.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==slot then found=b end
 end
 return found
end
local function LibraryLine(needle)
 local frame=NexusCommunityBuildsFrame
 if not frame then return nil end
 for _,f in ipairs(H.frames) do
  if f:IsVisible() then
   for _,r in ipairs(f.regions or {}) do
    if r.GetText and r:IsShown() then
     local t=V.Plain(r:GetText() or '')
     if t:find(needle,1,true) then return t end
    end
   end
  end
 end
 return nil
end

-- The Build Library window's own diagnostic (its controller's filters and
-- projection state), and the projection's own read-only explanation of why a
-- catalog row is or is not listed under those filters.
local function Diag()
 local ok,d=pcall(Nexus.CommunityBuilds.DiagnosticSnapshot)
 return ok and type(d)=='table' and d or {}
end
local function Explain(id)
 local d,projections=Diag(),Nexus.ViewProjections
 if not (projections and type(projections.ExplainBuild)=='function') then return 'unavailable' end
 local ok,why=pcall(projections.ExplainBuild,id,{scope=d.filterScope,currentClassOnly=d.filterCurrentClassOnly,
  qualifiedOnly=d.filterQualifiedOnly,search=''})
 return ok and tostring(why) or ('error: '..tostring(why))
end
-- The reasons ExplainBuild gives only after a row has passed the scope (own
-- for Mine) and current-class rules (ViewProjections.ExplainBuild order).
local PAST_SCOPE_AND_CLASS={['missing Dummy and Lich King records']=true,['missing Dummy record']=true,
 ['missing Lich King record']=true,['qualification unavailable']=true}

-- First run (checks/m4-initial-new-01 and the accepted-M3 control): the card
-- list was empty on both runtimes. Source trace (DIAGNOSIS_BEFORE_EDITS.md):
-- the Build Library's documented default filter "Require both DPS records"
-- (on unless explicitly turned off; it also applies under the Mine scope,
-- community_dps_filter.lua) leaves out a Saved Build with no DPS record, and
-- this fixture has none. The scenario now turns that filter off with its own
-- check box, as a player does. Its preconditions are checked through the
-- Build Library's own rules: the mirror is this character's verified Saved
-- Build (IsOwnBuild) and, under the default filters, it passes the Mine scope
-- and class rules and stops at the DPS-record stage. "qualification
-- unavailable" at that stage is an unknown DPS-record verdict, not by itself
-- proof that missing records alone excluded the card; the card itself decides.
-- Timing: the original single card wait (Until 2000) is kept and now starts
-- after the last real control (the check box); no extra settle wait is added.
C.scenario('Q5 the Saved Build card counts the Wishlist copies found in that Saved Build',function()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusCommunityBuildsFrame=nil;NexusPanel=nil
 H=F.Boot(F.Database(),function(h)
  h.perks.serverBuildSlots={[1]={name='Artificial Saved Build',verified=true,echoes=h.Clone(F.PLAN)}}
  h.perks.serverActiveSlot=1
 end)
 local CB=Nexus.CommunityBuilds
 local before=#H.actions
 CB.Show()
 C.setup(Until(2000,function() return Mirror(1)~=nil end)~=nil,'Q5: fixture: the Saved Build is imported by the real Build Library')
 local mirror=Mirror(1) or {}
 C.setup(mirror.destinationWishlistName=='Gen plan' and tonumber(mirror.destinationTotal)~=nil,
  'Q5: fixture: the mirror carries its assigned Wishlist and counts',tostring(mirror.destinationProgress)..'/'..tostring(mirror.destinationTotal))
 C.setup(mirror.id~=nil and CB.IsOwnBuild(mirror.id)==true,
  'Q5: fixture: the mirror is this character\'s verified Saved Build (the Build Library\'s own ownership rule)',tostring(mirror.id))
 local frame=NexusCommunityBuildsFrame
 local scope=frame and frame._myBuildsBtn
 if scope then scope:Click() end
 C.setup(Diag().filterScope=='mine' and not Diag().filterSearchActive,'Q5: fixture: the window lists the Mine scope with no search',tostring(Diag().filterScope))
 local why=Explain(mirror.id)
 print('OBSERVED','Q5 default filters: qualifiedOnly='..tostring(Diag().filterQualifiedOnly)..' explanation='..why)
 C.setup(Diag().filterQualifiedOnly==true and PAST_SCOPE_AND_CLASS[why]==true,
  'Q5: fixture: under the default filters the mirror passes the Mine scope and class rules and stops at the DPS-record stage',why)
 local box=frame and frame._qualifiedBtn
 if box and box:IsVisible() and box:IsEnabled() then
  -- The client flips a check box's own check before its OnClick runs.
  box:SetChecked(not box:GetChecked());box:Click()
 end
 C.setup(Diag().filterQualifiedOnly==false,'Q5: fixture: the real check box turned "Require both DPS records" off')
 -- The original card wait and budget, after the last real control.
 Until(2000,function() return LibraryLine('Assigned Wishlist:')~=nil end)
 local line=LibraryLine('Assigned Wishlist:') or ''
 local d=Diag()
 print('OBSERVED','Q5 after the check box: explanation='..Explain(mirror.id)..' current='..tostring(d.projectionCurrent)
  ..' pending='..tostring(d.projectionPending)..' blocked='..tostring(d.blockedReason)..' results='..tostring(d.resultCount))
 print('OBSERVED','Q5 card='..line)
 C.setup(line:find('Gen plan',1,true)~=nil,'Q5: fixture: the Mine scope shows the mirror card for Gen plan',line)
 local expected=string.format('%d / %d Wishlist copies in this Saved Build',
  tonumber(mirror.destinationProgress) or -1,tonumber(mirror.destinationTotal) or -1)
 C.expect(line:find(expected,1,true)~=nil,'Q5: the card names the unit: Wishlist copies in this Saved Build',line)
 -- Only a shown card can hold this (an empty line is not evidence).
 C.expect(line~='' and not line:find('in progress',1,true),'Q5: it no longer calls the Saved Build\'s copies "in progress"',line)
 -- The mirror's generated description, served beside it, counts the same
 -- copies (EchoProgress) and names the same unit; every count it gives is
 -- qualified.
 local desc=V.Plain(mirror.description or '')
 local unit=Nexus.UserText and Nexus.UserText.COUNT_UNITS and Nexus.UserText.COUNT_UNITS.savedBuild or '?'
 local bare=desc:gsub('%d+ ?/ ?%d+ '..unit:gsub('%p','%%%0'),'')
 print('OBSERVED','Q5 description='..desc)
 C.expect(desc:find(string.format('%d/%d %s',tonumber(mirror.destinationProgress) or -1,
  tonumber(mirror.destinationTotal) or -1,unit),1,true)~=nil and not bare:find('%d+ ?/ ?%d+'),
  'Q5: the generated description gives its count only as '..unit,desc)
 C.guard(#H.actions==before,'Q5: opening and filtering the Build Library performs no game action',#H.actions)
end)

C.scenario('Q6 Help gives the same count words',function()
 if Nexus.Help and Nexus.Help.Show then Nexus.Help.Show('start') end
 local body=V.Plain(NexusHelpWindow and NexusHelpWindow.body and NexusHelpWindow.body:GetText() or '')
 C.expect(body:find('Unavailable is not 0',1,true)~=nil and body:find('Echo families represented counts a family once',1,true)~=nil
  and body:find('rolled copies this run',1,true)~=nil,'Q6: Help names the count units and that unavailable is not 0',body:sub(-500))
end)

-- Q7 (UX-13, final copy closure): the Wishlist editor counts a plan, so its
-- footer and its save notice say the rolled copies are planned, never a bare
-- "N/79" beside Saved or assigned. Real editor, real Create & assign through
-- its own confirmation popup (the A01 route of ux_save_assignment_result),
-- real controller and adapter. The save's effects are unchanged: one upload,
-- Saved Build 2 assigned by Create as before, no other game action.
local function EditorButton(labels)
 for _,label in ipairs(labels) do
  for _,f in ipairs(H.frames) do if f.kind=='Button' and f:IsVisible() and f:GetText()==label then return f end end
 end
 return nil
end
local function CatalogRow(id)
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then return f end
 end
 return nil
end
-- The editor's two-line plan summary, found on both cuts by its count text.
local function FooterFirstLine()
 for _,r in ipairs(NexusEditorFrame and NexusEditorFrame.regions or {}) do
  local t=r.GetText and r:GetText()
  if type(t)=='string' and t:find('olled copies: %d+/79') then return t:match('^([^\n]+)') end
 end
 return nil
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
C.scenario('Q7 the editor footer and the save notice say planned rolled copies',function()
 NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil;NexusActiveWishlistSelector=nil
 NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil;NexusWishlistEditorLoadoutMenu=nil
 NexusWishlistSaveOnlyButton=nil
 Boot()
 SlashCmdList.NEXUS('editor')
 C.setup(NexusEditorFrame~=nil and NexusEditorFrame:IsShown() and NexusWishlistNameInput~=nil,'Q7: fixture: the Wishlist editor is open with a new draft')
 if NexusWishlistNameInput then NexusWishlistNameInput:SetText('Plan Q7') end
 local row=CatalogRow(201175)
 C.setup(row~=nil,'Q7: fixture: the catalog lists Echo Fire')
 if row then row:Click() end
 local footer=FooterFirstLine() or ''
 print('OBSERVED','Q7 footer='..footer)
 C.expect(footer=='Planned rolled copies: 1/79','Q7: the editor footer says the rolled copies are planned',footer)
 local uploadsBefore,others=0,0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploadsBefore=uploadsBefore+1 else others=others+1 end end
 local create=EditorButton({'Create & assign','Create unassigned','Create Wishlist'})
 if create then create:Click() end
 C.setup(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','Q7: fixture: Create asks for confirmation')
 local said=H.popup and Heard(function() H.AcceptPopup() end) or ''
 print('OBSERVED','Q7 said='..said)
 C.expect(said:find('Wishlist saved (1/79 rolled copies planned',1,true)~=nil,
  'Q7: the save notice says the rolled copies are planned',said)
 local uploads,othersAfter=0,0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploads=uploads+1 else othersAfter=othersAfter+1 end end
 local links=Nexus.Store.State().loadoutWishlists or {}
 C.guard(uploads==uploadsBefore+1 and othersAfter==others and links[2] and links[2].name=='Plan Q7',
  'Q7: the save itself is unchanged: one upload, Saved Build 2 assigned by Create, no other game action',
  'uploads='..uploads..' others='..othersAfter..' slot2='..tostring(links[2] and links[2].name))
end)

C.finish('(planned, run, Saved Build, locked and family counts are distinct units; no complete with a locked target outstanding)')
