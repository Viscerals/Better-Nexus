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
-- action.
-- UX-13 / LP-13 (EXPECT, fails at 6dcb46c): the generated description says
-- what its count is. Its numbers are CommunityController EchoProgress: the
-- assigned Wishlist's copies found in this Saved Build, not planned copies and
-- not copies rolled this run, so the canonical "planned" wording is read as
-- "a qualified unit", and the unit is the shared vocabulary's
-- UserText.COUNT_UNITS.savedBuild, "Wishlist copies in this Saved Build". A
-- generated description an earlier build left unqualified is described again
-- by an ordinary import whose signature does not change (D4, and D5 for a
-- title-only owner edit whose witness holds). Unchanged (GUARD): the counts,
-- ID, link, signature, assignment and unknown fields; the unassigned text; a
-- marked mirror without a witness that holds keeps its text, unqualified
-- legacy prose included (D6); no game, upload, send or assignment effect.
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
  or l:find(string.format('%d / %d',progress,total),1,true)~=nil
  or l:find(string.format('%d of %d',progress,total),1,true)~=nil
end

-- The shared count unit of the Wishlist's copies found in a Saved Build.
local SAVED_UNIT='Wishlist copies in this Saved Build'
-- Does the text give progress/total in that unit (its count is qualified)?
local function SaysUnit(text,progress,total)
 local l=V.Plain(text)
 if not Whole(progress) or not Whole(total) then return false end
 return l:find(string.format('%d/%d %s',progress,total,SAVED_UNIT),1,true)~=nil
  or l:find(string.format('%d / %d %s',progress,total,SAVED_UNIT),1,true)~=nil
end
-- The description CommunityController generated at 6dcb46c (no unit).
local function Legacy(name,progress,total)
 return string.format('Assigned Wishlist: %s - target progress (%d/%d).',name,progress,total)
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
local assigned=A.GetLoadoutWishlist(1)
C.setup(type(assigned)=='table' and assigned.name=='Gen plan','fixture: Saved Build 1 has the assigned Wishlist "Gen plan"',
 assigned and assigned.name)
C.setup(A.GetLoadoutWishlist(2)==nil,'fixture: Saved Build 2 has no assigned Wishlist')
C.setup(rawget(_G,'destinationName')==nil and rawget(_G,'destinationTotal')==nil,'fixture: no foreign global of those names')
C.guard(type(Nexus.UserText)=='table' and type(Nexus.UserText.COUNT_UNITS)=='table'
 and Nexus.UserText.COUNT_UNITS.savedBuild==SAVED_UNIT,'the shared count vocabulary names this unit "'..SAVED_UNIT..'"',
 Nexus.UserText and Nexus.UserText.COUNT_UNITS and Nexus.UserText.COUNT_UNITS.savedBuild)

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
 C.expect(SaysUnit(first.description,p,t),
  'D1: and qualifies that count: '..printable(p)..'/'..printable(t)..' '..SAVED_UNIT,first.description)
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
 C.expect(SaysUnit(shown,first.destinationProgress,first.destinationTotal),
  'D2: and the unit of that count, '..SAVED_UNIT,shown)
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

C.guard(#H.actions==0,'D1-D3: no game action: nothing was activated, saved or uploaded',#H.actions)

-- D4-D6: an earlier build's mirror read back in a later session. The saved
-- row of mirror 1 is changed between two sessions (an offline module reload
-- with round-tripped literal data, not a client reload); the fake server Saved
-- Builds are the same in both, so the later ordinary import has the same
-- signature. Artificial names, link and an unknown field.
local LINK='https://discord.com/channels/7/8/9'
local UNKNOWN='futureFieldUnknownHere'
local function Server(h)
 h.perks.serverBuildSlots={
  [1]={name='Artificial Saved Build',verified=true,echoes=h.Clone(F.PLAN)},
  [2]={name='Artificial Unassigned Build',verified=true,echoes=h.Clone(UNASSIGNED)},
 }
 h.perks.serverActiveSlot=1
end
-- The stored row of build `id` (the saved record).
local function StoredRow(id)
 local bundle=rawget(NexusDB,'authorityBundle')
 local builds=type(bundle)=='table' and bundle.communityBuilds or nil
 local row=type(builds)=='table' and id~=nil and builds[id] or nil
 return type(row)=='table' and row or nil
end
-- The game, upload, send, request and assignment effects so far.
local function Effects()
 local uploads=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploads=uploads+1 end end
 local links,names=Nexus.Store.State().loadoutWishlists or {},{}
 for slot,link in pairs(links) do names[#names+1]=tostring(slot)..'='..tostring(type(link)=='table' and link.name) end
 table.sort(names)
 return table.concat({#H.actions,uploads,#H.sent,tonumber(H.grantedRequests) or 0,table.concat(names,',')},'|')
end
-- Writes the earlier build's row into mirror 1, reloads and runs one ordinary
-- import; returns the mirror before and after and the detail pane text, or
-- nil when the fixture did not reach its state.
local function Session(tag,plant)
 C.setup(Until(2000,ImportIdle)~=nil,tag..': fixture: no Saved import is running before the reload')
 local was=Mirror(1)
 local row=was and StoredRow(was.id)
 C.setup(row~=nil,tag..': fixture: the saved row of mirror 1 exists')
 if not row then return nil end
 local p,t=was.destinationProgress,was.destinationTotal
 local legacy=Legacy('Gen plan',p,t)
 plant(row,legacy)
 row[UNKNOWN]='kept'
 local planted={description=row.description,userTitle=row.userTitle}
 print('OBSERVED',tag..' planted description='..printable(row.description),'userTitle='..printable(row.userTitle),
  'witness='..printable(row.generatedDescriptionWitness))
 H=F.Reload(Server)
 A,CB=Nexus.GameAdapter,Nexus.CommunityBuilds
 C.setup(Nexus.StartupStatus().coreReady==true,tag..': fixture: the later session reached core-ready')
 local before=Mirror(1) or {}
 C.setup(before.id==was.id and before.description==planted.description and before.userTitle==planted.userTitle,
  tag..": fixture: the later session serves the earlier build's mirror 1",printable(before.description))
 local effects,stats=Effects(),Import()
 CB.Show()
 C.setup(Until(2000,function()
  local now=Import()
  return now.pending~=true and Delta(now,stats,'completions')>0
 end)~=nil,tag..': fixture: opening the Build Library completes an ordinary Saved import')
 local after=Import()
 C.setup(Delta(after,stats,'finalizations')>=2,tag..': fixture: that import finalizes both Saved Builds',
  Delta(after,stats,'finalizations'))
 local m=Mirror(1) or {}
 CB.ShowBuild(m.id)
 local panel
 Until(2000,function()
  local f=NexusCommunityBuildsFrame
  panel=f and f._detailPanel
  return panel and panel:IsShown() and panel._nexusShownId==m.id
 end)
 C.setup(panel and panel:IsShown() and panel._nexusShownId==m.id,tag..': fixture: the detail pane shows mirror 1')
 local shown=V.Plain(panel and panel.desc and panel.desc:GetText() or '')
 print('OBSERVED',tag..' description='..printable(m.description),'witness='..printable(m.generatedDescriptionWitness),
  'detail='..shown,'writes='..Delta(after,stats,'writes'))
 C.guard(m.id==was.id and m._savedSignature==was._savedSignature
  and m.destinationWishlistName=='Gen plan' and m.destinationProgress==p and m.destinationTotal==t,
  tag..': the mirror keeps its ID, import signature, assigned Wishlist and counts '..printable(p)..'/'..printable(t),
  printable(m.id)..' '..printable(m.destinationProgress)..'/'..printable(m.destinationTotal))
 local stored=StoredRow(m.id) or {}
 C.guard(stored[UNKNOWN]=='kept',tag..': the saved row keeps an unknown field',stored[UNKNOWN])
 local other=Mirror(2) or {}
 C.guard(SaysUnassigned(other.description) and not V.Names(other.description,'Gen plan') and other.destinationWishlistName==nil,
  tag..': the unassigned mirror still says that no Wishlist is assigned',other.description)
 C.guard(Effects()==effects,tag..': the import performs no game action, upload, send, request or assignment change',
  effects..' -> '..Effects())
 return {mirror=m,shown=shown,p=p,t=t,legacy=legacy}
end

C.scenario('D4 an ordinary import qualifies the unqualified description an earlier build generated',function()
 local r=Session('D4',function(row,legacy)
  -- The earlier build generated this text on the unmarked mirror, with a
  -- witness, and the owner saved a link (a link-only save marks nothing).
  row.userTitle=nil;row.title='Artificial Saved Build';row.link=LINK
  row.description=legacy;row.generatedDescriptionWitness='0:'..legacy
 end)
 if not r then return end
 local m=r.mirror
 C.guard(m.link==LINK and m.userTitle==nil and m.title=='Artificial Saved Build',
  'D4: the saved link is kept and marks no owner edit',printable(m.link)..' / '..printable(m.userTitle))
 C.expect(SaysAssigned(m.description,'Gen plan',r.p,r.t) and SaysUnit(m.description,r.p,r.t),
  'D4: the generated description now names "Gen plan" at '..r.p..'/'..r.t..' '..SAVED_UNIT,m.description)
 C.guard(m.generatedDescriptionWitness=='0:'..tostring(m.description),
  'D4: with a witness of the text it generated',m.generatedDescriptionWitness)
 C.expect(SaysUnit(r.shown,r.p,r.t) and SaysAssigned(r.shown,'Gen plan',r.p,r.t),'D4: and the detail pane shows it',r.shown)
 -- A further ordinary import finds nothing to describe again.
 C.setup(Until(2000,ImportIdle)~=nil,'D4: fixture: no Saved import is running before the next one')
 local stats,kept=Import(),m.description
 CB.Hide();CB.Show()
 C.setup(Until(2000,function()
  local now=Import()
  return now.pending~=true and Delta(now,stats,'completions')>0
 end)~=nil,'D4: fixture: opening the Build Library again completes a new Saved import')
 local writes=Delta(Import(),stats,'writes')
 C.guard(writes==0 and (Mirror(1) or {}).description==kept,'D4: which writes nothing and keeps the text',writes)
end)

C.scenario('D5 an ordinary import qualifies it after a title-only owner edit whose witness holds',function()
 local TITLE='Artificial owner title'
 local r=Session('D5',function(row,legacy)
  row.userTitle=TITLE;row.title=TITLE;row.link=LINK
  row.description=legacy;row.generatedDescriptionWitness=#TITLE..':'..TITLE..legacy
 end)
 if not r then return end
 local m=r.mirror
 C.guard(m.title==TITLE and m.userTitle==TITLE and m.link==LINK,"D5: the owner's title and link are kept",printable(m.title))
 C.expect(SaysAssigned(m.description,'Gen plan',r.p,r.t) and SaysUnit(m.description,r.p,r.t),
  'D5: the generated description now says '..r.p..'/'..r.t..' '..SAVED_UNIT,m.description)
 C.guard(m.generatedDescriptionWitness==#TITLE..':'..TITLE..tostring(m.description),
  'D5: with a witness of that text under the owner title',m.generatedDescriptionWitness)
end)

C.scenario('D6 an ordinary import keeps unqualified text it cannot tell from an owner edit',function()
 local TITLE='Artificial earlier owner title'
 local r=Session('D6',function(row,legacy)
  -- An earlier build marked the mirror without a witness (as a link-only save
  -- once did): the text cannot be told from the owner's own.
  row.userTitle=TITLE;row.title=TITLE;row.link=LINK
  row.description=legacy;row.generatedDescriptionWitness=nil
 end)
 if not r then return end
 local m=r.mirror
 C.guard(m.description==r.legacy and m.title==TITLE and m.userTitle==TITLE and m.link==LINK
  and m.generatedDescriptionWitness==nil,'D6: the mirror keeps that text, its title, its link and no witness',m.description)
 C.guard(r.shown==V.Plain(r.legacy),'D6: and the detail pane shows the kept text',r.shown)
end)

C.guard(#H.actions==0,'no game action: nothing was activated, saved or uploaded',#H.actions)
C.finish('(a Saved Build mirror describes its assigned Wishlist in a qualified unit; owner text and the unassigned state are kept)')
