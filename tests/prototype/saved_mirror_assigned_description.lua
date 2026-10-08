-- F-S2-2 (P3), regression-first: a Saved Build mirror's generated description
-- states its assigned Wishlist. The Saved import (CommunityController
-- PrepareSavedSlot/FinalizeSavedSlot) computes the assigned Wishlist's name and
-- target progress for each server Saved Build and stores them on the mirror
-- (destinationWishlistName/destinationProgress/destinationTotal), but the
-- generated description reads names that are not in scope there, so every new
-- mirror says "No Wishlist assigned yet." while its card says the opposite.
-- Healthy behaviour (EXPECT, fails at the baseline): a newly imported mirror
-- of an assigned Saved Build has a generated description that names the
-- assigned Wishlist and its target progress (the stored progress/total), and
-- does not say that no Wishlist is assigned; the Build Library detail pane
-- shows that description.
-- Unchanged (GUARD, holds at the baseline): the stored assignment metadata; a
-- mirror of an unassigned Saved Build still says that no Wishlist is assigned
-- and names none; a description the owner wrote through the real edit path is
-- kept when opening the Build Library imports the Saved Builds again; no game
-- action. Older mirrors whose signature does not change are not required to
-- be rewritten.
-- The owner's text is read where the Build Library serves it, the mirror's
-- description: EditBuild writes it there and to userDescription, which is not
-- a catalog V1 field, so the catalog keeps that copy unserved and no read
-- returns it. An owner edit is seen through the served userTitle.
-- Real TOC boot, adapter, Saved import and Build Library window; the format-5
-- saved fixture (its Saved Build 1 association "Gen plan"). Artificial names.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('saved_mirror_assigned_description')
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

local function Until(limit,fn)
 for i=1,limit do
  if fn() then return i end
  H.Advance(.05,.05)
 end
 return nil
end

-- The Build Library's Saved import counters (CommunityController
-- SavedImportStats, through the facade's VirtualStats).
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

-- Does the text say that no Wishlist is assigned?
local function SaysUnassigned(text)
 local l=V.Plain(text):lower()
 return l:find('no wishlist',1,true)~=nil or l:find('not assigned',1,true)~=nil
  or l:find('unassigned',1,true)~=nil
end

-- Does the text name Wishlist `name` and the target progress progress/total?
local function Whole(n) return type(n)=='number' and n==math.floor(n) and n>=0 end

local function SaysAssigned(text,name,progress,total)
 local l=V.Plain(text)
 if not V.Names(l,name) or not Whole(progress) or not Whole(total) then return false end
 return l:find(string.format('%d/%d',progress,total),1,true)~=nil
  or l:find(string.format('%d of %d',progress,total),1,true)~=nil
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
local assigned=A.GetLoadoutWishlist(1)
C.setup(type(assigned)=='table' and assigned.name=='Gen plan','fixture: Saved Build 1 has the assigned Wishlist "Gen plan"',
 assigned and assigned.name)
C.setup(A.GetLoadoutWishlist(2)==nil,'fixture: Saved Build 2 has no assigned Wishlist')
C.setup(rawget(_G,'destinationName')==nil and rawget(_G,'destinationTotal')==nil,'fixture: no foreign global of those names')

local first,second
C.scenario('D1 a newly imported mirror of an assigned Saved Build',function()
 CB.Show()
 C.setup(Until(2000,function() return Mirror(1)~=nil and Mirror(2)~=nil end)~=nil,
  'D1: fixture: both Saved Builds are imported through the real Build Library facade')
 first,second=Mirror(1) or {},Mirror(2) or {}
 local p,t=first.destinationProgress,first.destinationTotal
 print('OBSERVED','D1 assigned='..printable(first.destinationWishlistName),'progress='..printable(p)..'/'..printable(t),
  'description='..printable(first.description),'unassigned description='..printable(second.description))
 C.guard(first.destinationWishlistName=='Gen plan','D1: the mirror keeps its assigned Wishlist name',first.destinationWishlistName)
 C.setup(Whole(p) and Whole(t) and t>0,'D1: fixture: the mirror carries whole target progress numbers',
  printable(p)..'/'..printable(t))
 C.setup(first.userTitle==nil and second.userTitle==nil,'D1: fixture: neither mirror has an owner edit')
 C.expect(SaysAssigned(first.description,'Gen plan',p,t),
  'D1: the generated description names the assigned Wishlist "Gen plan" and its target progress '..printable(p)..'/'..printable(t),
  first.description)
 C.expect(not SaysUnassigned(first.description),'D1: and does not say that no Wishlist is assigned',first.description)
 C.guard(SaysUnassigned(second.description),'D1: the mirror of the unassigned Saved Build says that no Wishlist is assigned',
  second.description)
 C.guard(not V.Names(second.description,'Gen plan'),'D1: and names no Wishlist',second.description)
 C.guard(second.destinationWishlistName==nil,'D1: and stores no assigned Wishlist',second.destinationWishlistName)
end)

C.scenario('D2 the detail pane of that mirror',function()
 local id=first and first.id
 C.setup(id~=nil,'D2: fixture: the mirror has an ID')
 if not id then return end
 CB.ShowBuild(id)
 local panel
 Until(2000,function()
  local f=NexusCommunityBuildsFrame
  panel=f and f._detailPanel
  return panel and panel:IsShown() and panel._nexusShownId==id
 end)
 C.setup(panel and panel:IsShown() and panel._nexusShownId==id,'D2: fixture: the Build Library detail pane shows the mirror')
 local shown=V.Plain(panel and panel.desc and panel.desc:GetText() or '')
 print('OBSERVED','D2 detail description='..shown)
 C.expect(SaysAssigned(shown,'Gen plan',first.destinationProgress,first.destinationTotal) and not SaysUnassigned(shown),
  'D2: the detail pane shows the assigned Wishlist and its progress',shown)
end)

C.scenario('D3 a user-authored description survives a later import',function()
 local mirror=Mirror(1)
 C.setup(mirror~=nil,'D3: fixture: the mirror of Saved Build 1 exists')
 if not mirror then return end
 C.setup(Until(2000,ImportIdle)~=nil,'D3: fixture: no Saved import is running before the edit')
 local NOTE='Artificial owner note for this Saved Build.'
 local ok,why=CB.EditBuild(mirror.id,mirror.title,NOTE,nil)
 C.setup(ok==true,'D3: fixture: the owner edits the description through the real edit path',why)
 C.setup(Until(2000,function() local m=Mirror(1) return m~=nil and m.description==NOTE and m.userTitle~=nil end)~=nil,
  'D3: fixture: the edit is saved and the Build Library serves the owner\'s text')
 C.setup(Until(2000,ImportIdle)~=nil,'D3: fixture: no Saved import is running after the edit')
 -- Opening the Build Library imports the server Saved Builds again: a new
 -- pass that reads the edited mirror and finalizes both Saved Builds.
 local before=Import()
 CB.Hide();CB.Show()
 C.setup(Until(2000,function()
  local now=Import()
  return now.pending~=true and Delta(now,before,'completions')>0
 end)~=nil,'D3: fixture: opening the Build Library again completes a new Saved import')
 local after=Import()
 C.setup(Delta(after,before,'finalizations')>=2,'D3: fixture: that import finalizes both Saved Builds',
  Delta(after,before,'finalizations'))
 local again,other=Mirror(1) or {},Mirror(2) or {}
 print('OBSERVED','D3 description='..printable(again.description),'title='..printable(again.title),
  'import writes='..Delta(after,before,'writes'))
 C.guard(again.description==NOTE,'D3: the mirror keeps the description its owner wrote',again.description)
 C.guard(again.destinationWishlistName=='Gen plan','D3: and its assigned Wishlist',again.destinationWishlistName)
 C.guard(SaysUnassigned(other.description) and other.userTitle==nil,
  'D3: the unassigned mirror still says that no Wishlist is assigned',other.description)
end)

C.guard(#H.actions==0,'no game action: nothing was activated, saved or uploaded',#H.actions)
C.finish('(a new Saved Build mirror describes its assigned Wishlist; owner text and the unassigned state are kept)')
