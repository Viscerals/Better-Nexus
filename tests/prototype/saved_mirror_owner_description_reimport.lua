-- F-S2-2 (P3) preservation, regression-first: a Saved Build mirror keeps the
-- description its owner wrote when a later Saved import rewrites the mirror
-- because the server Saved Build changed (here, its name). EditBuild writes
-- the owner's text to the mirror's description and marks the mirror with
-- userTitle; it also writes userDescription, which is not a catalog V1 field,
-- so no read serves it. The import (CommunityController FinalizeSavedSlot)
-- read only userDescription, so its rewrite replaced the owner's text.
-- Healthy behaviour (EXPECT, fails at the baseline): after the real edit and a
-- signature-changing re-import, the same mirror serves the owner's text, and
-- the Build Library detail pane shows it.
-- Unchanged (GUARD, holds at the baseline): the same mirror identity, its
-- owner-edit marker and the owner's title; its assigned Wishlist; the stored
-- row keeps its unserved userDescription (retained data, not the visible
-- text); a mirror without an owner edit is rewritten by the same import (its
-- title follows the server) and still says that no Wishlist is assigned; no
-- game action.
-- Real TOC boot, adapter, Saved import, edit path and Build Library window;
-- the format-5 saved fixture (its Saved Build 1 association "Gen plan").
-- Only the fake server Saved Build names change. Artificial names.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('saved_mirror_owner_description_reimport')
local UNASSIGNED={{spellId=200010,quality=2,stacks=1},{spellId=200011,quality=3,stacks=2}}
local H=F.Boot(F.Database(),function(h)
 h.perks.serverBuildSlots={
  [1]={name='Artificial Saved Build',verified=true,echoes=h.Clone(F.PLAN)},
  [2]={name='Artificial Unassigned Build',verified=true,echoes=h.Clone(UNASSIGNED)},
 }
 h.perks.serverActiveSlot=1
end)
local A=Nexus.GameAdapter
local CB=Nexus.CommunityBuilds
local RENAMED={[1]='Artificial Saved Build renamed',[2]='Artificial Unassigned Build renamed'}
local NOTE='Artificial owner note kept through a server rename.'

local function Until(limit,fn)
 for i=1,limit do
  if fn() then return i end
  H.Advance(.05,.05)
 end
 return nil
end

-- The Build Library's Saved import counters (through the facade's VirtualStats).
local function Import()
 local stats=CB.VirtualStats()
 return type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
end
local function ImportIdle() return Import().pending~=true end
local function Delta(after,before,key) return (tonumber(after[key]) or 0)-(tonumber(before[key]) or 0) end

-- The mirror of server Saved Build `slot`, as the real Build Library reads it.
local function Mirror(slot)
 local found
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==slot then found=b end
 end
 return found
end

local function SaysUnassigned(text)
 local l=V.Plain(text):lower()
 return l:find('no wishlist',1,true)~=nil or l:find('not assigned',1,true)~=nil
  or l:find('unassigned',1,true)~=nil
end

-- The stored row of build `id` (the saved record, read only).
local function StoredRow(id)
 local bundle=rawget(NexusDB,'authorityBundle')
 local builds=type(bundle)=='table' and bundle.communityBuilds or nil
 local row=type(builds)=='table' and builds[id] or nil
 return type(row)=='table' and row or nil
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
local assigned=A.GetLoadoutWishlist(1)
C.setup(type(assigned)=='table' and assigned.name=='Gen plan','fixture: Saved Build 1 has the assigned Wishlist "Gen plan"',
 assigned and assigned.name)
C.setup(A.GetLoadoutWishlist(2)==nil,'fixture: Saved Build 2 has no assigned Wishlist')

local edited,other
C.scenario('R1 the owner edits the mirror of Saved Build 1',function()
 CB.Show()
 C.setup(Until(2000,function() return Mirror(1)~=nil and Mirror(2)~=nil and ImportIdle() end)~=nil,
  'R1: fixture: both Saved Builds are imported through the real Build Library facade')
 local mirror=Mirror(1)
 other=Mirror(2)
 if not (mirror and other) then return end
 C.setup(mirror.userTitle==nil and other.userTitle==nil,'R1: fixture: neither mirror has an owner edit yet')
 local ok,why=CB.EditBuild(mirror.id,mirror.title,NOTE,nil)
 C.setup(ok==true,'R1: fixture: the owner edits the description through the real edit path',why)
 C.setup(Until(2000,function()
  local m=Mirror(1)
  return m~=nil and m.description==NOTE and m.userTitle~=nil and ImportIdle()
 end)~=nil,'R1: fixture: the Build Library serves the owner\'s text and the owner-edit marker')
 edited=Mirror(1)
end)

C.scenario('R2 a signature-changing re-import of both Saved Builds',function()
 C.setup(edited~=nil and other~=nil,'R2: fixture: the edited and the unedited mirror exist')
 if not (edited and other) then return end
 local before=Import()
 H.perks.serverBuildSlots[1].name=RENAMED[1]
 H.perks.serverBuildSlots[2].name=RENAMED[2]
 H.Notify();A.Poll()
 -- Opening the Build Library imports the server Saved Builds again.
 CB.Hide();CB.Show()
 C.setup(Until(2000,function()
  local one,two=Mirror(1),Mirror(2)
  return one~=nil and two~=nil and one.serverTitle==RENAMED[1] and two.serverTitle==RENAMED[2] and ImportIdle()
 end)~=nil,'R2: fixture: the re-import rewrites both mirrors with the renamed server Saved Builds')
 local after=Import()
 local again,second=Mirror(1) or {},Mirror(2) or {}
 print('OBSERVED','R2 description='..printable(again.description),'title='..printable(again.title),
  'userTitle='..printable(again.userTitle),'import writes='..Delta(after,before,'writes'))
 print('OBSERVED','R2 unedited title='..printable(second.title),'description='..printable(second.description))
 C.guard(again.id==edited.id,'R2: the same mirror identity',again.id)
 C.guard(again.userTitle==edited.userTitle,'R2: the owner-edit marker is kept',again.userTitle)
 C.guard(again.title==edited.title,'R2: the owner\'s title is kept; the server rename does not replace it',again.title)
 C.expect(again.description==NOTE,'R2: the mirror keeps the description its owner wrote',again.description)
 C.guard(again.destinationWishlistName=='Gen plan','R2: and its assigned Wishlist',again.destinationWishlistName)
 -- Retained data only: the unserved copy is not what the player reads.
 local stored=StoredRow(edited.id) or {}
 C.guard(stored.userDescription==NOTE,'R2: the stored row keeps the unserved userDescription the edit wrote',
  stored.userDescription)
 C.guard(second.id==other.id and second.userTitle==nil,'R2: the unedited mirror keeps its identity and has no owner edit',
  second.id)
 C.guard(second.title==RENAMED[2],'R2: the unedited mirror is rewritten: its title follows the server',second.title)
 C.guard(SaysUnassigned(second.description),'R2: and it still says that no Wishlist is assigned',second.description)
end)

C.scenario('R3 the detail pane of the edited mirror',function()
 local id=edited and edited.id
 C.setup(id~=nil,'R3: fixture: the edited mirror has an ID')
 if not id then return end
 CB.ShowBuild(id)
 local panel
 Until(2000,function()
  local f=NexusCommunityBuildsFrame
  panel=f and f._detailPanel
  return panel and panel:IsShown() and panel._nexusShownId==id
 end)
 C.setup(panel and panel:IsShown() and panel._nexusShownId==id,'R3: fixture: the Build Library detail pane shows the mirror')
 local shown=V.Plain(panel and panel.desc and panel.desc:GetText() or '')
 print('OBSERVED','R3 detail description='..shown)
 C.expect(shown:find(NOTE,1,true)~=nil,'R3: the detail pane shows the owner\'s description',shown)
end)

C.guard(#H.actions==0,'no game action: nothing was activated, saved or uploaded',#H.actions)
C.finish('(an owner-written Saved Build description survives a signature-changing re-import)')
