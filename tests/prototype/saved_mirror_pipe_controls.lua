-- Controls for the SPEC-R3-1 correction (core/CommunityController.lua
-- EditBuild): the display rule (no literal "|") applies to description text
-- the owner changes, not to the stored description a save re-submits
-- unchanged. The root reproduction saved_mirror_pipe_resubmit pins the two
-- refused saves; L and T below repeat them only as steps of the later checks.
-- Healthy behaviour (EXPECT, fails at 8a): on an own Saved Build mirror whose
-- generated description names its assigned server Wishlist "Fire|Frost plan",
-- Save Link saves the link and a title-only Save Details saves the owner's
-- title and keeps the link; a signature-changing re-import then describes
-- "Fire|Frost plan" at the current 6/6 under the owner's title and link, and
-- the detail pane shows that.
-- Unchanged (GUARD, holds at 8a): the detail pane shows the name with its "|"
-- doubled and no undoubled "|"; Save Link changes no text and marks no owner
-- edit; a title or a description the owner changes is still refused when it
-- holds a "|" (in the real Edit dialog, and through the controller with its
-- reason), including an owner edit of the generated text that keeps its "|",
-- and every refusal leaves the whole stored record as it was; the mirror keeps
-- its identity, server slot, verified owner, record and publication bindings
-- and assigned Wishlist; an ordinary owner edit (title and description without
-- "|") is saved and kept through a re-import and a later Save Link; no game or
-- network action.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, adapter, Saved import and Build Library window (detail pane,
-- link field, Save Link, Edit Build dialog) and the CommunityBuilds facade;
-- the format-5 saved fixture with Saved Build 1's assigned Wishlist stored as
-- "Fire|Frost plan", as in the root reproduction. Only the fake server Saved
-- Build changes. Artificial names and Discord-form links; nothing is sent.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('saved_mirror_pipe_controls')

local PLAN='Fire|Frost plan'
-- The same name as a display projection carries it (Identity.DisplaySafeText).
local SHOWN='Fire||Frost plan'
local NAME='Artificial Saved Build'
local LINK,LINK2='https://discord.com/channels/7/8/9','https://discord.com/channels/7/8/10'
local OWNER_TITLE='Artificial owner title'
local PIPE_TITLE='Artificial|owner title'
local PIPE_NOTE='Artificial owner note with a | in it.'
local OWNER_TITLE2,NOTE='Artificial second owner title','Artificial owner note written in the Edit dialog.'

-- An Echo row of harness Echo `id`, with the quality the harness catalog gives it.
local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end
-- Server Saved Build 1 measured against its assigned Wishlist (F.PLAN: 200001
-- x2, 200002 x3, 200003 x1): 2+second of the 6 copies, or all 6 with the third Echo.
local function Slot1(second,third)
 local rows={E(200001,2),E(200002,second)}
 if third then rows[3]=E(200003,1) end
 return rows
end
local H=F.Boot(F.Database({mutate=function(db) db.chars[F.NAME].loadoutWishlists[1].name=PLAN end}),function(h)
 h.perks.serverBuildSlots={[1]={name=NAME,verified=true,echoes=Slot1(1)}}
 h.perks.serverActiveSlot=1
end)
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

-- The mirror of server Saved Build 1, as the real Build Library reads it.
local function Mirror()
 local found
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==1 then found=b end
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
-- Every field of a value, nested tables included, in a stable order.
local function Dump(v,depth)
 depth=depth or 0
 if type(v)~='table' then return type(v)..':'..printable(v) end
 if depth>6 then return '<deep>' end
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=printable(k)..'='..Dump(v[k],depth+1) end
 return '{'..table.concat(out,',')..'}'
end

-- Does the text state progress progress/total ("p/t" or "p of t")?
local function StatesProgress(text,progress,total)
 local l=V.Plain(text)
 return l:find(string.format('%d/%d',progress,total),1,true)~=nil
  or l:find(string.format('%d of %d',progress,total),1,true)~=nil
end
-- Does the stored text name the assigned Wishlist, "|" as stored, at progress/total?
local function SaysAssigned(text,progress,total)
 return type(text)=='string' and text:find(PLAN,1,true)~=nil and StatesProgress(text,progress,total)
end
-- Is every "|" of the shown text, outside colour codes, doubled?
local function Escaped(shown)
 local bare=V.Plain(shown):gsub('||','')
 return bare:find('|',1,true)==nil
end

-- The server Saved Build changes; opening the Build Library again imports it
-- again (as in saved_mirror_title_only_description).
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
-- Edit Build again closes the open dialog and drops its draft.
local function CloseEdit(tag)
 local panel,popup=Panel(),NexusEditPopup
 if panel and popup and popup:IsShown() then panel.editBtn:Click() end
 C.setup(not (popup and popup:IsShown()),tag..': fixture: the Edit dialog is closed again')
end
-- Save Details, then wait until the Build Library serves what `saved` accepts.
local function SaveDetails(popup,saved)
 popup._saveBtn:Click()
 return Until(2000,function()
  local m=Mirror()
  return m~=nil and saved(m) and ImportIdle()
 end)~=nil
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
C.setup((A.GetLoadoutWishlist(1) or {}).name==PLAN,'fixture: Saved Build 1 is assigned the server Wishlist "'..PLAN..'"',
 (A.GetLoadoutWishlist(1) or {}).name)

local id
C.scenario('P the first import names "Fire|Frost plan" and the detail pane doubles its "|"',function()
 CB.Show()
 C.setup(Until(2000,function()
  local m=Mirror()
  return m~=nil and m.destinationProgress==3 and ImportIdle()
 end)~=nil,'P: fixture: Saved Build 1 is imported at 3/6 through the real Build Library facade')
 local m=Mirror() or {}
 id=m.id
 print('OBSERVED','P description='..printable(m.description))
 C.setup(m.userTitle==nil and m.title==NAME and SaysAssigned(m.description,3,6),
  'P: fixture: the unmarked mirror has the generated description of "'..PLAN..'" at 3/6',m.description)
 local panel=ShowBuild(id)
 C.setup(panel~=nil,'P: fixture: the Build Library detail pane shows the mirror')
 local shown=tostring(panel and panel.desc and panel.desc:GetText() or '')
 print('OBSERVED','P detail description='..shown)
 C.guard(shown:find(SHOWN,1,true)~=nil and Escaped(shown),
  'P: the detail pane shows the Wishlist name with its "|" doubled and no undoubled "|"',shown)
end)

C.scenario('L Save Link re-submits the stored generated description unchanged',function()
 C.setup(id~=nil,'L: fixture: the mirror has an ID')
 if not id then return end
 local panel=ShowBuild(id)
 C.setup(panel~=nil and panel.linkBox:IsShown() and panel.linkBox._nexusBoundBuildId==id
  and panel.linkSaveBtn:IsShown() and panel.linkSaveBtn:IsEnabled(),
  'L: fixture: the owner-only link field and Save Link are offered for the own mirror')
 if not panel then return end
 local before=Mirror() or {}
 C.setup(Type(panel.linkBox,LINK)==LINK,'L: fixture: the owner typed a link into the field')
 panel.linkSaveBtn:Click()
 C.expect(Until(2000,function()
  local m=Mirror()
  return m~=nil and m.link==LINK and ImportIdle()
 end)~=nil,'L: Save Link saves the link',(Mirror() or {}).link)
 local m=Mirror() or {}
 C.guard(m.description==before.description and m.title==before.title and m.userTitle==nil,
  'L: and changes no text and marks no owner edit',printable(m.userTitle))
end)

local titled
C.scenario('T the owner changes only the title in the real Edit dialog',function()
 local prior=Mirror() or {}
 local popup=OpenEdit('T',id)
 if not popup then return end
 local title,desc=popup._editTitleBox,popup._editDescBox
 C.setup(desc:_NexusRawText()==prior.description,
  'T: fixture: the description field holds the stored generated description exactly',desc:_NexusRawText())
 C.setup(Type(title,OWNER_TITLE)==OWNER_TITLE,'T: fixture: the owner typed a new title')
 C.expect(SaveDetails(popup,function(m) return m.title==OWNER_TITLE end),
  'T: Save Details saves the title-only edit',(Mirror() or {}).title)
 C.expect(not popup:IsShown(),'T: and closes the Edit dialog')
 local m=Mirror() or {}
 print('OBSERVED','T title='..printable(m.title),'description='..printable(m.description),'link='..printable(m.link),
  'witness stored='..printable((StoredRow(id) or {}).generatedDescriptionWitness~=nil))
 C.expect(m.userTitle==OWNER_TITLE,"T: the changed title is marked as the owner's",m.userTitle)
 C.expect(m.link==LINK,'T: the title-only edit keeps the saved link',m.link)
 C.guard(m.description==prior.description,'T: the description is the stored generated one, unchanged',m.description)
 C.guard(m.id==prior.id and m.importedSavedBuild==true and tonumber(m.serverSlot)==1,
  'T: the same mirror identity and server slot',m.id)
 C.guard(CB.IsOwnBuild(id)==true and m.ownerKey==F.OWNER and m.ownerVerified==true and m.isMine==true,
  "T: it stays the character's own verified mirror",printable(m.ownerKey)..'/'..printable(m.ownerVerified))
 C.guard(m.recordBuildId==prior.recordBuildId and m.publishedBuildId==prior.publishedBuildId,
  'T: its record and publication bindings are unchanged',printable(m.recordBuildId)..'/'..printable(m.publishedBuildId))
 C.guard(m.destinationWishlistName==PLAN,'T: and its assigned Wishlist',m.destinationWishlistName)
 titled=m.title==OWNER_TITLE and m or nil
 if popup:IsShown() then CloseEdit('T') end
end)

C.scenario('X a title or a description the owner changes with a "|" is still refused',function()
 local popup=OpenEdit('X',id)
 if not popup then return end
 local title,desc=popup._editTitleBox,popup._editDescBox
 local current=Mirror() or {}
 C.setup(StoredRow(id)~=nil,'X: fixture: the stored row of the mirror exists')
 local stored=Dump(StoredRow(id))
 C.setup(Type(title,PIPE_TITLE)==PIPE_TITLE and desc:_NexusRawText()==current.description,
  'X1: fixture: the owner typed a title with a "|" and left the generated description')
 popup._saveBtn:Click()
 C.guard(popup:IsShown() and Dump(StoredRow(id))==stored,
  'X1: Save Details refuses the title with a "|" and the whole stored record is as it was')
 C.setup(Type(title,current.title)==current.title and Type(desc,PIPE_NOTE)==PIPE_NOTE,
  'X2: fixture: the owner kept the title and typed a description with a "|"')
 popup._saveBtn:Click()
 C.guard(popup:IsShown() and Dump(StoredRow(id))==stored,
  'X2: Save Details refuses the description with a "|" and the whole stored record is as it was')
 CloseEdit('X')
 -- The controller, with its reasons: an edit of the generated text that keeps
 -- its "|" is owner text too.
 local cases={
  {'X3','title',PIPE_TITLE,nil,'title contains unsafe text'},
  {'X4','description',current.title,PIPE_NOTE,'description contains unsafe text'},
  {'X5','generated description',current.title,tostring(current.description)..' Owner note.',
   'description contains unsafe text'},
 }
 for _,case in ipairs(cases) do
  local ok,why=CB.EditBuild(id,case[3],case[4],nil)
  print('OBSERVED',case[1]..' changed '..case[2],'ok='..printable(ok),'why='..printable(why))
  C.guard(ok==false and why==case[5],case[1]..': EditBuild refuses a changed '..case[2]..' with a "|": '..case[5],
   printable(ok)..'/'..printable(why))
  C.guard(Dump(StoredRow(id))==stored,case[1]..': and the whole stored record is as it was')
 end
 local m=Mirror() or {}
 C.guard(m.title==current.title and m.description==current.description and m.link==current.link
  and m.userTitle==current.userTitle,'X: the served mirror keeps its title, description, link and owner marker',
  printable(m.title)..' / '..printable(m.description))
end)

C.scenario('S a signature-changing re-import after the title-only edit and the refusals',function()
 C.setup(titled~=nil,'S: fixture: the title-only edit was saved')
 local prior=Mirror() or {}
 ServerChange(function(slots) slots[1].echoes=Slot1(3,true) end)
 C.setup(Until(2000,function()
  local m=Mirror()
  return m~=nil and m.destinationProgress==6 and ImportIdle()
 end)~=nil,'S: fixture: the re-import stores the current progress 6/6 on the mirror')
 local m=Mirror() or {}
 print('OBSERVED','S description='..printable(m.description),'title='..printable(m.title),'link='..printable(m.link))
 C.expect(titled~=nil and SaysAssigned(m.description,6,6) and not StatesProgress(m.description,3,6),
  'S: after the title-only edit the description names "'..PLAN..'" at the current 6/6, not 3/6',m.description)
 C.expect(m.title==OWNER_TITLE and m.userTitle==OWNER_TITLE,"S: the owner's title is kept",m.title)
 C.expect(m.link==LINK,'S: and the saved link',m.link)
 C.guard(m.id==prior.id and m.importedSavedBuild==true and tonumber(m.serverSlot)==1,
  'S: the same mirror identity and server slot',m.id)
 C.guard(CB.IsOwnBuild(id)==true and m.ownerKey==F.OWNER and m.ownerVerified==true and m.isMine==true,
  "S: it stays the character's own verified mirror",printable(m.ownerKey)..'/'..printable(m.ownerVerified))
 C.guard(m.recordBuildId==prior.recordBuildId and m.publishedBuildId==prior.publishedBuildId,
  'S: its record and publication bindings are unchanged',printable(m.recordBuildId)..'/'..printable(m.publishedBuildId))
 C.guard(m.destinationWishlistName==PLAN,'S: and its assigned Wishlist',m.destinationWishlistName)
end)

C.scenario('D the detail pane after the re-import',function()
 local panel=ShowBuild(id)
 C.setup(panel~=nil,'D: fixture: the Build Library detail pane shows the mirror')
 if not panel then return end
 local shown=tostring(panel.desc and panel.desc:GetText() or '')
 local title=V.Plain(panel.title and panel.title:GetText() or '')
 print('OBSERVED','D detail title='..title,'description='..shown)
 C.expect(titled~=nil and shown:find(SHOWN,1,true)~=nil and StatesProgress(shown,6,6) and not StatesProgress(shown,3,6),
  'D: the detail pane shows "'..PLAN..'" at the current 6/6',shown)
 C.guard(Escaped(shown),'D: with every "|" doubled: no undoubled "|" reaches the pane',shown)
 C.expect(title==OWNER_TITLE,"D: and the owner's title",title)
end)

C.scenario('O an ordinary owner edit replaces the generated text and is kept',function()
 local prior=Mirror() or {}
 local popup=OpenEdit('O',id)
 if not popup then return end
 C.setup(Type(popup._editTitleBox,OWNER_TITLE2)==OWNER_TITLE2 and Type(popup._editDescBox,NOTE)==NOTE,
  'O: fixture: the owner typed a title and a description without "|"')
 C.guard(SaveDetails(popup,function(m) return m.title==OWNER_TITLE2 and m.description==NOTE end),
  'O: Save Details saves the ordinary edit',(Mirror() or {}).description)
 local m=Mirror() or {}
 C.guard(m.userTitle==OWNER_TITLE2 and m.link==prior.link,"O: the text is marked as the owner's and the link is kept",
  printable(m.userTitle)..'/'..printable(m.link))
 if popup:IsShown() then CloseEdit('O') end
 ServerChange(function(slots) slots[1].echoes=Slot1(2) end)
 C.setup(Until(2000,function()
  local again=Mirror()
  return again~=nil and again.destinationProgress==4 and ImportIdle()
 end)~=nil,'O: fixture: a re-import stores the new progress 4/6 on the mirror')
 m=Mirror() or {}
 print('OBSERVED','O after re-import title='..printable(m.title),'description='..printable(m.description))
 C.guard(m.title==OWNER_TITLE2 and m.description==NOTE,
  'O: the owner-written title and description are kept through the re-import',m.description)
 local panel=ShowBuild(id)
 C.setup(panel~=nil,'O: fixture: the detail pane shows the mirror')
 if not panel then return end
 C.setup(Type(panel.linkBox,LINK2)==LINK2,'O: fixture: the owner typed another link')
 panel.linkSaveBtn:Click()
 C.guard(Until(2000,function()
  local again=Mirror()
  return again~=nil and again.link==LINK2 and ImportIdle()
 end)~=nil,'O: Save Link on the owner-written text saves the link',(Mirror() or {}).link)
 m=Mirror() or {}
 C.guard(m.title==OWNER_TITLE2 and m.description==NOTE and m.userTitle==OWNER_TITLE2,
  'O: and keeps the owner-written title and description',m.description)
end)

C.guard((A.GetLoadoutWishlist(1) or {}).name==PLAN,'the Saved Build 1 assignment keeps its name with "|"',
 (A.GetLoadoutWishlist(1) or {}).name)
C.guard(#H.actions==0 and #H.sent==0,'no game or network action: nothing was activated, saved, uploaded or sent',
 #H.actions..'/'..#H.sent)
C.finish('(unchanged stored text is kept; owner-changed text with a "|" is refused; owner text and links are kept)')
