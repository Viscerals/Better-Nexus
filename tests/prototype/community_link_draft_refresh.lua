-- F-S3-4 (P3), regression-first: an owner's unsaved link draft survives
-- ordinary background work. Every Build Library refresh re-renders the detail
-- pane, and the pane writes the stored link into the "Discord build link"
-- field whenever the field is shown (ui/CommunityRenderer.lua
-- RefreshDetailPanel), with no regard to an edit in progress. Any DPS or
-- build-library revision (a received record, Sync, a local capture) therefore
-- replaces what the owner typed, and Save Link afterwards saves the old value.
-- Healthy behaviour (EXPECT, fails at the baseline): with the field still
-- bound to the same own build, the typed draft survives a DPS_CHANGED
-- revision on the public revision bus and a DPS record received through the
-- real receive path; an explicit Save Link after such work saves the draft.
-- Unchanged (GUARD, holds at the baseline): the field stays bound to the same
-- build; nothing is saved without Save Link (the stored link stays empty);
-- selecting another build rebinds the field and discards the draft, and
-- returning shows the stored link; after the character changes (ownership
-- loss, the fake unit boundary the share tests use) a Save Link click writes
-- nothing; no game action.
-- Real TOC boot, catalog, controller, ViewRefresh and Build Library window;
-- the real edit-box handlers (typing is Insert, which the harness delivers as
-- user input); saved data from leaderboard_fixture_support.lua. The drafts are
-- artificial Discord-form links; nothing is sent to a network.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('community_link_draft_refresh')
local fx=L.New({players={
 {name='PrototypeTester',class='MAGE',isLocal=true,dps={dummy=40000},locked=0},
 {name='Bravo',class='PRIEST',dps={dummy=30000},locked=0},
}})
local H=F.Boot(fx:Install(F.Database({version=2})))
for _=1,400 do H.Advance(.05,.05) end
local CB=Nexus.CommunityBuilds
local ownId,otherId=fx.players[1].buildId,fx.players[2].buildId
local DRAFT='https://discord.com/channels/1/2/3'

local function Until(limit,fn)
 for i=1,limit do
  if fn() then return i end
  H.Advance(.05,.05)
 end
 return nil
end
local function Panel()
 local f=NexusCommunityBuildsFrame
 return f and f._detailPanel
end
local function ShowBuild(id)
 CB.ShowBuild(id)
 Until(4000,function()
  local p=Panel()
  return p and p:IsShown() and p._nexusShownId==id
 end)
 local p=Panel()
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end
-- The link the catalog stores for the own build (the saved record, read only).
local function StoredLink()
 local bundle=rawget(NexusDB,'authorityBundle')
 local builds=type(bundle)=='table' and bundle.communityBuilds or nil
 local row=type(builds)=='table' and builds[ownId] or nil
 return type(row)=='table' and row.link or nil,type(row)=='table'
end
-- The owner types a link: the field gets focus and the text arrives as input.
local function Type(box,text)
 box:SetFocus();box:SetText('');box:Insert(text)
 return box:_NexusRawText()
end
local function SaveAvailable(p)
 return p:IsShown() and p.linkSaveBtn:IsShown() and p.linkSaveBtn:IsEnabled()
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
local panel=ShowBuild(ownId)
C.setup(panel~=nil,'fixture: the own build is selected and shown in the detail pane')
local box=panel and panel.linkBox
C.setup(box~=nil and box:IsShown() and SaveAvailable(panel),'fixture: the owner-only link field and Save Link are available')
local stored,present=StoredLink()
C.setup(present and stored==nil and box and box:_NexusRawText()=='','fixture: the own build stores no link yet')

local function Background(tag,work)
 if not box then return end
 C.setup(Type(box,DRAFT)==DRAFT,tag..': fixture: the owner typed a draft link')
 work()
 local p=Panel()
 C.guard(p~=nil and p:IsShown() and p._nexusShownId==ownId and box._nexusBoundBuildId==ownId,
  tag..': the field stays bound to the same own build')
 print('OBSERVED',tag,'field='..printable(box:_NexusRawText()),'stored='..printable((StoredLink())))
 C.expect(box:_NexusRawText()==DRAFT,tag..': the unsaved draft survives the background refresh',box:_NexusRawText())
 C.guard((StoredLink())==nil,tag..': nothing was saved without Save Link',(StoredLink()))
end

C.scenario('W1 a DPS_CHANGED revision',function()
 Background('W1',function()
  Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='artificial link draft fixture'})
  for _=1,200 do H.Advance(.05,.05) end
 end)
end)

C.scenario('W2 a DPS record received for another character',function()
 Background('W2',function()
  local ok,why=fx:Receive('Bravo','dummy',{dps=31000})
  C.setup(ok==true,'W2: fixture: the record is received through the real receive path',why)
  for _=1,200 do H.Advance(.05,.05) end
 end)
end)

C.scenario('G1 selecting another build rebinds the field',function()
 if not box then return end
 Type(box,DRAFT)
 local other=ShowBuild(otherId)
 C.setup(other~=nil,'G1: fixture: another player\'s build is shown')
 C.guard(box._nexusBoundBuildId~=ownId and not SaveAvailable(Panel()),
  'G1: the field is no longer bound to the own build and Save Link is not offered',box._nexusBoundBuildId)
 C.guard(not box:IsVisible() or box:_NexusRawText()~=DRAFT,'G1: the other build does not show the draft',box:_NexusRawText())
 C.setup(ShowBuild(ownId)~=nil,'G1: fixture: the own build is shown again')
 C.guard(box._nexusBoundBuildId==ownId and box:_NexusRawText()==((StoredLink()) or ''),
  'G1: returning shows the stored link: the rebind discarded the draft',box:_NexusRawText())
 C.guard((StoredLink())==nil,'G1: nothing was saved',(StoredLink()))
end)

C.scenario('W3 Save Link after background work',function()
 if not box then return end
 C.setup(Type(box,DRAFT)==DRAFT,'W3: fixture: the owner typed a draft link')
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='artificial link draft fixture'})
 for _=1,200 do H.Advance(.05,.05) end
 C.guard((StoredLink())==nil,'W3: nothing was saved before Save Link',(StoredLink()))
 C.setup(SaveAvailable(Panel()),'W3: fixture: Save Link is offered')
 panel.linkSaveBtn:Click()
 Until(400,function() return StoredLink()~=nil end)
 print('OBSERVED','W3 stored after Save Link='..printable((StoredLink())))
 C.expect((StoredLink())==DRAFT,'W3: an explicit Save Link after the refresh saves the draft',(StoredLink()))
end)

C.scenario('G2 the character changes (ownership loss)',function()
 if not box then return end
 local before=StoredLink()
 Type(box,'https://discord.com/channels/4/5/6')
 local realUnitName=UnitName
 UnitName=function(unit,...)
  if unit==nil or unit=='player' then return 'DifferentPlayer','Ebonhold' end
  return realUnitName(unit,...)
 end
 local ok,err=pcall(function()
  Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='artificial ownership fixture'})
  for _=1,400 do H.Advance(.05,.05) end
  C.setup(CB.IsOwnBuild(ownId)==false,'G2: fixture: the build is no longer the current character\'s own build')
  -- The catalog re-admits for the new character on its own schedule, so the
  -- visible pane state is printed; the refused write below is the guard.
  local p=Panel()
  print('OBSERVED','G2 pane shown='..printable(p and p:IsShown()),'Save offered='..printable(p and SaveAvailable(p)),
   'field shown='..printable(box:IsVisible()),'field='..printable(box:_NexusRawText()))
  if p and p.linkSaveBtn:IsEnabled() then p.linkSaveBtn:Click() end
  for _=1,40 do H.Advance(.05,.05) end
 end)
 UnitName=realUnitName
 C.setup(ok,'G2: fixture: the ownership change ran',err)
 for _=1,400 do H.Advance(.05,.05) end
 C.guard((StoredLink())==before,'G2: Save Link writes no link for a build the character no longer owns',(StoredLink()))
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(an unsaved own link draft survives background refreshes; rebind and ownership loss reset or disable it)')
