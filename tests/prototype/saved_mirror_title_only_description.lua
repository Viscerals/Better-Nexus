-- Spec review SPEC-R2-1 (P3), regression-first: a title-only owner edit of a
-- Saved Build mirror must not freeze the mirror's generated description.
-- The Build Library's Edit dialog (ui/CommunityRenderer.lua, Save Details)
-- submits the title and the description as they stand. CommunityController
-- EditBuild marks a Saved Build mirror as owner-written (userTitle) when either
-- text changes, and the Saved import (PrepareSavedSlot, SavedMirrorDescription)
-- keeps the title and the description of a marked mirror. So after the owner
-- changes only the title, the untouched generated description keeps stating the
-- progress at the time of the edit, while the mirror's stored progress (its
-- card line) follows the server.
-- Healthy behaviour (EXPECT, fails at 067d6ab): after the title-only edit at
-- 4/6 and a signature-changing re-import (the server Saved Build now holds all 6
-- copies of its assigned Wishlist "Gen plan"), the served description names
-- "Gen plan" and 6/6 and no longer states 4/6, and the Build Library detail
-- pane shows it.
-- Unchanged (GUARD, holds at 067d6ab): before any edit the same re-import
-- rewrites the generated description (3/6 to 4/6); the owner's changed title,
-- the saved link, the mirror identity, server slot, assigned Wishlist, verified
-- owner and record/publication bindings are kept; a title and a description the
-- owner wrote (mirror 2) and a description the owner wrote (mirror 3) are kept
-- through a progress change and a server rename; two mirrors whose author marker
-- an earlier build left keep that marker, their title and their description
-- exactly (mirror 4: a 7013c49 Save Link over its generated text; mirror 5: a
-- b704660 save over the "No Wishlist assigned yet." b704660 gave every mirror).
-- Such a marker cannot be told from an owner edit without guessing from the
-- text, and it is not reclassified (the FINAL_REPAIR_SPEC-r2 residual). The
-- Saved Build assignments are unchanged; no game action.
-- Observed only, required neither way: mirror 3's title after the rename. A
-- description-only edit freezing the generated title is pre-existing at
-- b704660; saved_mirror_owner_description_reimport pins it and is unchanged.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, adapter, Saved import and Build Library window (detail pane,
-- link field, Save Link, Edit Build dialog); the format-5 saved fixture (Saved
-- Build 1's "Gen plan") with artificial assignments of Saved Builds 2-5 in the
-- same record shape. The earlier-build markers are written into the saved
-- bundle rows between two sessions (an offline module reload with round-tripped
-- literal data, not a client reload). Only the fake server Saved Builds change.
-- Artificial names and an artificial Discord-form link; nothing is sent.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('saved_mirror_title_only_description')

-- An Echo row of harness Echo `id`, with the quality the harness catalog gives it.
local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end
-- Server Saved Build 1 measured against its assigned Wishlist "Gen plan"
-- (F.PLAN: 200001 x2, 200002 x3, 200003 x1): 2+second of the 6 copies, or all
-- 6 with the third Echo.
local function Slot1(second,third)
 local rows={E(200001,2),E(200002,second)}
 if third then rows[3]=E(200003,1) end
 return rows
end
-- The Wishlists assigned to Saved Builds 2-5, stored in the record shape the
-- fixture gives "Gen plan" (F.Row): slot, content key, name and Echo rows.
local PLAN={
 [2]={name='Side plan',echoes={E(200004,2),E(200005,2)}},
 [3]={name='Third plan',echoes={E(200006,2),E(200007,1)}},
 [4]={name='Fourth plan',echoes={E(200008,2),E(200009,2)}},
 [5]={name='Fifth plan',echoes={E(200012,1),E(200013,2)}},
}
local function PlanName(slot) return slot==1 and 'Gen plan' or PLAN[slot].name end
local function AddPlans(db)
 local links=db.chars[F.NAME].loadoutWishlists
 for slot,plan in pairs(PLAN) do
  local echoes={}
  for i,e in ipairs(plan.echoes) do echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=false} end
  links[slot]={slot=slot,key=F.Key(echoes),name=plan.name,echoes=echoes}
 end
end
-- The server Saved Builds as they start and after scenario S, and the progress
-- each gives against its assigned Wishlist (copies held, copies planned).
local NAME={'Artificial Saved Build','Artificial Second Build','Artificial Third Build',
 'Artificial Fourth Build','Artificial Fifth Build'}
local function Renamed(slot) return NAME[slot]..' renamed' end
local FIRST={Slot1(1),{E(200004,1),E(200005,1)},{E(200006,1)},{E(200008,1)},{E(200012,1)}}
local LATER={Slot1(3,true),{E(200004,2),E(200005,1)},{E(200006,2)},{E(200008,2),E(200009,1)},{E(200012,1),E(200013,1)}}
local AT_FIRST={{3,6},{2,4},{1,3},{1,4},{1,3}}
local AT_LATER={{6,6},{3,4},{2,3},{3,4},{2,3}}
local function Server(h)
 local slots={}
 for slot=1,5 do slots[slot]={name=NAME[slot],verified=true,echoes=h.Clone(FIRST[slot])} end
 h.perks.serverBuildSlots=slots
 h.perks.serverActiveSlot=1
end
local LINK='https://discord.com/channels/7/8/9'
local OWNER_TITLE='Artificial owner title'
local OWNER_TITLE2,NOTE2='Artificial second owner title','Artificial owner note on the second Saved Build.'
local NOTE3='Artificial owner note on the third Saved Build.'
-- What b704660's Saved import gave every mirror (its generated description
-- read names that were not in scope there), and so the text its saves marked.
local B704660_TEXT='No Wishlist assigned yet.'

local H=F.Boot(F.Database({mutate=AddPlans}),Server)
local A,CB=Nexus.GameAdapter,Nexus.CommunityBuilds

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
local function AllMirrors()
 for slot=1,5 do if not Mirror(slot) then return false end end
 return true
end

-- The stored row of build `id` (the saved record).
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

-- The Saved Build Wishlist assignments: each stored record's name and content
-- key, and the Wishlist the adapter resolves for that Saved Build.
local function Assignments()
 local state=Nexus.Store.State() or {}
 local links=type(state.loadoutWishlists)=='table' and state.loadoutWishlists or {}
 local out={}
 for slot=1,5 do
  local stored=type(links[slot])=='table' and links[slot] or {}
  local linked=A.GetLoadoutWishlist(slot) or {}
  out[#out+1]=table.concat({slot,printable(stored.name),printable(stored.key),printable(linked.name)},'/')
 end
 return table.concat(out,' ')
end

-- The server Saved Builds change; opening the Build Library again imports
-- them again (as in saved_mirror_link_only_description).
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

-- Open the real Edit dialog of build `id` with its detail pane's Edit Build.
local function OpenEdit(tag,id)
 local panel=ShowBuild(id)
 C.setup(panel~=nil and panel.editBtn:IsShown() and panel.editBtn:IsEnabled(),
  tag..': fixture: the detail pane offers Edit Build for the own mirror')
 if not panel then return nil end
 panel.editBtn:Click()
 local popup=NexusEditPopup
 local open=popup~=nil and popup:IsShown() and popup._editingId==id
 C.setup(open,tag..': fixture: the Edit dialog opens for that mirror')
 return open and popup or nil
end
-- Save Details, then wait until the Build Library serves what `saved` accepts.
local function SaveDetails(tag,popup,slot,saved)
 popup._saveBtn:Click()
 C.setup(Until(2000,function()
  local m=Mirror(slot)
  return m~=nil and saved(m) and ImportIdle()
 end)~=nil,tag..': fixture: Save Details saved the text and the Build Library serves it')
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
for slot=1,5 do
 local linked=A.GetLoadoutWishlist(slot)
 C.setup(type(linked)=='table' and linked.name==PlanName(slot),
  'fixture: Saved Build '..slot..' has the assigned Wishlist "'..PlanName(slot)..'"',linked and linked.name)
end
local ASSIGNED=Assignments()

local ids,planted={},{}
C.scenario('P the first session; earlier builds left author markers on mirrors 4 and 5',function()
 CB.Show()
 C.setup(Until(2000,function() return AllMirrors() and ImportIdle() end)~=nil,
  'P: fixture: the five Saved Builds are imported through the real Build Library facade')
 for slot=1,5 do
  local m=Mirror(slot) or {}
  ids[slot]=m.id
  C.setup(m.userTitle==nil and SaysAssigned(m.description,PlanName(slot),AT_FIRST[slot][1],AT_FIRST[slot][2]),
   'P: fixture: mirror '..slot..' has the generated description of "'..PlanName(slot)..'" at '
   ..AT_FIRST[slot][1]..'/'..AT_FIRST[slot][2]..' and no owner edit',m.description)
 end
 C.guard(#H.actions==0,'P: no game action in the first session',#H.actions)
 -- An earlier build's Save Link (its EditBuild marked every save) wrote the
 -- served title and description as userTitle and userDescription: 7013c49
 -- over its generated text (mirror 4), b704660 over its generated sentence
 -- (mirror 5).
 local four,five=StoredRow(ids[4]),StoredRow(ids[5])
 C.setup(four~=nil and five~=nil,'P: fixture: the saved rows of mirrors 4 and 5 exist')
 if not (four and five) then return end
 four.userTitle,four.userDescription=four.title,four.description
 five.description=B704660_TEXT
 five.userTitle,five.userDescription=five.title,five.description
 planted[4]={userTitle=four.userTitle,title=four.title,description=four.description}
 planted[5]={userTitle=five.userTitle,title=five.title,description=five.description}
 print('OBSERVED','P marker 4 title='..printable(four.title),'description='..printable(four.description))
 print('OBSERVED','P marker 5 title='..printable(five.title),'description='..printable(five.description))
end)

C.scenario('R the second session reads the saved data back',function()
 C.setup(planted[4]~=nil and planted[5]~=nil,'R: fixture: the earlier-build markers were written')
 H=F.Reload(Server)
 A,CB=Nexus.GameAdapter,Nexus.CommunityBuilds
 C.setup(Nexus.StartupStatus().coreReady==true,'R: fixture: the second session reached core-ready')
 C.setup(Assignments()==ASSIGNED,'R: fixture: the Saved Build assignments read back unchanged',Assignments())
end)

C.scenario('Q the second session imports the Saved Builds',function()
 CB.Show()
 C.setup(Until(2000,function()
  local s=Import()
  return (tonumber(s.completions) or 0)>0 and s.pending~=true and AllMirrors()
 end)~=nil,'Q: fixture: the second session completes a Saved import of the five Saved Builds')
 for slot=1,5 do
  local m=Mirror(slot) or {}
  C.setup(ids[slot]~=nil and m.id==ids[slot],'Q: fixture: mirror '..slot..' keeps its identity through the reload',m.id)
 end
 for slot=4,5 do
  local m,p=Mirror(slot) or {},planted[slot] or {}
  C.setup(p.userTitle~=nil and m.userTitle==p.userTitle and m.title==p.title and m.description==p.description,
   'Q: fixture: mirror '..slot..' serves the author marker an earlier build left',
   printable(m.userTitle)..' / '..printable(m.description))
 end
end)

C.scenario('A before any edit, a re-import rewrites the generated description',function()
 ServerChange(function(slots) slots[1].echoes=Slot1(2) end)
 C.setup(Until(2000,function()
  local m=Mirror(1)
  return m~=nil and m.destinationProgress==4 and ImportIdle()
 end)~=nil,'A: fixture: a re-import stores the new progress 4/6 on mirror 1')
 local m=Mirror(1) or {}
 print('OBSERVED','A description='..printable(m.description),'title='..printable(m.title))
 C.guard(m.id==ids[1] and SaysAssigned(m.description,'Gen plan',4,6) and not StatesProgress(m.description,3,6),
  'A: without an owner edit, the re-import rewrites the generated description for 4/6',m.description)
 C.guard(m.title==NAME[1],'A: and the title is the server name',m.title)
end)

C.scenario('L the owner saves a link on mirror 1',function()
 local panel=ShowBuild(ids[1])
 C.setup(panel~=nil,'L: fixture: the Build Library detail pane shows mirror 1')
 if not panel then return end
 local box=panel.linkBox
 C.setup(box~=nil and box:IsShown() and box._nexusBoundBuildId==ids[1] and panel.linkSaveBtn:IsShown()
  and panel.linkSaveBtn:IsEnabled(),'L: fixture: the owner-only link field and Save Link are offered for the own mirror')
 if not box then return end
 C.setup(Type(box,LINK)==LINK,'L: fixture: the owner typed a link into the field')
 panel.linkSaveBtn:Click()
 C.setup(Until(2000,function()
  local m=Mirror(1)
  return m~=nil and m.link==LINK and ImportIdle()
 end)~=nil,'L: fixture: Save Link saved the link and the Build Library serves it',(Mirror(1) or {}).link)
 local m=Mirror(1) or {}
 C.setup(m.userTitle==nil and m.title==NAME[1] and SaysAssigned(m.description,'Gen plan',4,6),
  'L: fixture: the link save marked no owner edit and changed no text',printable(m.userTitle))
end)

local edited
C.scenario('T the owner changes only the title of mirror 1 in the real Edit dialog',function()
 local before=Mirror(1) or {}
 local popup=OpenEdit('T',ids[1])
 if not popup then return end
 local title,desc=popup._editTitleBox,popup._editDescBox
 C.setup(title:_NexusRawText()==before.title and desc:_NexusRawText()==before.description,
  'T: fixture: the dialog opens with the served title and the generated description',desc:_NexusRawText())
 C.setup(Type(title,OWNER_TITLE)==OWNER_TITLE,'T: fixture: the owner typed a new title')
 C.setup(desc:_NexusRawText()==before.description,
  'T: fixture: the description field still holds the generated description, untouched',desc:_NexusRawText())
 SaveDetails('T',popup,1,function(m) return m.title==OWNER_TITLE end)
 local m=Mirror(1) or {}
 print('OBSERVED','T after Save Details title='..printable(m.title),'description='..printable(m.description),
  'userTitle='..printable(m.userTitle),'link='..printable(m.link))
 C.setup(m.description==before.description and m.destinationProgress==4,
  'T: fixture: the saved description is the unchanged generated one at 4/6',m.description)
 C.guard(m.link==LINK,'T: the title edit keeps the saved link',m.link)
 edited=m.title==OWNER_TITLE and m or nil
end)

C.scenario('O the owner writes texts on mirrors 2 and 3 in the real Edit dialog',function()
 local popup=OpenEdit('O2',ids[2])
 if popup then
  C.setup(Type(popup._editTitleBox,OWNER_TITLE2)==OWNER_TITLE2 and Type(popup._editDescBox,NOTE2)==NOTE2,
   'O2: fixture: the owner typed a title and a description')
  SaveDetails('O2',popup,2,function(m) return m.title==OWNER_TITLE2 and m.description==NOTE2 end)
 end
 popup=OpenEdit('O3',ids[3])
 if popup then
  C.setup(Type(popup._editDescBox,NOTE3)==NOTE3,'O3: fixture: the owner typed a description and left the title')
  SaveDetails('O3',popup,3,function(m) return m.description==NOTE3 end)
  C.setup((Mirror(3) or {}).title==NAME[3],'O3: fixture: the title is still the server name',(Mirror(3) or {}).title)
 end
end)

C.scenario('S a signature-changing re-import of the five Saved Builds',function()
 C.setup(edited~=nil,'S: fixture: the title-only edit of mirror 1 was saved')
 local bound=Mirror(1) or {}
 ServerChange(function(slots)
  for slot=1,5 do
   slots[slot].echoes=H.Clone(LATER[slot])
   if slot>1 then slots[slot].name=Renamed(slot) end
  end
 end)
 C.setup(Until(2000,function()
  for slot=1,5 do
   local m=Mirror(slot)
   if not (m and m.destinationProgress==AT_LATER[slot][1]) then return false end
   if slot>1 and m.serverTitle~=Renamed(slot) then return false end
  end
  return ImportIdle()
 end)~=nil,'S: fixture: the re-import stores every mirror\'s new progress and the renamed Saved Builds 2-5')
 local one=Mirror(1) or {}
 print('OBSERVED','S mirror 1 description='..printable(one.description),'title='..printable(one.title),
  'progress='..printable(one.destinationProgress)..'/'..printable(one.destinationTotal),'link='..printable(one.link))
 C.setup(one.destinationProgress==6 and one.destinationTotal==6,
  'S: fixture: mirror 1 stores the current progress 6/6 (what its card line states)',
  printable(one.destinationProgress)..'/'..printable(one.destinationTotal))
 C.expect(SaysAssigned(one.description,'Gen plan',6,6),
  'S: mirror 1 describes its assigned Wishlist "Gen plan" at the current 6/6',one.description)
 C.expect(not StatesProgress(one.description,4,6),
  'S: and no longer states 4/6, the progress when its owner changed only the title',one.description)
 C.guard(one.title==OWNER_TITLE,"S: the owner's changed title is kept",one.title)
 C.guard(one.link==LINK,'S: the saved link is kept through the re-import',one.link)
 C.guard(one.id==ids[1] and one.importedSavedBuild==true and tonumber(one.serverSlot)==1,
  'S: the same mirror identity and server slot',one.id)
 C.guard(one.destinationWishlistName=='Gen plan','S: and its assigned Wishlist',one.destinationWishlistName)
 C.guard(CB.IsOwnBuild(ids[1])==true and one.ownerKey==F.OWNER and one.ownerVerified==true and one.isMine==true,
  "S: it stays the character's own verified mirror",printable(one.ownerKey)..'/'..printable(one.ownerVerified))
 C.guard(one.recordBuildId==bound.recordBuildId and one.publishedBuildId==bound.publishedBuildId,
  'S: its record and publication bindings are unchanged',printable(one.recordBuildId)..'/'..printable(one.publishedBuildId))
 C.guard(one.userDescription==nil,'S: the served mirror carries no unserved field (userDescription)',one.userDescription)
 local two,three=Mirror(2) or {},Mirror(3) or {}
 print('OBSERVED','S mirror 2 title='..printable(two.title),'description='..printable(two.description))
 print('OBSERVED','S mirror 3 (description-only edit) title='..printable(three.title),
  'server title='..printable(three.serverTitle),'description='..printable(three.description))
 C.guard(two.title==OWNER_TITLE2,'S: the title the owner wrote on mirror 2 is kept through its rename',two.title)
 C.guard(two.description==NOTE2,'S: and the description the owner wrote, through its progress change',two.description)
 C.guard(three.description==NOTE3,'S: the description the owner wrote on mirror 3 is kept',three.description)
 local kept=true
 for slot=1,5 do kept=kept and (Mirror(slot) or {}).destinationWishlistName==PlanName(slot) end
 C.guard(kept,'S: every mirror keeps its assigned Wishlist')
 for slot=4,5 do
  local m,p=Mirror(slot) or {},planted[slot] or {}
  print('OBSERVED','S mirror '..slot..' (earlier-build marker) title='..printable(m.title),
   'description='..printable(m.description),
   'progress='..printable(m.destinationProgress)..'/'..printable(m.destinationTotal))
  C.guard(p.userTitle~=nil and m.userTitle==p.userTitle,
   'S: mirror '..slot..' keeps the author marker an earlier build left',m.userTitle)
  C.guard(p.title~=nil and m.title==p.title,'S: and the title it marked',m.title)
  C.guard(p.description~=nil and m.description==p.description,
   'S: and the description it marked: an already-ambiguous marker is not reclassified from its text',m.description)
 end
end)

C.scenario('D the detail pane after the re-import',function()
 local panel=ShowBuild(ids[1])
 C.setup(panel~=nil,'D: fixture: the Build Library detail pane shows mirror 1')
 if not panel then return end
 local shown=V.Plain(panel.desc and panel.desc:GetText() or '')
 local title=V.Plain(panel.title and panel.title:GetText() or '')
 print('OBSERVED','D detail title='..title,'description='..shown)
 C.expect(SaysAssigned(shown,'Gen plan',6,6) and not StatesProgress(shown,4,6),
  'D: the detail pane shows "Gen plan" at the current 6/6, not the frozen 4/6',shown)
 C.guard(title==OWNER_TITLE,"D: and the owner's title",title)
 C.guard(panel.linkSaveBtn:IsShown() and panel.linkSaveBtn:IsEnabled(),'D: Save Link is still offered on the own mirror')
 local other=ShowBuild(ids[2])
 C.setup(other~=nil,'D: fixture: the detail pane shows mirror 2')
 local text=V.Plain(other and other.desc and other.desc:GetText() or '')
 C.guard(text:find(NOTE2,1,true)~=nil,"D: mirror 2's detail pane shows the description its owner wrote",text)
end)

C.guard(Assignments()==ASSIGNED,'the Saved Build Wishlist assignments are unchanged',Assignments())
C.guard(#H.actions==0,'no game action in the second session: nothing was activated, saved or uploaded',#H.actions)
C.finish('(a title-only edit leaves a Saved Build mirror description generated; owner text and earlier-build markers are kept)')
