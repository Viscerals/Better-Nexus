-- Standards review STD-2 (P3), regression-first: a link-only Save Link on an
-- own Saved Build mirror must not turn the mirror's generated description and
-- server title into owner-written text.
-- Save Link (ui/CommunityRenderer.lua, Build Library detail pane) saves through
-- CommunityController EditBuild with the unchanged title and description, and
-- EditBuild marks every save of a Saved Build mirror as an owner edit
-- (userTitle, userDescription). When the server Saved Build then changes, the
-- Saved import (PrepareSavedSlot, FinalizeSavedSlot, SavedMirrorDescription)
-- keeps the title and the description of a marked mirror, so after a link-only
-- save the description keeps stating the old progress while the mirror's
-- stored progress is current.
-- Healthy behaviour (EXPECT, fails at 7013c49): after Save Link and a
-- signature-changing re-import (the server Saved Build now holds all 6 copies
-- of its assigned Wishlist "Gen plan" and is renamed), the served description
-- names "Gen plan" and 6/6 and no longer 4/6, the title is the new server
-- name, and the Build Library detail pane shows both; the saved link is kept
-- through the re-import.
-- Unchanged (GUARD, holds at 7013c49): before any link save, a re-import
-- rewrites the generated description for new progress (3/6 to 4/6); Save Link
-- saves the link and changes neither the description nor the title; the mirror
-- keeps its identity, server slot, assigned Wishlist, verified owner and record
-- and publication bindings, Save Link stays offered on it, and the served
-- mirror carries no unserved field; a title and a description the owner writes
-- in the real Edit dialog survive a server rename; no game action.
-- Not covered: a mirror marked before a repair (by an earlier link-only save or
-- the earlier description defect) cannot be told from an owner edit without a
-- text heuristic, so this test requires nothing of it.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, adapter, Saved import and Build Library window (detail pane,
-- link field, Save Link, Edit Build dialog); the format-5 saved fixture (Saved
-- Build 1's association "Gen plan"). Only the fake server Saved Builds change.
-- Artificial names and an artificial Discord-form link; nothing is sent.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('saved_mirror_link_only_description')
-- Server Saved Build 1 measured against its assigned Wishlist "Gen plan"
-- (F.PLAN: 200001 x2, 200002 x3, 200003 x1): 2+second of the 6 copies, or all
-- 6 with the third Echo.
local function Slot1(second,third)
 local rows={{spellId=200001,quality=1,stacks=2},{spellId=200002,quality=2,stacks=second}}
 if third then rows[3]={spellId=200003,quality=3,stacks=1} end
 return rows
end
local UNASSIGNED={{spellId=200010,quality=2,stacks=1},{spellId=200011,quality=3,stacks=2}}
local NAME={[1]='Artificial Saved Build',[2]='Artificial Second Build'}
local RENAMED={[1]='Artificial Saved Build renamed',[2]='Artificial Second Build renamed'}
local LINK='https://discord.com/channels/7/8/9'
local OWNER_TITLE,NOTE='Artificial owner title','Artificial owner note written in the Edit dialog.'
local H=F.Boot(F.Database(),function(h)
 h.perks.serverBuildSlots={
  [1]={name=NAME[1],verified=true,echoes=Slot1(1)},
  [2]={name=NAME[2],verified=true,echoes=h.Clone(UNASSIGNED)},
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

-- The Build Library's Saved import counters (through the facade's VirtualStats).
local function Import()
 local stats=CB.VirtualStats()
 return type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
end
local function ImportIdle() return Import().pending~=true end

-- The mirror of server Saved Build `slot`, as the real Build Library reads it.
local function Mirror(slot)
 local found
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==slot then found=b end
 end
 return found
end

-- The stored row of build `id` (the saved record, read only).
local function StoredRow(id)
 local bundle=rawget(NexusDB,'authorityBundle')
 local builds=type(bundle)=='table' and bundle.communityBuilds or nil
 local row=type(builds)=='table' and id~=nil and builds[id] or nil
 return type(row)=='table' and row or nil
end

-- Does the text state progress progress/total ("p/t" or "p of t")?
local function StatesProgress(text,progress,total)
 local l=V.Plain(text)
 return l:find(string.format('%d/%d',progress,total),1,true)~=nil
  or l:find(string.format('%d of %d',progress,total),1,true)~=nil
end
-- Does the text name Wishlist `name` and the progress progress/total?
local function SaysAssigned(text,name,progress,total)
 return V.Names(text,name) and StatesProgress(text,progress,total)
end

-- The server Saved Builds change; opening the Build Library again imports
-- them again (as in saved_mirror_owner_description_reimport).
local function ServerChange(change)
 change(H.perks.serverBuildSlots)
 H.Notify();A.Poll()
 CB.Hide();CB.Show()
end

local function Panel()
 local f=NexusCommunityBuildsFrame
 return f and f._detailPanel
end
-- Select build `id` in the Build Library and wait for its detail pane.
local function ShowBuild(id)
 CB.ShowBuild(id)
 Until(2000,function()
  local p=Panel()
  return p and p:IsShown() and p._nexusShownId==id and ImportIdle()
 end)
 local p=Panel()
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end

-- The owner types into a field: it gets focus and the text arrives as input.
local function Type(box,text)
 box:SetFocus();box:SetText('');box:Insert(text)
 return box:_NexusRawText()
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
local assigned=A.GetLoadoutWishlist(1)
C.setup(type(assigned)=='table' and assigned.name=='Gen plan','fixture: Saved Build 1 has the assigned Wishlist "Gen plan"',
 assigned and assigned.name)
C.setup(A.GetLoadoutWishlist(2)==nil,'fixture: Saved Build 2 has no assigned Wishlist')

local id1,id2,linked
C.scenario('A the generated description follows the server before any link save',function()
 CB.Show()
 C.setup(Until(2000,function() return Mirror(1)~=nil and Mirror(2)~=nil and ImportIdle() end)~=nil,
  'A: fixture: both Saved Builds are imported through the real Build Library facade')
 local one,two=Mirror(1) or {},Mirror(2) or {}
 id1,id2=one.id,two.id
 print('OBSERVED','A first import description='..printable(one.description),
  'progress='..printable(one.destinationProgress)..'/'..printable(one.destinationTotal))
 C.setup(one.destinationProgress==3 and one.destinationTotal==6 and SaysAssigned(one.description,'Gen plan',3,6),
  'A: fixture: the mirror of Saved Build 1 has the generated description of "Gen plan" at 3/6',one.description)
 C.setup(one.userTitle==nil and two.userTitle==nil,'A: fixture: neither mirror has an owner edit')
 ServerChange(function(slots) slots[1].echoes=Slot1(2) end)
 C.setup(Until(2000,function()
  local m=Mirror(1)
  return m~=nil and m.destinationProgress==4 and ImportIdle()
 end)~=nil,'A: fixture: a re-import stores the new progress 4/6 on the mirror')
 local again=Mirror(1) or {}
 print('OBSERVED','A re-import description='..printable(again.description),'title='..printable(again.title))
 C.guard(again.id==id1 and SaysAssigned(again.description,'Gen plan',4,6) and not StatesProgress(again.description,3,6),
  'A: without an owner edit, the re-import rewrites the generated description for 4/6',again.description)
 C.guard(again.title==NAME[1],'A: and the title is the server name',again.title)
end)

C.scenario('L1 Save Link on the own mirror in the Build Library detail pane',function()
 C.setup(id1~=nil,'L1: fixture: the mirror of Saved Build 1 has an ID')
 if not id1 then return end
 local panel=ShowBuild(id1)
 C.setup(panel~=nil,'L1: fixture: the Build Library detail pane shows the mirror')
 if not panel then return end
 local box=panel.linkBox
 C.setup(box~=nil and box:IsShown() and box._nexusBoundBuildId==id1 and panel.linkSaveBtn:IsShown()
  and panel.linkSaveBtn:IsEnabled(),'L1: fixture: the owner-only link field and Save Link are offered for the own mirror')
 if not box then return end
 local before=Mirror(1) or {}
 C.setup(before.link==nil and (StoredRow(id1) or {}).link==nil,'L1: fixture: the mirror has no link yet')
 C.setup(Type(box,LINK)==LINK,'L1: fixture: the owner typed a link into the field')
 panel.linkSaveBtn:Click()
 C.setup(Until(2000,function()
  local m=Mirror(1)
  return m~=nil and m.link==LINK and ImportIdle()
 end)~=nil,'L1: fixture: Save Link saved the link and the Build Library serves it',(Mirror(1) or {}).link)
 local after=Mirror(1) or {}
 print('OBSERVED','L1 after Save Link description='..printable(after.description),'title='..printable(after.title),
  'stored link='..printable((StoredRow(id1) or {}).link))
 C.guard(after.description==before.description,'L1: Save Link leaves the description as it was',after.description)
 C.guard(after.title==before.title,'L1: and the title',after.title)
 C.guard(after.id==id1 and CB.IsOwnBuild(id1)==true,"L1: the mirror keeps its identity and stays the character's own")
 linked=after
end)

C.scenario('L2 a signature-changing re-import after the link save',function()
 local before=linked
 C.setup(before~=nil,'L2: fixture: the link was saved')
 if not before then return end
 ServerChange(function(slots) slots[1].echoes=Slot1(3,true);slots[1].name=RENAMED[1] end)
 C.setup(Until(2000,function()
  local m=Mirror(1)
  return m~=nil and m.serverTitle==RENAMED[1] and m.destinationProgress==6 and ImportIdle()
 end)~=nil,'L2: fixture: the re-import rewrites the mirror with the renamed server Saved Build')
 local again=Mirror(1) or {}
 print('OBSERVED','L2 description='..printable(again.description),'title='..printable(again.title),
  'progress='..printable(again.destinationProgress)..'/'..printable(again.destinationTotal),
  'link='..printable(again.link),'stored link='..printable((StoredRow(id1) or {}).link))
 C.setup(again.destinationProgress==6 and again.destinationTotal==6,'L2: fixture: the mirror stores the current progress 6/6',
  printable(again.destinationProgress)..'/'..printable(again.destinationTotal))
 C.expect(SaysAssigned(again.description,'Gen plan',6,6),
  'L2: the description names the assigned Wishlist "Gen plan" and its current progress 6/6',again.description)
 C.expect(not StatesProgress(again.description,4,6),'L2: and no longer states the earlier progress 4/6',again.description)
 C.expect(again.title==RENAMED[1],'L2: the title follows the server rename: a link save wrote no owner title',again.title)
 C.expect(again.link==LINK,'L2: the saved link is kept through the re-import',again.link)
 C.guard(again.id==id1 and again.importedSavedBuild==true and tonumber(again.serverSlot)==1,
  'L2: the same mirror identity and server slot',again.id)
 C.guard(again.destinationWishlistName=='Gen plan','L2: and its assigned Wishlist',again.destinationWishlistName)
 C.guard(CB.IsOwnBuild(id1)==true and again.ownerKey==F.OWNER and again.ownerVerified==true and again.isMine==true,
  "L2: it stays the character's own verified mirror",printable(again.ownerKey)..'/'..printable(again.ownerVerified))
 C.guard(again.recordBuildId==before.recordBuildId and again.publishedBuildId==before.publishedBuildId,
  'L2: its record and publication bindings are unchanged',printable(again.recordBuildId)..'/'..printable(again.publishedBuildId))
 C.guard(again.userDescription==nil,'L2: the served mirror carries no unserved field (userDescription)',again.userDescription)
end)

C.scenario('L3 the detail pane after the re-import',function()
 C.setup(id1~=nil,'L3: fixture: the mirror has an ID')
 if not id1 then return end
 local panel=ShowBuild(id1)
 C.setup(panel~=nil,'L3: fixture: the Build Library detail pane shows the mirror')
 if not panel then return end
 local shown=V.Plain(panel.desc and panel.desc:GetText() or '')
 local title=V.Plain(panel.title and panel.title:GetText() or '')
 local field=panel.linkBox and panel.linkBox:IsShown() and panel.linkBox:_NexusRawText() or nil
 print('OBSERVED','L3 detail title='..title,'description='..shown,'link field='..printable(field))
 C.expect(SaysAssigned(shown,'Gen plan',6,6) and not StatesProgress(shown,4,6),
  'L3: the detail pane shows the assigned Wishlist and the current progress 6/6, not 4/6',shown)
 C.expect(title==RENAMED[1],'L3: and the server name as the title',title)
 C.guard(panel.linkSaveBtn:IsShown() and panel.linkSaveBtn:IsEnabled(),'L3: Save Link is still offered on the own mirror')
end)

C.scenario('G1 an owner edit in the real Edit dialog survives a server rename',function()
 C.setup(id2~=nil,'G1: fixture: the mirror of Saved Build 2 has an ID')
 if not id2 then return end
 local panel=ShowBuild(id2)
 C.setup(panel~=nil and panel.editBtn:IsShown() and panel.editBtn:IsEnabled(),
  'G1: fixture: the detail pane offers Edit Build for the own mirror')
 if not panel then return end
 panel.editBtn:Click()
 local popup=NexusEditPopup
 C.setup(popup~=nil and popup:IsShown() and popup._editingId==id2,'G1: fixture: the Edit dialog opens for that mirror')
 if not (popup and popup:IsShown()) then return end
 C.setup(Type(popup._editTitleBox,OWNER_TITLE)==OWNER_TITLE and Type(popup._editDescBox,NOTE)==NOTE,
  'G1: fixture: the owner typed a title and a description')
 popup._saveBtn:Click()
 C.setup(Until(2000,function()
  local m=Mirror(2)
  return m~=nil and m.title==OWNER_TITLE and m.description==NOTE and ImportIdle()
 end)~=nil,'G1: fixture: Save Details saved both and the Build Library serves them')
 ServerChange(function(slots) slots[2].name=RENAMED[2] end)
 C.setup(Until(2000,function()
  local m=Mirror(2)
  return m~=nil and m.serverTitle==RENAMED[2] and ImportIdle()
 end)~=nil,'G1: fixture: the re-import rewrites the mirror with the renamed server Saved Build')
 local again=Mirror(2) or {}
 print('OBSERVED','G1 title='..printable(again.title),'description='..printable(again.description))
 C.guard(again.id==id2 and again.description==NOTE,'G1: the description the owner wrote is kept',again.description)
 C.guard(again.title==OWNER_TITLE,'G1: and the title the owner wrote',again.title)
 local shown=ShowBuild(id2)
 local text=V.Plain(shown and shown.desc and shown.desc:GetText() or '')
 C.guard(text:find(NOTE,1,true)~=nil,"G1: the detail pane shows the owner's description",text)
end)

C.guard(#H.actions==0,'no game action: nothing was activated, saved or uploaded',#H.actions)
C.finish('(a link-only Save Link keeps a Saved Build mirror description truthful; owner edits and the link are kept)')
